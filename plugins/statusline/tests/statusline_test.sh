#!/bin/bash
# Lightweight integration tests for statusline.sh — no external framework.
# A fake curl (first in PATH) serves fixture responses; HOME and the runtime
# dir are isolated per run. Only dummy credentials are used.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATUSLINE="$SCRIPT_DIR/../scripts/statusline.sh"
ORIG_PATH="$PATH"

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
HOME_T="$T/home"; RUN_T="$T/run"; BIN_T="$T/bin"; FIX_T="$T/fixtures"
CURL_LOG="$T/curl.log"
mkdir -p "$HOME_T/.claude" "$RUN_T" "$BIN_T" "$FIX_T"

# ── Fake curl: logs its arguments, serves $FAKE_CURL_FIXTURE for any URL ─────
cat > "$BIN_T/curl" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$FAKE_CURL_LOG"
url=""
for a in "$@"; do case "$a" in http://*|https://*) url="$a";; esac; done
if [ -n "${FAKE_CURL_FIXTURE:-}" ] && [ -f "$FAKE_CURL_FIXTURE" ]; then
    cat "$FAKE_CURL_FIXTURE"
    exit 0
fi
printf '{"error":"no fixture for %s"}\n' "$url"
exit 1
EOF
chmod +x "$BIN_T/curl"

# ── Helpers ──────────────────────────────────────────────────────────────────
strip_ansi() { sed $'s/\x1b\[[0-9;]*m//g'; }

# run_sl VAR=val ... — runs statusline.sh with a clean environment (env -i), so
# exported variables of the calling shell (ANTHROPIC_BASE_URL etc.) never leak.
run_sl() {
    env -i PATH="$BIN_T:$ORIG_PATH" HOME="$HOME_T" XDG_RUNTIME_DIR="$RUN_T" \
        FAKE_CURL_LOG="$CURL_LOG" FAKE_CURL_FIXTURE="${FAKE_CURL_FIXTURE:-}" \
        STATUSLINE_SHOW_GIT=0 STATUSLINE_BOTTOM_PADDING=0 \
        "$@" bash "$STATUSLINE" 2>/dev/null | strip_ansi | head -n1
}

FAIL=0
pass() { printf 'ok    %s\n' "$1"; }
fail() { printf 'FAIL  %s\n       %s\n' "$1" "$2"; FAIL=$((FAIL + 1)); }

assert_contains() {     # name haystack needle
    case "$2" in *"$3"*) pass "$1" ;; *) fail "$1" "expected [$3] in: $2" ;; esac
}
assert_not_contains() { # name haystack needle
    case "$2" in *"$3"*) fail "$1" "unexpected [$3] in: $2" ;; *) pass "$1" ;; esac
}
assert_no_curl() {      # name
    if [ ! -s "$CURL_LOG" ]; then pass "$1"; else fail "$1" "curl was called: $(cat "$CURL_LOG")"; fi
}
assert_curl_has() {     # name needle
    if grep -q -- "$2" "$CURL_LOG" 2>/dev/null; then pass "$1"; else fail "$1" "curl log lacks [$2]"; fi
}
reset_log() { : > "$CURL_LOG"; }

future_iso() { # seconds ahead → UTC ISO 8601
    local e=$(( $(date +%s) + $1 ))
    date -u -r "$e" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "@$e" +%Y-%m-%dT%H:%M:%SZ
}

# ── Fixtures ─────────────────────────────────────────────────────────────────
RES_2H_ISO="$(future_iso 7200)"
RES_2H5_ISO="$(future_iso 9000)"
RES_MONTH_ISO="$(future_iso 2592000)"
RES_EPOCH=$(( $(date +%s) + 9000 ))

STDIN_BASE=$(cat <<EOF
{"model":{"display_name":"Claude Sonnet 5"},"context_window":{"used_percentage":42},"workspace":{"current_dir":"/tmp"}}
EOF
)
STDIN_NATIVE=$(cat <<EOF
{"model":{"display_name":"Claude Sonnet 5"},"context_window":{"used_percentage":42},"workspace":{"current_dir":"/tmp"},"rate_limits":{"five_hour":{"used_percentage":35,"resets_at":$RES_EPOCH},"seven_day":{"used_percentage":18}}}
EOF
)
# Trap for Kimi: native Claude fields that must be ignored.
STDIN_KIMI_NATIVE=$(cat <<EOF
{"model":{"display_name":"Kimi K2"},"context_window":{"used_percentage":42},"workspace":{"current_dir":"/tmp"},"rate_limits":{"five_hour":{"used_percentage":99,"resets_at":$RES_EPOCH},"seven_day":{"used_percentage":99}}}
EOF
)

cat > "$FIX_T/claude_usage.json" <<EOF
{"five_hour":{"utilization":35,"resets_at":"$RES_2H5_ISO"},"seven_day":{"utilization":18},"seven_day_sonnet":{"utilization":7}}
EOF

cat > "$FIX_T/kimi_usages.json" <<EOF
{
  "limits": [
    {"window": {"duration": 300, "timeUnit": "TIME_UNIT_MINUTE"},
     "detail": {"limit": "100", "used": "30", "remaining": "70", "resetTime": "$RES_2H_ISO"}}
  ],
  "usages": {
    "limit_5h": {"used_ratio": 0, "reset_time": "$RES_2H_ISO"},
    "limit_month_total": {"used_ratio": 0.18, "reset_time": "$RES_MONTH_ISO"},
    "limit_month_code": {"used_ratio": 0.05, "reset_time": "$RES_MONTH_ISO"}
  }
}
EOF

# 5h fallback: no limits[] detail, only usages.limit_5h.
cat > "$FIX_T/kimi_fallback.json" <<EOF
{
  "limits": [],
  "usages": {
    "limit_5h": {"used_ratio": 0.42, "reset_time": "$RES_2H_ISO"},
    "limit_month_total": {"used_ratio": 0.18, "reset_time": "$RES_MONTH_ISO"}
  }
}
EOF

echo "not json at all" > "$FIX_T/malformed.txt"

# ── 1. Claude default: native fast path makes no network call ────────────────
reset_log
FAKE_CURL_FIXTURE=""
out=$(printf '%s' "$STDIN_NATIVE" | run_sl STATUSLINE_SHOW_WEEKLY=0)
assert_contains "claude: native session rendered" "$out" "session"
assert_contains "claude: native session percent" "$out" "35%"
assert_contains "claude: reset countdown" "$out" "restarts in"
assert_not_contains "claude: weekly hidden by default" "$out" "weekly"
assert_no_curl "claude: native fast path skips API"

# ── 2. Claude weekly + Sonnet via OAuth API ──────────────────────────────────
reset_log
FAKE_CURL_FIXTURE="$FIX_T/claude_usage.json"
mkdir -p "$HOME_T/.claude"
cat > "$HOME_T/.claude/.credentials.json" <<EOF
{"claudeAiOauth":{"accessToken":"dummy_oauth_token"}}
EOF
out=$(printf '%s' "$STDIN_NATIVE" | run_sl STATUSLINE_SHOW_WEEKLY=1)
assert_contains "claude: weekly rendered" "$out" "weekly"
assert_contains "claude: weekly percent from stdin" "$out" "18%"
assert_contains "claude: sonnet from API" "$out" "sonnet 7%"
assert_curl_has "claude: OAuth usage endpoint called" "api.anthropic.com/api/oauth/usage"
if jq -e '.provider == "claude" and (.metrics.week_sonnet.percent_used == 7)' \
    "$HOME_T/.claude/usage-exact.json" >/dev/null 2>&1; then
    pass "claude: cache tagged provider=claude"
else
    fail "claude: cache tagged provider=claude" "$(cat "$HOME_T/.claude/usage-exact.json" 2>/dev/null)"
fi

# ── 3. Claude legacy cache (no provider tag) is accepted ─────────────────────
reset_log
FAKE_CURL_FIXTURE=""
cat > "$HOME_T/.claude/usage-exact.json" <<EOF
{"timestamp":"$(future_iso 0)","source":"api","metrics":{"session":{"percent_used":42,"resets_at":"$RES_2H_ISO"},"week_all":{"percent_used":18}}}
EOF
out=$(printf '%s' "$STDIN_BASE" | run_sl STATUSLINE_SHOW_WEEKLY=0)
assert_contains "claude: legacy cache session" "$out" "42%"
assert_no_curl "claude: fresh legacy cache skips API"

# ── 4. Kimi auto-detection via ANTHROPIC_BASE_URL ────────────────────────────
reset_log
rm -f "$HOME_T/.claude/usage-kimi.json"
FAKE_CURL_FIXTURE="$FIX_T/kimi_usages.json"
out=$(printf '%s' "$STDIN_KIMI_NATIVE" | run_sl \
    ANTHROPIC_BASE_URL="https://api.kimi.ai/coding/" \
    ANTHROPIC_API_KEY="dummy_kimi_key" \
    STATUSLINE_SHOW_WEEKLY=1)
assert_contains "kimi: session from detail" "$out" "session"
assert_contains "kimi: session percent 30" "$out" "30%"
assert_contains "kimi: monthly rendered" "$out" "monthly"
assert_contains "kimi: monthly percent 18" "$out" "18%"
assert_not_contains "kimi: ignores native Claude limits" "$out" "99%"
assert_curl_has "kimi: usages endpoint called" "api.kimi.ai/coding/v1/usages"
if jq -e '.provider == "kimi" and (.metrics.month_all.percent_used > 17 and .metrics.month_all.percent_used < 19)' \
    "$HOME_T/.claude/usage-kimi.json" >/dev/null 2>&1; then
    pass "kimi: cache tagged provider=kimi with month_all"
else
    fail "kimi: cache tagged provider=kimi with month_all" "$(cat "$HOME_T/.claude/usage-kimi.json" 2>/dev/null)"
fi

# ── 5. Kimi via STATUSLINE_PROVIDER when endpoint is unset ───────────────────
reset_log
rm -f "$HOME_T/.claude/usage-kimi.json"
out=$(printf '%s' "$STDIN_BASE" | run_sl \
    STATUSLINE_PROVIDER=kimi ANTHROPIC_API_KEY="dummy_kimi_key" STATUSLINE_SHOW_WEEKLY=1)
assert_curl_has "kimi: provider setting hits default Kimi URL" "https://api.kimi.ai/coding/v1/usages"
assert_contains "kimi: monthly via provider setting" "$out" "monthly"

# ── 6. Kimi auth: AUTH_TOKEN wins over API_KEY, API_KEY is the fallback ──────
reset_log
rm -f "$HOME_T/.claude/usage-kimi.json"
printf '%s' "$STDIN_BASE" | run_sl STATUSLINE_PROVIDER=kimi \
    ANTHROPIC_AUTH_TOKEN="tok_aaa" ANTHROPIC_API_KEY="key_bbb" STATUSLINE_SHOW_WEEKLY=1 >/dev/null
assert_curl_has "kimi: Bearer prefers AUTH_TOKEN" "Bearer tok_aaa"
reset_log
rm -f "$HOME_T/.claude/usage-kimi.json"
printf '%s' "$STDIN_BASE" | run_sl STATUSLINE_PROVIDER=kimi \
    ANTHROPIC_API_KEY="key_bbb" STATUSLINE_SHOW_WEEKLY=1 >/dev/null
assert_curl_has "kimi: Bearer falls back to API_KEY" "Bearer key_bbb"

# ── 7. Kimi 5h fallback via usages.limit_5h ──────────────────────────────────
reset_log
rm -f "$HOME_T/.claude/usage-kimi.json"
FAKE_CURL_FIXTURE="$FIX_T/kimi_fallback.json"
out=$(printf '%s' "$STDIN_BASE" | run_sl \
    STATUSLINE_PROVIDER=kimi ANTHROPIC_API_KEY="dummy_kimi_key" STATUSLINE_SHOW_WEEKLY=1)
assert_contains "kimi: 5h fallback percent 42" "$out" "42%"
FAKE_CURL_FIXTURE="$FIX_T/kimi_usages.json"

# ── 8. Unknown endpoint: no usage, no network, other segments intact ─────────
reset_log
out=$(printf '%s' "$STDIN_KIMI_NATIVE" | run_sl \
    ANTHROPIC_BASE_URL="https://proxy.example.com/anthropic" \
    ANTHROPIC_API_KEY="dummy" STATUSLINE_SHOW_WEEKLY=1)
assert_not_contains "unknown: no session segment" "$out" "session"
assert_not_contains "unknown: no monthly segment" "$out" "monthly"
assert_not_contains "unknown: native limits ignored" "$out" "99%"
assert_contains "unknown: model still rendered" "$out" "Kimi K2"
assert_contains "unknown: context still rendered" "$out" "Ctx"
assert_no_curl "unknown: no API call"

# ── 9. Lookalike hosts are not Kimi ──────────────────────────────────────────
reset_log
out=$(printf '%s' "$STDIN_BASE" | run_sl \
    ANTHROPIC_BASE_URL="https://api.kimi.ai.evil.com/coding/" ANTHROPIC_API_KEY="dummy")
assert_not_contains "lookalike: suffix host not kimi" "$out" "session"
out=$(printf '%s' "$STDIN_BASE" | run_sl \
    ANTHROPIC_BASE_URL="https://example.com/?next=api.kimi.ai" ANTHROPIC_API_KEY="dummy")
assert_not_contains "lookalike: kimi only in query" "$out" "session"
assert_no_curl "lookalike: no API call"

# ── 10. Invalid STATUSLINE_PROVIDER disables usage ───────────────────────────
reset_log
out=$(printf '%s' "$STDIN_NATIVE" | run_sl STATUSLINE_PROVIDER=bob)
assert_not_contains "invalid provider: no session" "$out" "session"
assert_no_curl "invalid provider: no API call"

# ── 11. Malformed Kimi response: no crash, no cache clobber ──────────────────
reset_log
rm -f "$HOME_T/.claude/usage-kimi.json"
FAKE_CURL_FIXTURE="$FIX_T/malformed.txt"
out=$(printf '%s' "$STDIN_BASE" | run_sl \
    STATUSLINE_PROVIDER=kimi ANTHROPIC_API_KEY="dummy" STATUSLINE_SHOW_WEEKLY=1)
assert_contains "malformed: other segments render" "$out" "Ctx"
assert_not_contains "malformed: no session segment" "$out" "session"
if [ ! -f "$HOME_T/.claude/usage-kimi.json" ]; then
    pass "malformed: no cache written"
else
    fail "malformed: no cache written" "cache file exists"
fi
FAKE_CURL_FIXTURE="$FIX_T/kimi_usages.json"

# ── 12. Cross-provider cache isolation ───────────────────────────────────────
# A fresh cache tagged for another provider must count as a miss and refresh.
reset_log
cat > "$HOME_T/.claude/usage-kimi.json" <<EOF
{"timestamp":"$(future_iso 0)","source":"api","provider":"claude","metrics":{"session":{"percent_used":77,"resets_at":"$RES_2H_ISO"}}}
EOF
out=$(printf '%s' "$STDIN_BASE" | run_sl \
    STATUSLINE_PROVIDER=kimi ANTHROPIC_API_KEY="dummy" STATUSLINE_SHOW_WEEKLY=1)
assert_curl_has "isolation: claude-tagged kimi cache refreshes" "/v1/usages"
assert_not_contains "isolation: foreign cache value not shown" "$out" "77%"

reset_log
cat > "$HOME_T/.claude/usage-exact.json" <<EOF
{"timestamp":"$(future_iso 0)","source":"api","provider":"kimi","metrics":{"session":{"percent_used":77,"resets_at":"$RES_2H_ISO"}}}
EOF
FAKE_CURL_FIXTURE="$FIX_T/claude_usage.json"
out=$(printf '%s' "$STDIN_BASE" | run_sl STATUSLINE_SHOW_WEEKLY=0)
assert_curl_has "isolation: kimi-tagged claude cache refreshes" "api/oauth/usage"
assert_contains "isolation: claude refresh wins" "$out" "35%"
assert_not_contains "isolation: foreign cache value not shown" "$out" "77%"

# ── Summary ──────────────────────────────────────────────────────────────────
if [ "$FAIL" -eq 0 ]; then
    echo "all tests passed"
else
    echo "$FAIL test(s) failed"
    exit 1
fi
