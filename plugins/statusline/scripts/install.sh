#!/bin/bash
# Installs statusline.sh to a stable path and points settings.json statusLine at it.
# A statusLine set to some other command is left untouched.
set -u

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
TARGET_DIR="$CLAUDE_DIR/statusline"
TARGET="$TARGET_DIR/statusline.sh"
SETTINGS="$CLAUDE_DIR/settings.json"
COMMAND="bash $TARGET"
LEGACY_COMMAND="bash ~/.claude/hooks/statusline.sh"

command -v jq >/dev/null 2>&1 || exit 0

mkdir -p "$TARGET_DIR"
if ! cmp -s "$SRC_DIR/statusline.sh" "$TARGET"; then
    cp "$SRC_DIR/statusline.sh" "$TARGET.tmp" && mv "$TARGET.tmp" "$TARGET"
fi

[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
current="$(jq -r '.statusLine.command // empty' "$SETTINGS" 2>/dev/null)" || exit 0

case "$current" in
    "$COMMAND") exit 0 ;;
    ""|"$LEGACY_COMMAND") ;;
    *) exit 0 ;;
esac

tmp="$(mktemp "$SETTINGS.XXXXXX")" || exit 0
if jq --arg cmd "$COMMAND" '.statusLine = {type: "command", command: $cmd}' "$SETTINGS" > "$tmp"; then
    mv "$tmp" "$SETTINGS"
else
    rm -f "$tmp"
fi
exit 0
