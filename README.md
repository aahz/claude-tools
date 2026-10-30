# aahz-tools

Personal Claude Code plugin marketplace.

Also includes a [native Codex CLI status-line adaptation](plugins/statusline/CODEX.md)
for context capacity, 5-hour and weekly limits:

```sh
bash plugins/statusline/scripts/codex.sh
```

## Install

```
/plugin marketplace add aahz/claude-tools
/plugin install statusline@aahz-tools
```

Restart Claude Code after the first install.

## Plugins

### statusline

Status line: git branch, model/effort, context window, session (5h) usage with reset countdown, optional weekly quotas, cost and duration.

Segments, options and how it installs itself: [plugins/statusline/README.md](plugins/statusline/README.md).
