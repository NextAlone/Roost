#!/usr/bin/env bash
set -euo pipefail

SOCKET_PATH="${ROOST_SOCKET_PATH:-${MUXY_SOCKET_PATH:-}}"
PANE_ID="${ROOST_PANE_ID:-${MUXY_PANE_ID:-}}"
LOG_FILE="${HOME}/Library/Logs/roost-hook.log"

if [ -z "$SOCKET_PATH" ] || [ -z "$PANE_ID" ]; then
    if [ -n "${ROOST_HOOK_DEBUG:-}" ]; then
        mkdir -p "$(dirname "$LOG_FILE")"
        printf '[%s] hook skipped: socket=%s pane=%s event=%s\n' \
            "$(date '+%F %T')" "${SOCKET_PATH:-<empty>}" "${PANE_ID:-<empty>}" "${1:-<no-event>}" \
            >> "$LOG_FILE"
    fi
    exit 0
fi

event="${1:-}"
input=$(cat)

mkdir -p "$(dirname "$LOG_FILE")"

send_notification() {
    local type="$1"
    local title="$2"
    local body="$3"
    local err
    err=$(printf '%s|%s|%s|%s' "$type" "$PANE_ID" "$title" "$body" \
        | nc -w 1 -U "$SOCKET_PATH" 2>&1 1>/dev/null) || {
        printf '[%s] hook send failed event=%s pane=%s err=%s\n' \
            "$(date '+%F %T')" "$type" "$PANE_ID" "$err" \
            >> "$LOG_FILE"
        return 0
    }
}

extract_last_message() {
    local msg=""
    msg=$(printf '%s' "$input" | grep -o '"last_assistant_message":"[^"]*"' | head -1 | cut -d'"' -f4)
    if [ -n "$msg" ]; then
        printf '%s' "$msg" | tr '|' ' ' | head -c 200
        return
    fi
    printf 'Session completed'
}

case "$event" in
    SessionStart|sessionstart)
        send_notification "claude_hook:idle" "Claude Code" "Session started"
        ;;
    UserPromptSubmit|userpromptsubmit)
        send_notification "claude_hook:running" "Claude Code" "Working"
        ;;
    Notification|notification)
        send_notification "claude_hook:needs_input" "Claude Code" "Needs attention"
        ;;
    Stop|stop)
        body=$(extract_last_message)
        send_notification "claude_hook:completed" "Claude Code" "$body"
        ;;
esac
