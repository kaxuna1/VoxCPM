# Voice AI Agent with Tool Calling — Design Spec

## Goal

Add an AI agent to PushToTalkSTT that detects a configurable trigger word in transcribed text, sends the command to MiniMax M2.7 Highspeed with tool definitions, and executes the chosen tool on the user's Mac.

## Flow

```
User speaks → Parakeet transcribes → Check for trigger word →
  YES: Strip trigger word → Send to MiniMax with tools → Execute tool result
  NO: Inject text as normal (current behavior)
```

## Trigger Word

- Default: "Hey"
- Detection: case-insensitive prefix match after trimming whitespace
- The trigger word + any trailing comma/space is stripped before sending to MiniMax
- Example: "Hey, open Google Chrome" → LLM receives "open Google Chrome"
- Stored in `UserDefaults` key: `agentTriggerWord`
- Configurable in Settings → AI Agent tab
- Agent can be disabled entirely via a toggle (UserDefaults: `agentEnabled`, default true)

## MiniMax Client

- **Base URL:** `https://api.minimax.chat/v1/chat/completions`
- **Model:** `MiniMax-M2.7-highspeed`
- **Auth:** `Authorization: Bearer <key>` — key stored in UserDefaults key `minimaxApiKey`
- **Format:** OpenAI-compatible. Request includes `model`, `messages`, `tools` array. Response includes `choices[0].message.tool_calls` or `choices[0].message.content`.
- **Timeout:** 10 seconds
- **System prompt:** Instructs the LLM it's a voice assistant, should pick the most appropriate tool for the user's request, or use `type_text` if the request is just text to type.
- **Fallback:** If MiniMax returns an error, times out, or no API key is configured, fall back to typing the raw text and show a warning notification.

### Request Format

```json
{
  "model": "MiniMax-M2.7-highspeed",
  "messages": [
    {"role": "system", "content": "<system prompt>"},
    {"role": "user", "content": "<transcribed text without trigger word>"}
  ],
  "tools": [<tool definitions>],
  "tool_choice": "auto"
}
```

### Response Handling

- If `finish_reason == "tool_calls"`: parse `tool_calls[0].function.name` and `tool_calls[0].function.arguments` (JSON string), look up in tool registry, execute handler.
- If `finish_reason == "stop"` with text content: the LLM decided this is plain text, inject via TextInjector.
- If error or timeout: inject raw text as fallback, show notification.

## System Prompt

```
You are a voice assistant running on macOS. The user speaks commands and you decide which tool to call.

Rules:
- Pick the most appropriate tool for the user's request
- If the user wants text typed/written, use the type_text tool
- If unsure, use type_text with the original text
- Only call one tool per request
- Keep tool arguments concise and accurate
```

## Tools (10)

| # | Function Name | Description | Parameters | Implementation |
|---|--------------|-------------|------------|----------------|
| 1 | `open_application` | Open a macOS application by name | `name: String` | `NSWorkspace.shared.open(URL)` using app URL from bundle |
| 2 | `open_url` | Open a URL in the default browser | `url: String` | `NSWorkspace.shared.open(URL)` |
| 3 | `search_google` | Search Google for a query | `query: String` | Open `https://www.google.com/search?q=<encoded query>` |
| 4 | `run_shell_command` | Run a shell command in zsh | `command: String` | `Process()` with `/bin/zsh -c <command>` |
| 5 | `toggle_music` | Play or pause Apple Music | (none) | AppleScript: `tell application "Music" to playpause` |
| 6 | `set_volume` | Set system volume | `level: Int` (0-100) | AppleScript: `set volume output volume <level>` |
| 7 | `toggle_dark_mode` | Toggle macOS dark/light mode | (none) | AppleScript: tell System Events to toggle dark mode |
| 8 | `create_file` | Create a file with content | `path: String, content: String` | `FileManager.default.createFile` |
| 9 | `read_clipboard` | Read current clipboard text and speak/type it | (none) | `NSPasteboard.general.string(forType: .string)` then type it |
| 10 | `type_text` | Type text into the active application | `text: String` | `TextInjector.inject(text)` — fallback when no action needed |

### Tool Definition Format (OpenAI-compatible)

Each tool is defined as:
```json
{
  "type": "function",
  "function": {
    "name": "open_application",
    "description": "Open a macOS application by name",
    "parameters": {
      "type": "object",
      "properties": {
        "name": {"type": "string", "description": "Application name, e.g. 'Google Chrome', 'Terminal', 'Finder'"}
      },
      "required": ["name"]
    }
  }
}
```

### Tool Registry Architecture

```swift
struct ToolDefinition {
    let name: String
    let description: String
    let parameters: [[String: Any]]  // JSON Schema for OpenAI tools format
    let handler: ([String: String]) async -> ToolResult
}

struct ToolResult {
    let success: Bool
    let message: String
}
```

Tools are stored in an array. Adding a new tool = appending one `ToolDefinition`. The tool definitions are serialized to JSON for the MiniMax request. The handler closure executes the actual macOS action.

## Overlay & UX

- When agent is processing (after trigger word detected), show `.processing` overlay phase (existing teal brain spinner) with label "Thinking..."
- After tool execution: hide overlay, show notification with tool result (e.g., "Opened Google Chrome" or "Volume set to 50%")
- If no API key configured and trigger word used: show notification "MiniMax API key not set. Configure in Settings."

## Settings

New "AI Agent" tab in Settings window:

- **Enable Agent** — toggle (default: on)
- **Trigger Word** — text field (default: "Hey")
- **MiniMax API Key** — secure text field
- **Model** — text field (default: "MiniMax-M2.7-highspeed"), in case user wants to change model
- **Test Connection** — button that sends a test message and shows "Connected" or error

## Files

| Action | File | Purpose |
|--------|------|---------|
| Create | `PushToTalkSTT/MiniMaxClient.swift` | OpenAI-compatible HTTP client for MiniMax API |
| Create | `PushToTalkSTT/AgentManager.swift` | Trigger word detection, tool dispatch, orchestration |
| Create | `PushToTalkSTT/AgentTools.swift` | 10 tool definitions + handler implementations |
| Modify | `PushToTalkSTT/AppDelegate.swift` | Route transcription through AgentManager before injection |
| Modify | `PushToTalkSTT/SettingsView.swift` | Add AI Agent settings tab |

## Recording Flow Change

In `AppDelegate.stopRecording`, after getting the transcription result:

```
1. Check if agent is enabled AND trigger word matches
2. YES:
   a. Strip trigger word from text
   b. Show .processing overlay
   c. Send to AgentManager.process(text)
   d. AgentManager calls MiniMax with tools
   e. Parse response: tool_call or plain text
   f. Execute tool handler or inject text
   g. Hide overlay, show notification
3. NO:
   a. Continue existing flow (post-processing, injection)
```

## Security Considerations

- `run_shell_command` is powerful — the LLM could be tricked into running destructive commands. For v1, we trust the user's intent since they explicitly say the trigger word. Future: add a confirmation dialog for shell commands.
- API key is stored in UserDefaults (not Keychain) for simplicity. Future: migrate to Keychain.
- No commands are executed without the user explicitly speaking the trigger word first.

## Out of Scope

- Multi-turn conversation (agent executes one tool per voice command)
- Tool chaining (calling multiple tools in sequence)
- Custom tool definitions via config file (architecture supports it, UI doesn't)
- Confirmation dialogs before execution
- Voice feedback / TTS for agent responses
