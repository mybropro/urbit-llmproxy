#!/usr/bin/env bash
#
# End-to-end behavioral tests for %llmproxy.
#
# Drives the running %llmproxy-client's HTTP API to exercise auth/policy/discovery
# paths. Assumes:
#
#   - test1 ship is reachable at $T1 (default http://localhost:80)
#     and has %llmproxy installed with hosting toggled ON.
#   - test2 ship is reachable at $T2 (default http://localhost:8081)
#     and has %llmproxy installed.
#   - Both ships' HTTP ports accept unauthenticated localhost requests
#     (Eyre's default behavior).
#   - test2's %llmproxy-client points its `node` at test1 (set via the UI or via
#     the SET_T2_NODE_TO_T1 var below — script does it idempotently).
#
# Run: bash tests/e2e.sh
#
# Exits 0 on full pass, 1 on any failure.

set -u

T1="${T1:-http://localhost:80}"
T2="${T2:-http://localhost:8081}"

# Filled in at startup
T1_SHIP=""
T2_SHIP=""

PASS=0
FAIL=0
FAILED_TESTS=()

# ─── helpers ───────────────────────────────────────────────────────────

color() {
  case "$1" in
    red)   printf '\033[31m%s\033[0m' "$2" ;;
    green) printf '\033[32m%s\033[0m' "$2" ;;
    dim)   printf '\033[2m%s\033[0m' "$2" ;;
    *)     printf '%s' "$2" ;;
  esac
}

run() {
  local name="$1"
  shift
  if "$@" >/tmp/e2e-out 2>&1; then
    PASS=$((PASS+1))
    printf '  %s %s\n' "$(color green '✓')" "$name"
  else
    FAIL=$((FAIL+1))
    FAILED_TESTS+=("$name")
    printf '  %s %s\n' "$(color red '✗')" "$name"
    sed 's/^/      /' /tmp/e2e-out | head -10
  fi
}

# Configure the %llmproxy-client at $1 via /llmproxy/ui POST.
ui_post() {
  local base="$1"; shift
  curl -sS --max-time 10 -X POST "$base/llmproxy/ui" \
    -H 'content-type: application/x-www-form-urlencoded' \
    "$@" -o /dev/null
}

# Submit a chat-completions request to $1, return status code on stdout.
# Optional Authorization arg via env BEARER.
chat_status() {
  local base="$1"
  if [[ -n "${BEARER:-}" ]]; then
    curl -sS --max-time 90 -o /tmp/e2e-body -w '%{http_code}' \
      -X POST "$base/llmproxy/v1/chat/completions" \
      -H 'content-type: application/json' \
      -H "Authorization: Bearer $BEARER" \
      -d '{"model":"llama3.1:8b","messages":[{"role":"user","content":"reply: ok"}]}'
  else
    curl -sS --max-time 90 -o /tmp/e2e-body -w '%{http_code}' \
      -X POST "$base/llmproxy/v1/chat/completions" \
      -H 'content-type: application/json' \
      -d '{"model":"llama3.1:8b","messages":[{"role":"user","content":"reply: ok"}]}'
  fi
}

models_status() {
  local base="$1"
  if [[ -n "${BEARER:-}" ]]; then
    curl -sS --max-time 10 -o /tmp/e2e-body -w '%{http_code}' \
      -H "Authorization: Bearer $BEARER" \
      "$base/llmproxy/v1/models"
  else
    curl -sS --max-time 10 -o /tmp/e2e-body -w '%{http_code}' \
      "$base/llmproxy/v1/models"
  fi
}

assert_status() {
  local got="$1" expected="$2" msg="${3:-}"
  if [[ "$got" != "$expected" ]]; then
    echo "expected status $expected, got $got. body:" >&2
    head -c 400 /tmp/e2e-body >&2
    echo >&2
    return 1
  fi
}

assert_body_contains() {
  local needle="$1"
  if ! grep -qF -- "$needle" /tmp/e2e-body; then
    echo "expected body to contain '$needle'. got:" >&2
    head -c 400 /tmp/e2e-body >&2
    echo >&2
    return 1
  fi
}

# Read the @p of a ship from Eyre's session cookie. Reliable regardless
# of UI state (hosting on/off, what node the client is pointed at, etc).
ship_of() {
  local base="$1"
  curl -sSI --max-time 5 "$base/llmproxy/ui" \
    | grep -oE 'urbauth-~[a-z-]+' \
    | head -1 \
    | sed 's/urbauth-//'
}

# ─── setup ─────────────────────────────────────────────────────────────

setup_ships() {
  T1_SHIP=$(ship_of "$T1") || true
  T2_SHIP=$(ship_of "$T2") || true
  if [[ -z "$T1_SHIP" ]]; then
    echo "$(color red 'fatal:') could not determine T1 ship at $T1"
    exit 1
  fi
  if [[ -z "$T2_SHIP" ]]; then
    echo "$(color red 'fatal:') could not determine T2 ship at $T2"
    exit 1
  fi
  printf '%s T1=%s @%s\n' "$(color dim '·')" "$T1" "$T1_SHIP"
  printf '%s T2=%s @%s\n' "$(color dim '·')" "$T2" "$T2_SHIP"
  # Point T2's %llmproxy-client at T1's node (idempotent)
  ui_post "$T2" \
    --data-urlencode "action=set-node" \
    --data-urlencode "node=$T1_SHIP"
}

reset_t1() {
  # Clear API token, set whitelist empty, ensure hosting is on
  ui_post "$T1" --data-urlencode "action=set-client-api-token" --data-urlencode "token="
  # Make sure mode is whitelist with empty list. The toggle action flips, so
  # we read state then conditionally toggle. Simpler: set ships first (which
  # also confirms current state).
  ui_post "$T1" --data-urlencode "action=set-policy-ships" --data-urlencode "ships="
  # If we landed on blacklist, toggle to whitelist
  if curl -sS --max-time 5 "$T1/llmproxy/ui" | grep -q 'blacklist (everyone'; then
    ui_post "$T1" --data-urlencode "action=toggle-policy-mode"
  fi
  # Ensure hosting is on (if it shows 'turn on hosting', toggle)
  if curl -sS --max-time 5 "$T1/llmproxy/ui" | grep -q '>turn on hosting<'; then
    ui_post "$T1" --data-urlencode "action=toggle-hosting"
  fi
  sleep 1   # let the queued client → node pokes settle
}

# ─── test scenarios ────────────────────────────────────────────────────

# 1. UI smoke
test_ui_renders() {
  local code
  code=$(curl -sS --max-time 5 -o /tmp/e2e-body -w '%{http_code}' "$T1/llmproxy/ui")
  assert_status "$code" "200" || return 1
  assert_body_contains "<summary>Use as a client</summary>"
}

test_models_endpoint() {
  unset BEARER
  local code
  code=$(models_status "$T1")
  assert_status "$code" "200" || return 1
  assert_body_contains '"object":"list"'
}

# 2. Local chat (own ship)
test_local_chat_works() {
  unset BEARER
  reset_t1
  local code
  code=$(chat_status "$T1")
  assert_status "$code" "200"
}

# 3. Whitelist policy
test_whitelist_empty_blocks_remote() {
  reset_t1   # whitelist=[], hosting on
  unset BEARER
  local code
  code=$(chat_status "$T2")    # T2 → T1 cross-ship, expect 403
  assert_status "$code" "403"
}

test_whitelist_allows_listed_ship() {
  reset_t1
  ui_post "$T1" \
    --data-urlencode "action=set-policy-ships" \
    --data-urlencode "ships=$T2_SHIP"
  sleep 2   # let the client → node poke propagate
  unset BEARER
  local code
  code=$(chat_status "$T2")
  assert_status "$code" "200"
}

# 4. Blacklist policy
test_blacklist_empty_allows_all() {
  reset_t1
  ui_post "$T1" --data-urlencode "action=toggle-policy-mode"   # → blacklist
  unset BEARER
  local code
  code=$(chat_status "$T2")
  assert_status "$code" "200"
}

test_blacklist_blocks_listed_ship() {
  reset_t1
  ui_post "$T1" --data-urlencode "action=toggle-policy-mode"   # → blacklist
  ui_post "$T1" \
    --data-urlencode "action=set-policy-ships" \
    --data-urlencode "ships=$T2_SHIP"
  sleep 2
  unset BEARER
  local code
  code=$(chat_status "$T2")
  assert_status "$code" "403"
}

# 5. API token
test_token_unset_no_auth_required() {
  reset_t1
  unset BEARER
  local code
  code=$(chat_status "$T1")
  assert_status "$code" "200"
}

test_token_set_no_header_rejected() {
  reset_t1
  ui_post "$T1" \
    --data-urlencode "action=set-client-api-token" \
    --data-urlencode "token=sk-test-secret"
  unset BEARER
  local code
  code=$(chat_status "$T1")
  assert_status "$code" "401"
}

test_token_set_wrong_header_rejected() {
  reset_t1
  ui_post "$T1" \
    --data-urlencode "action=set-client-api-token" \
    --data-urlencode "token=sk-test-secret"
  BEARER="sk-wrong"
  local code
  code=$(chat_status "$T1")
  assert_status "$code" "401"
}

test_token_set_correct_header_accepted() {
  reset_t1
  ui_post "$T1" \
    --data-urlencode "action=set-client-api-token" \
    --data-urlencode "token=sk-test-secret"
  BEARER="sk-test-secret"
  local code
  code=$(chat_status "$T1")
  assert_status "$code" "200"
}

test_models_endpoint_also_token_gated() {
  reset_t1
  ui_post "$T1" \
    --data-urlencode "action=set-client-api-token" \
    --data-urlencode "token=sk-test-secret"
  unset BEARER
  local code
  code=$(models_status "$T1")
  assert_status "$code" "401"
}

# 6. Generate token
test_generate_token_works_as_bearer() {
  reset_t1
  local resp tok
  resp=$(curl -sS --max-time 5 -X POST "$T1/llmproxy/ui" \
    -H 'content-type: application/x-www-form-urlencoded' \
    --data-urlencode 'action=generate-api-token')
  tok=$(printf '%s' "$resp" | grep -oE 'sk-[a-z0-9.-]+' | head -1)
  if [[ -z "$tok" ]]; then
    echo "no token in generate response" >&2
    return 1
  fi
  BEARER="$tok"
  local code
  code=$(chat_status "$T1")
  assert_status "$code" "200"
}

test_generate_token_is_random() {
  local r1 r2 t1 t2
  r1=$(curl -sS --max-time 5 -X POST "$T1/llmproxy/ui" \
    -H 'content-type: application/x-www-form-urlencoded' \
    --data-urlencode 'action=generate-api-token')
  t1=$(printf '%s' "$r1" | grep -oE 'sk-[a-z0-9.-]+' | head -1)
  sleep 1
  r2=$(curl -sS --max-time 5 -X POST "$T1/llmproxy/ui" \
    -H 'content-type: application/x-www-form-urlencoded' \
    --data-urlencode 'action=generate-api-token')
  t2=$(printf '%s' "$r2" | grep -oE 'sk-[a-z0-9.-]+' | head -1)
  if [[ -z "$t1" || -z "$t2" ]]; then
    echo "failed to capture tokens: t1=$t1 t2=$t2" >&2
    return 1
  fi
  if [[ "$t1" == "$t2" ]]; then
    echo "expected tokens to differ: both = $t1" >&2
    return 1
  fi
}

# 7. Models discovery
test_models_reflects_backend_advertised() {
  reset_t1
  ui_post "$T1" --data-urlencode "action=refresh-models"
  sleep 2
  unset BEARER
  local code
  code=$(models_status "$T1")
  assert_status "$code" "200" || return 1
  assert_body_contains '"id":"llama3.1:8b"'
}

# 8. UI invariants
test_invite_uses_publisher_atP() {
  curl -sS --max-time 5 -o /tmp/e2e-body "$T1/llmproxy/ui"
  assert_body_contains "|install $T1_SHIP %llmproxy"
}

test_api_endpoint_shows_full_url() {
  curl -sS --max-time 5 -o /tmp/e2e-body "$T1/llmproxy/ui"
  assert_body_contains "POST http://localhost"
  assert_body_contains "/llmproxy/v1/chat/completions"
}

# ─── runner ────────────────────────────────────────────────────────────

main() {
  printf '%s\n' "$(color dim '── e2e tests for %llmproxy ──')"
  setup_ships

  printf '\n  ui & endpoints\n'
  run "ui renders"                            test_ui_renders
  run "GET /v1/models returns list"           test_models_endpoint
  run "invite uses publisher @p"              test_invite_uses_publisher_atP
  run "api endpoint shows full URL"           test_api_endpoint_shows_full_url

  printf '\n  local chat\n'
  run "local chat (own ship) → 200"           test_local_chat_works

  printf '\n  whitelist policy\n'
  run "whitelist empty blocks remote → 403"   test_whitelist_empty_blocks_remote
  run "whitelist allows listed ship → 200"    test_whitelist_allows_listed_ship

  printf '\n  blacklist policy\n'
  run "blacklist empty allows all → 200"      test_blacklist_empty_allows_all
  run "blacklist blocks listed ship → 403"    test_blacklist_blocks_listed_ship

  printf '\n  api token\n'
  run "no token, no header → 200"             test_token_unset_no_auth_required
  run "token set, no header → 401"            test_token_set_no_header_rejected
  run "token set, wrong header → 401"         test_token_set_wrong_header_rejected
  run "token set, right header → 200"         test_token_set_correct_header_accepted
  run "/v1/models also gated → 401"           test_models_endpoint_also_token_gated

  printf '\n  generate token\n'
  run "generated token works as bearer"       test_generate_token_works_as_bearer
  run "successive generates differ"           test_generate_token_is_random

  printf '\n  models discovery\n'
  run "/v1/models reflects backend"           test_models_reflects_backend_advertised

  reset_t1   # leave system in a clean state

  printf '\n%s passed, %s failed\n' \
    "$(color green "$PASS")" \
    "$(if [[ $FAIL -gt 0 ]]; then color red "$FAIL"; else printf '%s' "$FAIL"; fi)"
  if [[ $FAIL -gt 0 ]]; then
    printf '\nfailing tests:\n'
    for t in "${FAILED_TESTS[@]}"; do
      printf '  - %s\n' "$t"
    done
    exit 1
  fi
}

main "$@"
