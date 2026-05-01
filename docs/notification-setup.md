# Notification Setup

Roost ships built-in notification integrations for Claude Code, Codex, Cursor CLI, and OpenCode where the corresponding provider integration is enabled under Settings -> Notifications.

This document is for everything else: sending notifications into Roost from a custom CLI, shell command, build script, or another agent.

## How Roost Receives Notifications

Roost currently listens on a Unix domain socket inherited from the Muxy storage layer:

```text
~/Library/Application Support/Muxy/muxy.sock
```

Terminals launched by Roost receive these compatibility environment variables:

| Variable | Description |
| --- | --- |
| `MUXY_SOCKET_PATH` | Unix socket path for notification messages. |
| `MUXY_PANE_ID` | Current terminal pane identifier. |
| `MUXY_PROJECT_ID` | Current project identifier. |
| `MUXY_WORKTREE_ID` | Current workspace/worktree identifier. |
| `MUXY_HOOK_SCRIPT` | Bundled hook script path when available. |

The `MUXY_*` names are the current integration contract for inherited hook scripts. Treat them as compatibility names, not product branding.

## Wire Format

One message per connection. The payload is a single UTF-8 line with four pipe-separated fields:

```text
<type>|<paneID>|<title>|<body>
```

| Field | Required | Description |
| --- | --- | --- |
| `type` | yes | Identifier for the source. Unknown values are accepted and shown generically. Built-in values include `claude_hook`, `codex`, `cursor`, and `opencode`. |
| `paneID` | yes | The pane the event belongs to. Use `$MUXY_PANE_ID` from inside a Roost terminal. Leave empty to attach the notification to the currently active pane. |
| `title` | yes | Shown as the notification title. If empty, Roost uses a default completion title. |
| `body` | no | Notification body. Must not contain `|` or newlines. Replace them first. |

Constraints:

- Max message size: 64 KB.
- The `|` character is the field separator; strip or replace it in user-supplied strings.
- Newlines terminate a message.

## Minimal Example: Shell

From inside a Roost terminal pane:

```bash
printf '%s|%s|%s|%s' \
    "custom" "$MUXY_PANE_ID" "Build finished" "All tests passed" \
    | nc -U "$MUXY_SOCKET_PATH"
```

Reusable helper:

```bash
roost_notify() {
    [ -z "${MUXY_SOCKET_PATH:-}" ] && return 0
    local title="${1:-Done}"
    local body="${2:-}"
    local safe_body
    safe_body=$(printf '%s' "$body" | tr '|\n\r' '   ' | head -c 500)
    printf '%s|%s|%s|%s' "custom" "${MUXY_PANE_ID:-}" "$title" "$safe_body" \
        | nc -U "$MUXY_SOCKET_PATH" 2>/dev/null || true
}

long-running-build && roost_notify "Build finished" "All tests passed"
```

## Minimal Example: Node.js

```javascript
import { createConnection } from "net"

function roostNotify(title, body = "") {
  const socketPath = process.env.MUXY_SOCKET_PATH
  const paneID = process.env.MUXY_PANE_ID || ""
  if (!socketPath) return
  const safeBody = String(body).replace(/[\n\r|]+/g, " ").slice(0, 500)
  const payload = `custom|${paneID}|${title}|${safeBody}`
  const conn = createConnection({ path: socketPath })
  conn.on("error", () => {})
  conn.write(payload, () => conn.end())
}
```

## Minimal Example: Python

```python
import os
import socket

def roost_notify(title: str, body: str = "") -> None:
    path = os.environ.get("MUXY_SOCKET_PATH")
    pane = os.environ.get("MUXY_PANE_ID", "")
    if not path:
        return
    safe_body = body.replace("|", " ").replace("\n", " ")[:500]
    payload = f"custom|{pane}|{title}|{safe_body}".encode("utf-8")
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
        s.connect(path)
        s.sendall(payload)
```

## Reference Implementations

The bundled integrations are templates for writing custom integrations:

- Shell hook: [`Muxy/Resources/scripts/muxy-claude-hook.sh`](../Muxy/Resources/scripts/muxy-claude-hook.sh)
- Shell hook: [`Muxy/Resources/scripts/muxy-codex-hook.sh`](../Muxy/Resources/scripts/muxy-codex-hook.sh)
- Shell hook: [`Muxy/Resources/scripts/muxy-cursor-hook.sh`](../Muxy/Resources/scripts/muxy-cursor-hook.sh)
- Node plugin: [`Muxy/Resources/scripts/opencode-muxy-plugin.js`](../Muxy/Resources/scripts/opencode-muxy-plugin.js)

## Tips

- **Fire and forget.** If Roost is not running or the socket does not exist, swallow the connection error rather than crashing your tool.
- **Do not block.** Open the connection, write the payload, close it. Roost does not send a response.
- **Sanitize.** Always strip `|`, `\n`, and `\r` from user or model-generated content before sending, and cap the body length.
- **Pane routing.** If you send from outside a Roost pane, omit `paneID`; Roost will route to the currently active pane of the active project.
- **Type strings.** Pick something descriptive for `type`. Unknown types still show with a generic source.

## Delivery Settings

Roost applies the user's choices under Settings -> Notifications:

- **Toast** — show an in-app banner.
- **Sound** — play a configured sound on arrival.
- **Position** — choose where the toast appears.

A dot also appears on project and workspace rows in the sidebar until the notification is read.
