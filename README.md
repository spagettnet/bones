Demo



https://github.com/user-attachments/assets/2414cf58-a2b3-477d-9be0-81c27df180d0



 Overview

  Bones is a macOS menu bar tool that replaces the traditional AI chat window with an agent-driven interaction model that can see your screen and collaborate with you on it. A pixel-art skeleton lives in your menu bar — grab him with your
   mouse and drag him onto any app window.

  Drop him on a window and suddenly Bones (powered by Claude) can see your app or web page in real-time and interact with it directly — with its own mouse and keyboard, as well as a variety of tools that let it create Just-in-Time (JIT)
  UI, generating widgets, overlays, or even running connected apps on the fly based on what you're doing.

  Bones is proactive (based on what it thinks would be useful) or reactive (based on what you ask for). It's also extensible through skills and apps based on the context it sees — if it sees a Partiful website, for example, it can use an
  installed Partiful skill + app which guides the generation and available actions, so knowledge and abilities can be grabbed on the fly.

  As Bones generates UI to fit your current view, it can accomplish tasks for you, collaborate with you, and customize your desktop — being both a helpful AI agent and a direct layer that augments your abilities, for fun or profit.

  ---
  Technologies, Frameworks & Libraries

  Native macOS (Swift / AppKit)

  - Swift 6.2 — compiled directly via swiftc, no Xcode project
  - AppKit — menu bar, sidebar, overlays, and floating widget panels
  - ScreenCaptureKit — high-fidelity window capture at 2x retina resolution
  - CoreGraphics / CGEvent — mouse click, scroll, and keyboard event synthesis
  - ApplicationServices / Accessibility APIs (AXUIElement) — full accessibility tree traversal for element discovery and targeting

  Python Agent

  - Anthropic SDK with Claude Opus 4.6 — streaming, tool use, and multimodal vision
  - Extensible through contextual Skills — pluggable skill modules that activate based on what Bones sees on screen

  ---
  Towards Intelligence-Driven HIT UI

  The entire stack is designed so Claude can be proactive and drive the interface directly on your desktop with just-in-time augmentations.

  - Accessibility API integration gives Claude a structured understanding of any app's UI — roles, labels, frames, 2-letter element codes — in addition to visual data from viewing the screen.
  - The overlay system lets Claude generate arbitrary interactive UI on the fly — dashboards, controls, visualizations — that can call back into native app interaction through the window.bones.* bridge.
  - The content change detector proactively feeds Claude visual updates without user prompting, so the agent stays aware of what you're doing.
  - The widget system lets Claude place contextual information (color swatches from a design tool, JSON from an API response, code snippets) at precise screen locations anchored to the elements they reference.
  - The run_javascript tool gives Claude deep access to browser DOM for web-based workflows.

  Claude's reasoning determines what UI exists, where it appears, and what it does.

---

## <img src="https://redis.io/wp-content/uploads/2024/04/Logotype.svg?auto=webp&quality=85,75&width=120" alt="Redis" height="20"> Shared Overlay Store

Overlays can be shared across Bones sessions via **Redis Vector Search**. Build an overlay once — share it everywhere.

### How it works

```
You build a PR dashboard on github.com
        |
        v
   publish_overlay  ──>  Redis (with vector embedding)
        |
        v
Next session on github.com discovers it automatically
        |
        v
Someone on gitlab.com finds it via semantic search and adapts it
```

### Setup

Redis Stack is required for the vector search + JSON modules:

```bash
# Option A: brew
brew install redis-stack
redis-stack-server

# Option B: Docker
docker run -d -p 6379:6379 redis/redis-stack
```

Embeddings use the **Voyage AI API** (`voyage-3-lite`, 512 dimensions). Set `VOYAGE_API_KEY` in your environment, or it falls back to your Anthropic API key.

### Tools

| Tool | Description |
|------|-------------|
| `publish_overlay` | Share a saved overlay to Redis with tags for discovery |
| `search_shared_overlays` | Find overlays — `exact` (same domain) or `similar` (semantic cross-domain) |
| `download_shared_overlay` | Fetch from Redis, save locally, and display |

### Example

```
You: "publish this overlay"
Bones: Published to shared store: bones:overlay:github.com:pr-dashboard

--- new session on github.com ---

Bones: "I found shared overlays for this site:
        - PR Dashboard (key: bones:overlay:github.com:pr-dashboard)
        Would you like to load it?"
```
