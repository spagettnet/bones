#!/usr/bin/env python3
"""Bones agent — Python subprocess that drives the conversation with Claude.

Communicates with the Swift host via JSON Lines on stdin/stdout.
Logs go to stderr (forwarded to BoneLog by Swift).
"""
import json
import sys
import base64
import anthropic

# ---------------------------------------------------------------------------
# IPC helpers
# ---------------------------------------------------------------------------

def read_message():
    """Block-read one JSON line from stdin."""
    line = sys.stdin.readline()
    if not line:
        return None
    return json.loads(line)


def send_message(msg: dict):
    """Write one JSON line to stdout and flush immediately."""
    sys.stdout.write(json.dumps(msg, separators=(",", ":")) + "\n")
    sys.stdout.flush()


def log(text: str):
    """Write to stderr — Swift captures this and routes to BoneLog."""
    sys.stderr.write(f"[agent] {text}\n")
    sys.stderr.flush()

# ---------------------------------------------------------------------------
# Tool schemas (sent to Claude as tool definitions)
# ---------------------------------------------------------------------------

NATIVE_TOOLS = [
    {
        "name": "take_screenshot",
        "description": (
            "Take a screenshot. target: 'app' (default), 'overlay', or 'both'. "
            "Set labeled=true to annotate with 2-letter element codes."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "target": {
                    "type": "string",
                    "enum": ["app", "overlay", "both"],
                    "description": "What to capture"
                },
                "labeled": {
                    "type": "boolean",
                    "description": "Annotate with 2-letter element codes"
                }
            },
            "required": []
        }
    },
    {
        "name": "click_code",
        "description": (
            "Click a UI element by its 2-letter Homerow code (e.g. 'AA', 'BF'). "
            "ALWAYS prefer this over raw click. Use take_screenshot(labeled=true) or "
            "get_elements to see available codes."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "code": {
                    "type": "string",
                    "description": "2-letter element code (e.g. 'AA', 'BF')"
                }
            },
            "required": ["code"]
        }
    },
    {
        "name": "type_into_code",
        "description": (
            "Click an input field by its 2-letter code, then type text into it."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "code": {
                    "type": "string",
                    "description": "2-letter element code for the input field"
                },
                "text": {
                    "type": "string",
                    "description": "Text to type"
                }
            },
            "required": ["code", "text"]
        }
    },
    {
        "name": "click",
        "description": (
            "Click at raw image-pixel coordinates. ONLY use as a fallback when "
            "click_code is not possible (element has no code). Coordinates are in "
            "the 2x retina screenshot space."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "x": {"type": "integer", "description": "X coordinate in image pixels"},
                "y": {"type": "integer", "description": "Y coordinate in image pixels"}
            },
            "required": ["x", "y"]
        }
    },
    {
        "name": "type_text",
        "description": "Type text at the current cursor position.",
        "input_schema": {
            "type": "object",
            "properties": {
                "text": {"type": "string", "description": "Text to type"}
            },
            "required": ["text"]
        }
    },
    {
        "name": "scroll",
        "description": "Scroll at a position.",
        "input_schema": {
            "type": "object",
            "properties": {
                "x": {"type": "integer", "description": "X coordinate in image pixels"},
                "y": {"type": "integer", "description": "Y coordinate in image pixels"},
                "direction": {
                    "type": "string",
                    "enum": ["up", "down"],
                    "description": "Scroll direction"
                },
                "amount": {
                    "type": "integer",
                    "description": "Number of scroll lines (default 3)"
                }
            },
            "required": ["x", "y", "direction"]
        }
    },
    {
        "name": "key_combo",
        "description": (
            "Press a keyboard shortcut. Pass modifier keys (cmd, ctrl, shift, alt/option) "
            "plus one main key. Examples: ['cmd','c'], ['cmd','shift','f'], ['return']."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "keys": {
                    "type": "array",
                    "items": {"type": "string"},
                    "description": "Array of key names"
                }
            },
            "required": ["keys"]
        }
    },
    {
        "name": "get_elements",
        "description": (
            "Get the full list of labeled elements with their 2-letter codes, roles, "
            "labels, and screen frames."
        ),
        "input_schema": {
            "type": "object",
            "properties": {},
            "required": []
        }
    },
    {
        "name": "find_elements",
        "description": (
            "Search the accessibility tree for elements matching a keyword. "
            "Returns matching elements with roles, labels, and frames."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "query": {
                    "type": "string",
                    "description": "Search keyword (case-insensitive partial match)"
                }
            },
            "required": ["query"]
        }
    },
    {
        "name": "create_overlay",
        "description": (
            "Create a dynamic HTML/CSS/JS overlay window floating above the target app. "
            "The overlay has access to window.bones.* bridge APIs."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "html": {"type": "string", "description": "HTML content"},
                "width": {"type": "integer", "description": "Width in pixels (default 400)"},
                "height": {"type": "integer", "description": "Height in pixels (default 300)"},
                "position": {
                    "type": "string",
                    "enum": ["top-left", "top-right", "center", "bottom-left"],
                    "description": "Overlay position"
                }
            },
            "required": ["html"]
        }
    },
    {
        "name": "update_overlay",
        "description": "Update an existing overlay with new HTML or execute JavaScript.",
        "input_schema": {
            "type": "object",
            "properties": {
                "html": {"type": "string", "description": "New HTML content (replaces existing)"},
                "javascript": {"type": "string", "description": "JavaScript to execute in overlay"}
            },
            "required": []
        }
    },
    {
        "name": "destroy_overlay",
        "description": "Remove the overlay window.",
        "input_schema": {
            "type": "object",
            "properties": {},
            "required": []
        }
    },
]

SYSTEM_PROMPT = """\
You are an AI assistant that can see and interact with the user's macOS screen. \
You are looking at a specific application window.

HOW TO INTERACT:
1. take_screenshot(labeled=true) → see the app with 2-letter element codes (AA, AB, AC...)
2. click_code(code) → click elements by their code. ALWAYS use this. NEVER guess coordinates.
3. type_into_code(code, text) → type into input fields by code
4. key_combo(keys) → keyboard shortcuts e.g. ["cmd","p"], ["cmd","shift","f"]
5. find_elements(query) → search for elements when codes aren't visible
6. get_elements → see the full element code map

RULES:
- ALWAYS take a labeled screenshot first to see available element codes.
- ALWAYS use click_code instead of raw click. Only use click(x,y) as an absolute last resort.
- After performing actions, take another screenshot to verify the result.
- Briefly describe what you see before and after taking actions.

You also have overlay tools. You can create dynamic HTML/CSS/JS UI overlays that float \
above the target window. Overlays have access to window.bones.* APIs that can interact \
with the target app. Use create_overlay to build interactive tools, dashboards, or controls. \
Use update_overlay to modify them, and destroy_overlay to remove them.
"""

# ---------------------------------------------------------------------------
# Agent
# ---------------------------------------------------------------------------

class Agent:
    def __init__(self, api_key: str):
        self.client = anthropic.Anthropic(api_key=api_key)
        self.messages = []
        self.cancelled = False

    def handle_init(self, msg: dict):
        """Process init message with screenshot + element codes."""
        content = []
        if msg.get("screenshot_base64"):
            content.append({
                "type": "image",
                "source": {
                    "type": "base64",
                    "media_type": msg.get("screenshot_media_type", "image/png"),
                    "data": msg["screenshot_base64"]
                }
            })
        if msg.get("element_codes"):
            codes_text = "Element codes:\n" + "\n".join(
                f"[{e['code']}] {e.get('type','?')}: \"{e.get('label', e.get('role','?'))}\""
                for e in msg["element_codes"]
            )
            content.append({"type": "text", "text": codes_text})
        content.append({
            "type": "text",
            "text": "Here is the current state of the window. What do you see?"
        })
        self.messages.append({"role": "user", "content": content})
        self.run_turn()

    def handle_user_message(self, msg: dict):
        """Process user chat message."""
        self.messages.append({
            "role": "user",
            "content": [{"type": "text", "text": msg["text"]}]
        })
        self.run_turn()

    def run_turn(self):
        """Agent loop — stream response, handle tool calls, repeat."""
        max_iterations = 20
        for _ in range(max_iterations):
            if self.cancelled:
                return

            send_message({"type": "streaming_start"})
            full_text = ""
            tool_uses = []

            try:
                with self.client.messages.stream(
                    model="claude-sonnet-4-5-20250929",
                    max_tokens=4096,
                    system=SYSTEM_PROMPT,
                    tools=NATIVE_TOOLS,
                    messages=self.messages
                ) as stream:
                    for event in stream:
                        if self.cancelled:
                            return

                        if event.type == "content_block_start":
                            if hasattr(event.content_block, "id") and event.content_block.type == "tool_use":
                                tool_uses.append({
                                    "id": event.content_block.id,
                                    "name": event.content_block.name,
                                    "input_json": ""
                                })

                        elif event.type == "content_block_delta":
                            if hasattr(event.delta, "text"):
                                full_text += event.delta.text
                                send_message({"type": "text_delta", "text": event.delta.text})
                            elif hasattr(event.delta, "partial_json"):
                                if tool_uses:
                                    tool_uses[-1]["input_json"] += event.delta.partial_json

                    # Get the final message for stop_reason
                    final = stream.get_final_message()
                    stop_reason = final.stop_reason

            except Exception as e:
                log(f"API error: {e}")
                send_message({"type": "streaming_end"})
                send_message({"type": "error", "message": str(e)})
                return

            send_message({"type": "streaming_end"})

            if full_text:
                send_message({"type": "assistant_message", "text": full_text})

            # Build assistant message for conversation history
            assistant_content = []
            if full_text:
                assistant_content.append({"type": "text", "text": full_text})
            for tu in tool_uses:
                try:
                    tool_input = json.loads(tu["input_json"]) if tu["input_json"] else {}
                except json.JSONDecodeError:
                    tool_input = {}
                assistant_content.append({
                    "type": "tool_use",
                    "id": tu["id"],
                    "name": tu["name"],
                    "input": tool_input
                })
            if assistant_content:
                self.messages.append({"role": "assistant", "content": assistant_content})

            # Handle tool calls
            if stop_reason == "tool_use" and tool_uses:
                tool_results = []
                for tu in tool_uses:
                    if self.cancelled:
                        return
                    try:
                        tool_input = json.loads(tu["input_json"]) if tu["input_json"] else {}
                    except json.JSONDecodeError:
                        tool_input = {}

                    # Send tool_use to Swift for native execution
                    send_message({
                        "type": "tool_use",
                        "id": tu["id"],
                        "name": tu["name"],
                        "input": tool_input
                    })

                    # Block-read the tool_result from Swift
                    result_msg = read_message()
                    if result_msg is None or self.cancelled:
                        return

                    if result_msg.get("type") == "cancel":
                        self.cancelled = True
                        return

                    # Build tool_result content
                    result_content = []
                    result = result_msg.get("result", {})
                    if result.get("text"):
                        result_content.append({"type": "text", "text": result["text"]})
                    if result.get("image_base64"):
                        result_content.append({
                            "type": "image",
                            "source": {
                                "type": "base64",
                                "media_type": result.get("media_type", "image/png"),
                                "data": result["image_base64"]
                            }
                        })
                    if not result_content:
                        result_content.append({"type": "text", "text": "(no output)"})

                    tool_results.append({
                        "type": "tool_result",
                        "tool_use_id": tu["id"],
                        "content": result_content,
                        "is_error": result.get("is_error", False)
                    })

                self.messages.append({"role": "user", "content": tool_results})
                # Continue the loop for the next turn
            else:
                # end_turn — done
                send_message({"type": "done"})
                return

        # Max iterations reached
        send_message({"type": "done"})

    def cancel(self):
        self.cancelled = True

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    log("agent started, waiting for init...")
    agent = None

    while True:
        msg = read_message()
        if msg is None:
            log("stdin closed, exiting")
            break

        msg_type = msg.get("type")
        log(f"received: {msg_type}")

        if msg_type == "init":
            agent = Agent(api_key=msg["api_key"])
            agent.handle_init(msg)

        elif msg_type == "user_message":
            if agent:
                agent.cancelled = False
                agent.handle_user_message(msg)
            else:
                send_message({"type": "error", "message": "Agent not initialized"})

        elif msg_type == "cancel":
            if agent:
                agent.cancel()

        else:
            log(f"unknown message type: {msg_type}")


if __name__ == "__main__":
    main()
