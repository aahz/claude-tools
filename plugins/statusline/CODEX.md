# Codex CLI adaptation

Codex already provides a status line below its prompt. Use its native
`tui.status_line` configuration instead of porting the Claude renderer.
The item identifiers below were found in the locally installed Codex CLI 0.155.1.

## Run now

From the repository root:

```sh
bash plugins/statusline/scripts/codex.sh
```

Arguments pass through, including `resume --last`, `--model`, and `--cd`:

```sh
bash plugins/statusline/scripts/codex.sh resume --last
bash plugins/statusline/scripts/codex.sh --cd /path/to/project
```

This launcher overrides only the footer for that invocation, preserves the
working directory, and does not edit your configuration. It requires `bash` and
`codex` on PATH. It does not require `jq`, `curl`, or a plugin installation.

## Enable for ordinary `codex` launches

Run `/statusline` inside Codex, select and order these fields, and confirm:

1. `context-remaining`
2. `five-hour-limit`
3. `weekly-limit`
4. `model-with-reasoning`
5. `git-branch`

Codex saves the selection to its configuration. Alternatively, merge this into
`~/.codex/config.toml` (or `$CODEX_HOME/config.toml` if set):

```toml
[tui]
status_line = ["context-remaining", "five-hour-limit", "weekly-limit", "model-with-reasoning", "git-branch"]
```

If `[tui]` already exists, edit/add `status_line` inside that table; do not append
a second `[tui]` table or replace the rest of the file. Restart Codex after a
manual edit. Remove just this key or use `/statusline` to change the selection.
The launcher always supplies its own selection; use plain `codex` to use your
saved selection.

## What carries over

| Claude plugin | Codex adaptation |
| --- | --- |
| Context usage bar | Native `context-remaining`; formatting is controlled by Codex |
| 5-hour used percentage | `five-hour-limit`: remaining primary quota, when available |
| Weekly used percentage, optional | `weekly-limit`: remaining secondary quota, enabled in this preset when available |
| Model / effort | `model-with-reasoning` |
| Git branch with dirty marker | `git-branch`; do not assume the same custom dirty marker |
| Custom colors, bar width, blank padding | Not configurable through this list of native fields |
| Reset countdown, cost and duration | Not included in this preset |

The quota percentages represent **remaining**, not consumed usage. The primary
and secondary windows come from the service; the field names do not create
limits or guarantee that every account has both windows. Missing data is omitted,
not converted to zero. With API-key authentication, do not expect ChatGPT
subscription quotas. Check the usage dashboard for reset times and account limits.

Context capacity and subscription allowance are different metrics. Avoid using
`used-tokens` as a substitute for context occupancy: the installed CLI describes
it as total tokens used in the session. For a more detailed footer, the installed
version also contains `context-used` and `context-window-size`; preview their
rendering with `/statusline` before adding them. Long selections may not fit a
narrow terminal, so this preset puts the three requested metrics first.

## Why the Claude script is not reused

`scripts/statusline.sh` consumes Claude-specific JSON on stdin, reads Claude
settings, and can poll Anthropic's OAuth usage endpoint. Its installer writes
Claude's `statusLine.command` via a `SessionStart` hook. Codex's documented footer
setting accepts native item identifiers, not an external renderer command.

The Codex launcher delegates context and quota tracking to Codex itself. It has
no polling loop, cache, credential handling, or invented token-to-quota formula.
Matching the old ANSI renderer, countdown and spacing exactly would require a
separate rendering extension or changes to the CLI, beyond this native preset.
This configuration targets the terminal UI, not the desktop app.

## Verification and sources

Checked on 2026-10-30 against the installed `codex-cli 0.155.1`, its help output
and embedded field identifiers. The launcher is syntax-checked and its argument
forwarding checked locally. Live account percentages and visual footer rendering
must be verified in an authenticated interactive CLI session.

- [Official footer configuration](https://learn.chatgpt.com/docs/config-file/config-reference)
- [Official /statusline command](https://learn.chatgpt.com/docs/cli/slash-commands#configure-footer-items-with-statusline)
- [Usage limits and dashboard](https://learn.chatgpt.com/docs/pricing)
