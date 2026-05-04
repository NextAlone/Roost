# Notification Setup

Roost ships built-in integrations for **Claude Code**, **Codex**, **Cursor**, and **OpenCode**. Toggle them under **Settings → Notifications**.

This document is for everything else: sending notifications into Roost from **any other tool** (a custom CLI, a shell command, a build script, a different AI agent, etc.).

## How Roost Receives Notifications

Roost listens on a Unix domain socket:

```
~/Library/Application Support/Roost/roost.sock
```

The socket path is exported to every terminal Roost spawns as `ROOST_SOCKET_PATH`, along with a per-pane identifier `ROOST_PANE_ID`. Any process running inside a Roost terminal pane can read these and send a message. Legacy `MUXY_*` aliases are still exported for existing integrations.

## Wire Format

One message per connection. The payload is a single UTF-8 line with four pipe-separated fields:

```
<type>|<paneID>|<title>|<body>
```

| Field    | Required | Description                                                                 |
| -------- | -------- | --------------------------------------------------------------------------- |
| `type`   | yes      | Identifier for the source. Unknown values are accepted and shown generically. Built-in values: `claude_hook`, `opencode`. |
| `paneID` | yes      | The pane the event belongs to. Use `$ROOST_PANE_ID` when sending from inside a Roost terminal. Leave empty to attach the notification to the currently active pane. |
| `title`  | yes      | Shown as the notification title. If empty, Roost uses `Task completed!`.     |
| `body`   | no       | Notification body. Must not contain `\|` or newlines — replace them first.   |

Constraints:

- Max message size: **64 KB**.
- The `|` character is the field separator — strip or replace it in user-supplied strings.
- Newlines terminate a message; you can send multiple messages on one connection by separating them with `\n`.

## Minimal Example — Shell

From anywhere inside a Roost terminal pane:

```bash
printf '%s|%s|%s|%s' \
    "custom" "$ROOST_PANE_ID" "Build finished" "All tests passed" \
    | nc -U "$ROOST_SOCKET_PATH"
```

Wrap it in a function and call it from anywhere:

```bash
roost_notify() {
    [ -z "${ROOST_SOCKET_PATH:-}" ] && return 0
    local title="${1:-Done}"
    local body="${2:-}"
    local safe_body
    safe_body=$(printf '%s' "$body" | tr '|\n\r' '   ' | head -c 500)
    printf '%s|%s|%s|%s' "custom" "${ROOST_PANE_ID:-}" "$title" "$safe_body" \
        | nc -U "$ROOST_SOCKET_PATH" 2>/dev/null || true
}

# Usage
long-running-build && roost_notify "Build finished" "All tests passed"
```

## Minimal Example — Node.js

```javascript
import { createConnection } from "net"

function roostNotify(title, body = "") {
  const socketPath = process.env.ROOST_SOCKET_PATH
  const paneID = process.env.ROOST_PANE_ID || ""
  if (!socketPath) return
  const safeBody = String(body).replace(/[\n\r|]+/g, " ").slice(0, 500)
  const payload = `custom|${paneID}|${title}|${safeBody}`
  const conn = createConnection({ path: socketPath })
  conn.on("error", () => {})
  conn.write(payload, () => conn.end())
}
```

## Minimal Example — Python

```python
import os, socket

def roost_notify(title: str, body: str = "") -> None:
    path = os.environ.get("ROOST_SOCKET_PATH")
    pane = os.environ.get("ROOST_PANE_ID", "")
    if not path:
        return
    safe_body = body.replace("|", " ").replace("\n", " ")[:500]
    payload = f"custom|{pane}|{title}|{safe_body}".encode("utf-8")
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
        s.connect(path)
        s.sendall(payload)
```

## Reference Implementations

The built-in integrations are good templates for writing your own:

- **Shell hook (Claude Code):** [`Muxy/Resources/scripts/roost-claude-hook.sh`](../Muxy/Resources/scripts/roost-claude-hook.sh)
- **Shell hook (Codex):** [`Muxy/Resources/scripts/roost-codex-hook.sh`](../Muxy/Resources/scripts/roost-codex-hook.sh)
- **Shell hook (Cursor):** [`Muxy/Resources/scripts/roost-cursor-hook.sh`](../Muxy/Resources/scripts/roost-cursor-hook.sh)
- **Node plugin (OpenCode):** [`Muxy/Resources/scripts/opencode-roost-plugin.js`](../Muxy/Resources/scripts/opencode-roost-plugin.js)

## Tips

- **Fire and forget.** If Roost isn't running or the socket doesn't exist, the connection will fail — swallow the error rather than crashing your tool. Every example above does this.
- **Don't block.** Open the connection, write the payload, close it. Do not wait for a response — Roost doesn't send one.
- **Sanitize.** Always strip `|`, `\n`, `\r` from user/model-generated content before sending, and cap the body length (200–500 characters is plenty).
- **Pane routing.** If you send from outside a Roost pane (e.g. a cron job), omit `paneID`; Roost will route to the currently active pane of the active project.
- **Type strings.** Pick something descriptive for `type`. If it doesn't match a registered provider, Roost still shows the notification with a generic source — your `title` field is what users actually see.

## Delivery Settings

Regardless of where a notification comes from, Roost respects the user's choices under **Settings → Notifications**:

- **Toast** — show an in-app banner
- **Sound** — play a system sound on arrival
- **Position** — where the toast appears

A dot also appears on the project and worktree rows in the sidebar until the notification is read.
