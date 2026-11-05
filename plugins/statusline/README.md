# statusline

For Codex CLI, see [the native Codex adaptation](CODEX.md). The Claude Code
installation and renderer below are specific to Claude Code.

Status line for Claude Code: git branch, model and effort, context window, session (5h) usage with reset countdown, optional long-period quota with reset date (weekly for Claude, monthly for Kimi), cost and duration. Works with both the Anthropic API and Kimi for Coding (`ANTHROPIC_BASE_URL=https://api.kimi.ai/coding/`).

```
main★ │ Opus 5.5/hi │ Ctx ▓▓▓▓▓░░░░░░░ 42% │ session ▓▓▓▓░░░░░░░░ 35% restarts in 2h30m │ weekly ▓▓░░░░░░░░░░ 18% resets Nov 12 15:00 │ $0.12 · 1h4m
main★ │ Kimi K2     │ Ctx ▓▓▓▓▓░░░░░░░ 42% │ session ▓▓▓▓░░░░░░░░ 30% restarts in 2h30m │ monthly ▓▓░░░░░░░░░░ 18% resets Dec 1 00:00
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
| Session | `session ▓▓░░ 35% restarts in 2h30m` | 5-hour usage limit and time until it resets (Claude and Kimi) |
| Weekly | `weekly ▓░░░ 18% / sonnet 7% resets Nov 12 15:00` | Claude 7-day limits and the date/time they reset; shown only with `STATUSLINE_SHOW_WEEKLY=1` |
| Monthly | `monthly ▓░░░ 18% resets Dec 1 00:00` | Kimi monthly shared pool and the date/time it resets; shown only with `STATUSLINE_SHOW_WEEKLY=1` |
| Cost · duration | `$0.12 · 1h4m` | session cost and wall time, shown when non-zero |

Bars are green below 50%, yellow below 80%, red from 80%.

### Provider selection

The usage provider is resolved in this order:

1. A recognized `ANTHROPIC_BASE_URL` host wins: `api.kimi.ai` / `api.kimi.com` → `kimi`, `api.anthropic.com` → `claude`. The full hostname is compared, so lookalike hosts (`api.kimi.ai.evil.com`) do not match.
2. If `ANTHROPIC_BASE_URL` is not set, `STATUSLINE_PROVIDER` (`claude` or `kimi`) is used; `kimi` then targets `https://api.kimi.ai/coding`.
3. With neither set, the provider is `claude`.

An unrecognized endpoint or an invalid `STATUSLINE_PROVIDER` value disables the usage segments entirely: no API calls are made, native `rate_limits` and caches are ignored, and the remaining segments (git, model, context, cost) keep rendering. Usage caches are per provider (`provider` field + separate files), so switching between Claude and Kimi never shows stale numbers from the other one.

### Where usage numbers come from

**Claude:**

- Session and weekly percentages are taken from `rate_limits` in the status line input when Claude Code provides it (Pro/Max subscriptions). Then no network requests are made.
- Otherwise, and always for the Sonnet weekly quota, the script calls `https://api.anthropic.com/api/oauth/usage` with the OAuth token from `~/.claude/.credentials.json` and caches the answer in `~/.claude/usage-exact.json`. The API is called at most once per `STATUSLINE_REFRESH_INTERVAL`.

**Kimi:**

- Usage always comes from `GET <ANTHROPIC_BASE_URL>/v1/usages` with `Authorization: Bearer` — `ANTHROPIC_AUTH_TOKEN` if set, otherwise `ANTHROPIC_API_KEY` (the same variables Claude Code itself uses; the Claude OAuth credentials file is never touched).
- The session percentage comes from the 300-minute entry in `limits[].detail` (falling back to `usages.limit_5h.used_ratio` when the detail is absent); the monthly percentage is `usages.limit_month_total.used_ratio`. `limit_month_code` is part of the same shared pool, not a separate quota, so it is not shown on its own.
- The answer is cached in `~/.claude/usage-kimi.json`, at most one API call per `STATUSLINE_REFRESH_INTERVAL`.

When the session value comes from a cache older than three refresh intervals, `(stale)` is appended.

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
| `STATUSLINE_PROVIDER` | `claude` | usage provider (`claude` or `kimi`); used only when `ANTHROPIC_BASE_URL` is not set — a recognized endpoint always wins |
| `STATUSLINE_SHOW_WEEKLY` | `0` | `1` shows the long-period quota: Claude weekly (all models) + Sonnet weekly, or the Kimi monthly pool; enables the usage API call |
| `STATUSLINE_SHOW_GIT` | `1` | `0` hides the git branch segment |
| `STATUSLINE_BAR_WIDTH` | `12` | progress bar width in characters |
| `STATUSLINE_REFRESH_INTERVAL` | `300` | seconds between usage API calls; `0` calls it on every render and risks rate limiting |
| `STATUSLINE_BOTTOM_PADDING` | `1` | empty lines printed after the status line, for vertical spacing |
| `STATUSLINE_USAGE_FILE` | `~/.claude/usage-exact.json` | Claude usage API cache |
| `STATUSLINE_KIMI_USAGE_FILE` | `~/.claude/usage-kimi.json` | Kimi usage API cache |
| `STATUSLINE_CREDENTIALS_FILE` | `~/.claude/.credentials.json` | where the Claude OAuth token is read from (not used for Kimi) |
| `STATUSLINE_SETTINGS_FILE` | `~/.claude/settings.json` | where `effortLevel` is read from |

## Uninstall

```
/plugin uninstall statusline@aahz-tools
```

Then remove `statusLine` from `~/.claude/settings.json` and the `~/.claude/statusline/` directory.
