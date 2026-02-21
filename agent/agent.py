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
    {
        "name": "get_overlay_logs",
        "description": (
            "Get console logs and errors from the overlay window. "
            "Shows console.log, console.warn, console.error output and uncaught exceptions. "
            "Use this to debug overlay issues."
        ),
        "input_schema": {
            "type": "object",
            "properties": {},
            "required": []
        }
    },
    {
        "name": "show_widget",
        "description": (
            "Show a floating widget panel at a position on the target window. "
            "Use to display contextual information like color swatches, JSON viewers, "
            "code snippets, or custom HTML widgets."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "widget_id": {"type": "string", "description": "Unique ID for this widget"},
                "type": {
                    "type": "string",
                    "description": "Widget type",
                    "enum": ["color_swatch", "json_viewer", "code_snippet", "custom_html"]
                },
                "x": {"type": "integer", "description": "X position in image pixels (2x retina)"},
                "y": {"type": "integer", "description": "Y position in image pixels (2x retina)"},
                "title": {"type": "string", "description": "Title for the widget window"},
                "config": {
                    "type": "object",
                    "description": (
                        "Widget config. color_swatch: {color: '#hex'}. json_viewer: {json: '{...}'}. "
                        "code_snippet: {code: '...', language: 'swift'}. custom_html: {html: '<div>...</div>', width: 300, height: 200}."
                    )
                }
            },
            "required": ["widget_id", "type", "x", "y", "title", "config"]
        }
    },
    {
        "name": "dismiss_widget",
        "description": "Dismiss a floating widget panel. Use widget_id='all' to dismiss all widgets.",
        "input_schema": {
            "type": "object",
            "properties": {
                "widget_id": {"type": "string", "description": "ID of widget to dismiss, or 'all'"}
            },
            "required": ["widget_id"]
        }
    },
    {
        "name": "read_editor_content",
        "description": (
            "Read the full text content from the focused text area or code editor in the target window. "
            "Returns the complete file/document text, not just what's visible on screen."
        ),
        "input_schema": {
            "type": "object",
            "properties": {},
            "required": []
        }
    },
    {
        "name": "run_javascript",
        "description": (
            "Execute JavaScript in the target browser's active tab and return the result. "
            "Works with Safari, Chrome, Arc, Brave, Edge. Use this to read page HTML "
            "(document.documentElement.outerHTML), get URLs (document.querySelectorAll('a')), "
            "interact with the DOM, or extract data from web pages. "
            "The JS expression should return a string value."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "javascript": {
                    "type": "string",
                    "description": "JavaScript code to execute in the browser tab"
                }
            },
            "required": ["javascript"]
        }
    },
    {
        "name": "visualize",
        "description": (
            "Render an interactive HTML visualization in the chat sidebar. "
            "Use to show visual representations of UI components, mockups, diagrams, etc."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "html": {"type": "string", "description": "Complete HTML content to render"},
                "title": {"type": "string", "description": "Label shown above the visualization"}
            },
            "required": ["html"]
        }
    },
    {
        "name": "launch_site_app",
        "description": (
            "Launch a pre-built site-specific app for the current webpage. "
            "These are rich interactive experiences built for specific websites. "
            "Pass the app_id and optionally the current page URL."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "app_id": {"type": "string", "description": "ID of the site app to launch"},
                "url": {"type": "string", "description": "Current page URL to pass to the app"}
            },
            "required": ["app_id"]
        }
    },
    {
        "name": "save_overlay",
        "description": (
            "Write overlay HTML to disk and display it. This is the primary way to create "
            "and iterate on persistent overlays. The HTML is written to "
            "~/.bones/apps/{domain}/{id}/overlay.html and immediately shown. "
            "Call again with the same id to update — edits go straight to disk and reload."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "id": {
                    "type": "string",
                    "description": "Slug ID for the overlay (e.g. 'game-spinner', 'pr-dashboard')"
                },
                "name": {
                    "type": "string",
                    "description": "Human-readable name (e.g. 'Game Spinner')"
                },
                "description": {
                    "type": "string",
                    "description": "Brief description of what the overlay does"
                },
                "html": {
                    "type": "string",
                    "description": "Full HTML content for the overlay"
                },
                "width": {
                    "type": "integer",
                    "description": "Width in pixels (default 400)"
                },
                "height": {
                    "type": "integer",
                    "description": "Height in pixels (default 300)"
                },
                "position": {
                    "type": "string",
                    "enum": ["top-left", "top-right", "center", "bottom-left"],
                    "description": "Overlay position on screen"
                }
            },
            "required": ["id", "name", "description", "html"]
        }
    },
    {
        "name": "read_overlay_source",
        "description": (
            "Read the HTML source of a saved overlay from disk. "
            "Use this to see the current state before making edits, "
            "then call save_overlay with the modified HTML."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "id": {
                    "type": "string",
                    "description": "ID of the saved overlay to read"
                }
            },
            "required": ["id"]
        }
    },
    {
        "name": "list_saved_overlays",
        "description": (
            "List all saved overlays for the current app/site. "
            "Returns overlay IDs, names, and descriptions."
        ),
        "input_schema": {
            "type": "object",
            "properties": {},
            "required": []
        }
    },
    {
        "name": "load_overlay",
        "description": (
            "Load a previously saved overlay from disk and display it. "
            "Use this to restore an overlay from a previous session."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "id": {
                    "type": "string",
                    "description": "ID of the saved overlay to load"
                }
            },
            "required": ["id"]
        }
    },
]

SYSTEM_PROMPT = """\
You are an AI assistant that can see and interact with the user's macOS screen. \
You are looking at a specific application window.

HOW TO INTERACT WITH THE APP:
1. take_screenshot(labeled=true) → see the app with 2-letter element codes (AA, AB, AC...)
2. click_code(code) → click elements by their code. ALWAYS prefer this over raw coordinates.
3. type_into_code(code, text) → type into input fields by code
4. key_combo(keys) → keyboard shortcuts e.g. ["cmd","p"], ["cmd","shift","f"]
5. find_elements(query) → search for elements when codes aren't visible
6. get_elements → see the full element code map

BROWSER TOOLS (when target is a web browser — Safari, Chrome, Arc, etc.):
- run_javascript(javascript) → execute JS in the browser tab, get results back
- IMPORTANT: Always wrap results in JSON.stringify() — raw DOM calls return nothing useful.
- Use ONE call with a comprehensive query rather than many small calls. Example:
  run_javascript("JSON.stringify([...document.querySelectorAll('a[href]')].map(a=>({t:a.textContent.trim().substring(0,60),h:a.href})).filter(a=>a.t&&a.h.startsWith('http')))")
- Other useful patterns:
  - Navigate: run_javascript("window.location.href='https://...'")
  - Click: run_javascript("document.querySelector('.btn').click()")
  - Page info: run_javascript("JSON.stringify({title:document.title,url:location.href})")

OVERLAY TOOLS:
You can create floating HTML/CSS/JS overlay windows above the target app using create_overlay. \
Overlays are standalone mini web apps.

Overlay JS API (window.bones.*):
- window.bones.close() → close/destroy this overlay
- window.bones.runJavaScript(js) → execute JS in the target browser tab (returns Promise with result)
- window.bones.navigate(url) → navigate the target browser to a URL
- window.bones.click(x, y) → click at coordinates in the target app
- window.bones.clickCode(code) → click a 2-letter element code
- window.bones.clickElement(label) → click element by accessibility label
- window.bones.typeText(text), window.bones.keyCombo(keys), etc.

CRITICAL OVERLAY RULES:
- When building overlays for browser pages, FIRST use run_javascript to extract real URLs, \
  links, and data from the page DOM. Then build the overlay with real <a href="..."> links \
  and real navigation — do NOT use window.bones.clickCode() for things that should be links.
- Overlays should be self-contained web apps. Use real HTML links, real onclick handlers, \
  real window.bones.navigate(url) for navigation — not proxy everything through bones click tools.
- Always give overlays a close button that calls window.bones.close().
- If something goes wrong, use get_overlay_logs to see console errors from the overlay.

PERSISTENT OVERLAYS:
- Use save_overlay to write overlay HTML directly to disk and display it. This is the preferred way \
  to build overlays that the user might want again — the files persist at ~/.bones/apps/{domain}/{id}/.
- To iterate: call read_overlay_source to get the current HTML, make edits, then save_overlay again.
- When saved overlays are available for the current site/app, offer to load them with load_overlay.
- For throwaway overlays, create_overlay is still fine. But for anything substantial, use save_overlay.

RULES:
- ALWAYS take a labeled screenshot first to see available element codes.
- ALWAYS use click_code instead of raw click(x,y) for interacting with the target app.
- When on a browser, use run_javascript to read page data and build overlays with real links.
- After performing actions, take another screenshot to verify the result.
- Briefly describe what you see before and after taking actions.
"""

# ---------------------------------------------------------------------------
# Agent
# ---------------------------------------------------------------------------

class Agent:
    def __init__(self, api_key: str):
        self.client = anthropic.Anthropic(api_key=api_key)
        self.messages = []
        self.cancelled = False
        self._pending_user_messages = []  # buffered user messages received during tool execution

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
        if msg.get("page_url"):
            content.append({"type": "text", "text": f"Page URL: {msg['page_url']}"})
        if msg.get("site_apps"):
            apps_text = "AVAILABLE SITE APPS for this page:\n"
            for app in msg["site_apps"]:
                apps_text += f"- {app['name']} (id: {app['id']}): {app['description']}\n"
            apps_text += (
                "\nYou should proactively offer to launch these apps for the user. "
                "Use launch_site_app(app_id='...') to launch. "
                "Pass the page URL as the 'url' parameter."
            )
            content.append({"type": "text", "text": apps_text})
        if msg.get("saved_overlays"):
            saved_text = "SAVED OVERLAYS for this site/app:\n"
            for ov in msg["saved_overlays"]:
                saved_text += f"- {ov['name']} (id: {ov['id']}): {ov['description']}\n"
            saved_text += (
                "\nOffer to load these for the user. "
                "Use load_overlay(id='...') to restore a saved overlay instantly."
            )
            content.append({"type": "text", "text": saved_text})
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

    def _read_tool_result(self):
        """Read messages from stdin until we get a tool_result or cancel.

        User messages that arrive during tool execution are buffered
        in self._pending_user_messages for later processing.
        """
        while True:
            msg = read_message()
            if msg is None:
                return None

            msg_type = msg.get("type")
            if msg_type == "tool_result":
                return msg
            elif msg_type == "cancel":
                return msg
            elif msg_type == "user_message":
                # Buffer for later — user typed while we were waiting for a tool result
                self._pending_user_messages.append(msg)
                log(f"buffered user message during tool execution: {msg.get('text', '')[:50]}")
            else:
                log(f"unexpected message during tool wait: {msg_type}")

    def _repair_messages(self):
        """Ensure every assistant tool_use has a matching tool_result.

        If the conversation got corrupted (e.g. crash, race condition),
        this injects placeholder tool_results so the API call won't fail.
        """
        i = 0
        while i < len(self.messages):
            msg = self.messages[i]
            if msg["role"] == "assistant":
                # Collect tool_use IDs from this assistant message
                tool_use_ids = []
                for block in msg.get("content", []):
                    if isinstance(block, dict) and block.get("type") == "tool_use":
                        tool_use_ids.append(block["id"])

                if tool_use_ids:
                    # Check if the next message has matching tool_results
                    next_msg = self.messages[i + 1] if i + 1 < len(self.messages) else None
                    existing_result_ids = set()
                    if next_msg and next_msg["role"] == "user":
                        for block in next_msg.get("content", []):
                            if isinstance(block, dict) and block.get("type") == "tool_result":
                                existing_result_ids.add(block.get("tool_use_id"))

                    missing_ids = [tid for tid in tool_use_ids if tid not in existing_result_ids]
                    if missing_ids:
                        log(f"repairing {len(missing_ids)} missing tool_result(s)")
                        repair_content = [
                            {
                                "type": "tool_result",
                                "tool_use_id": tid,
                                "content": [{"type": "text", "text": "[No result — interrupted]"}],
                                "is_error": True
                            }
                            for tid in missing_ids
                        ]
                        if next_msg and next_msg["role"] == "user":
                            # Prepend missing results to existing user message
                            next_msg["content"] = repair_content + next_msg.get("content", [])
                        else:
                            # Insert a new user message with tool_results
                            self.messages.insert(i + 1, {"role": "user", "content": repair_content})
            i += 1

    def run_turn(self):
        """Agent loop — stream response, handle tool calls, repeat."""
        max_iterations = 20
        for _ in range(max_iterations):
            if self.cancelled:
                return

            # Repair any corrupted conversation state before calling the API
            self._repair_messages()

            send_message({"type": "streaming_start"})
            full_text = ""
            tool_uses = []

            try:
                with self.client.messages.stream(
                    model="claude-opus-4-6",
                    max_tokens=16384,
                    system=SYSTEM_PROMPT,
                    tools=NATIVE_TOOLS,
                    messages=self.messages
                ) as stream:
                    for event in stream:
                        if self.cancelled:
                            send_message({"type": "streaming_end"})
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
                aborted = False
                for tu in tool_uses:
                    if self.cancelled or aborted:
                        tool_results.append({
                            "type": "tool_result",
                            "tool_use_id": tu["id"],
                            "content": [{"type": "text", "text": "[Cancelled]"}],
                            "is_error": True
                        })
                        continue

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

                    # Block-read the tool_result from Swift (skips interleaved user messages)
                    result_msg = self._read_tool_result()
                    if result_msg is None:
                        aborted = True
                        tool_results.append({
                            "type": "tool_result",
                            "tool_use_id": tu["id"],
                            "content": [{"type": "text", "text": "[Connection lost]"}],
                            "is_error": True
                        })
                        continue

                    if result_msg.get("type") == "cancel":
                        self.cancelled = True
                        tool_results.append({
                            "type": "tool_result",
                            "tool_use_id": tu["id"],
                            "content": [{"type": "text", "text": "[Cancelled]"}],
                            "is_error": True
                        })
                        continue

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

                # Always append tool results so the conversation stays valid
                self.messages.append({"role": "user", "content": tool_results})

                if self.cancelled or aborted:
                    send_message({"type": "done"})
                    return
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
                # Process any user messages that were buffered during tool execution
                while agent._pending_user_messages:
                    buffered = agent._pending_user_messages.pop(0)
                    log(f"processing buffered user message")
                    agent.cancelled = False
                    agent.handle_user_message(buffered)
            else:
                send_message({"type": "error", "message": "Agent not initialized"})

        elif msg_type == "cancel":
            if agent:
                agent.cancel()

        else:
            log(f"unknown message type: {msg_type}")


if __name__ == "__main__":
    main()
