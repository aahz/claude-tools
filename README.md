# aahz-tools

Personal Claude Code plugin marketplace.

## Install

```
/plugin marketplace add aahz/claude-tools
/plugin install statusline@aahz-tools
```

Restart Claude Code after the first install.

## Plugins

### statusline

Status line: git branch, model/effort, context window, session (5h) usage with reset countdown, optional weekly quotas, cost and duration.

On every session start the plugin copies `statusline.sh` to `~/.claude/statusline/` and sets `statusLine` in `~/.claude/settings.json`, unless it already points to another command.

Requires `bash`, `jq`, `curl`.

Options (environment variables): `STATUSLINE_SHOW_WEEKLY=1`, `STATUSLINE_SHOW_GIT=0`, `STATUSLINE_BAR_WIDTH`, `STATUSLINE_REFRESH_INTERVAL`, `STATUSLINE_BOTTOM_PADDING`.
