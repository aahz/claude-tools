# statusline

Status line for Claude Code: git branch, model and effort, context window, session (5h) usage with reset countdown, optional weekly quotas, cost and duration.

```
main★ │ Opus 5.5/hi │ Ctx ▓▓▓▓▓░░░░░░░ 42% │ session ▓▓▓▓░░░░░░░░ 35% restarts in 2h30m │ $0.12 · 1h4m
```

## Install

```
/plugin marketplace add aahz/claude-tools
/plugin install statusline@aahz-tools
```

Restart Claude Code after the first install.

Requires `bash`, `jq`, `curl`.

## How it is installed

On every session start the plugin's `SessionStart` hook (`scripts/install.sh`):

1. copies `statusline.sh` to `~/.claude/statusline/statusline.sh` (only when it changed);
2. sets `statusLine` in `~/.claude/settings.json` to `bash ~/.claude/statusline/statusline.sh`.

A `statusLine` that already points to some other command is left untouched. To switch to this one, remove your `statusLine` from `settings.json` and start a new session.

`CLAUDE_CONFIG_DIR` is respected instead of `~/.claude`.

## Segments

| Segment | Example | Source |
| --- | --- | --- |
| Git branch | `main★` | `git` in the session directory; `★` marks uncommitted or untracked changes, `(no git)` outside a repository |
| Model / effort | `Opus 5.5/hi` | model from the status line input; effort (`lo`, `md`, `hi`, `mx`) from `effortLevel` in `settings.json` |
| Context | `Ctx ▓▓▓░░ 42%` | context window usage; the label becomes `1M` for the extended 1M context |
| Session | `session ▓▓░░ 35% restarts in 2h30m` | 5-hour usage limit and time until it resets |
| Weekly | `weekly ▓░░░ 18% / sonnet 7%` | 7-day limits; shown only with `STATUSLINE_SHOW_WEEKLY=1` |
| Cost · duration | `$0.12 · 1h4m` | session cost and wall time, shown when non-zero |

Bars are green below 50%, yellow below 80%, red from 80%.

### Where usage numbers come from

- Session and weekly percentages are taken from `rate_limits` in the status line input when Claude Code provides it (Pro/Max subscriptions). Then no network requests are made.
- Otherwise, and always for the Sonnet weekly quota, the script calls `https://api.anthropic.com/api/oauth/usage` with the OAuth token from `~/.claude/.credentials.json` and caches the answer in `~/.claude/usage-exact.json`. The API is called at most once per `STATUSLINE_REFRESH_INTERVAL`.
- When the session value comes from a cache older than three refresh intervals, `(stale)` is appended.

## Options

Options are environment variables. Set them in the `env` section of `~/.claude/settings.json`:

```json
{
  "env": {
    "STATUSLINE_SHOW_WEEKLY": "1",
    "STATUSLINE_BAR_WIDTH": "8"
  }
}
```

or export them in the shell before starting `claude`.

| Variable | Default | Description |
| --- | --- | --- |
| `STATUSLINE_SHOW_WEEKLY` | `0` | `1` shows weekly (all models) and Sonnet weekly quotas; enables the usage API call |
| `STATUSLINE_SHOW_GIT` | `1` | `0` hides the git branch segment |
| `STATUSLINE_BAR_WIDTH` | `12` | progress bar width in characters |
| `STATUSLINE_REFRESH_INTERVAL` | `300` | seconds between usage API calls; `0` calls it on every render and risks rate limiting |
| `STATUSLINE_BOTTOM_PADDING` | `1` | empty lines printed after the status line, for vertical spacing |
| `STATUSLINE_USAGE_FILE` | `~/.claude/usage-exact.json` | usage API cache |
| `STATUSLINE_CREDENTIALS_FILE` | `~/.claude/.credentials.json` | where the OAuth token is read from |
| `STATUSLINE_SETTINGS_FILE` | `~/.claude/settings.json` | where `effortLevel` is read from |

## Uninstall

```
/plugin uninstall statusline@aahz-tools
```

Then remove `statusLine` from `~/.claude/settings.json` and the `~/.claude/statusline/` directory.
