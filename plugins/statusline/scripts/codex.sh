#!/bin/bash
# Use Codex's native footer; no Claude hooks, credential reads or API polling.
# Keep context and both quotas first so they take priority in narrow terminals.
set -eu

if ! command -v codex >/dev/null 2>&1; then
    echo 'codex is not on PATH. Install Codex CLI first.' >&2
    exit 127
fi

exec codex -c 'tui.status_line=["context-remaining","five-hour-limit","weekly-limit","model-with-reasoning","git-branch"]' "$@"
