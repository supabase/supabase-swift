#!/usr/bin/env bash
# Drive supabase-swift against an isolated local Supabase stack and keep the evidence.
# Usage: verify.sh up [RUN_ID] | doctor | drive <journey> [label] | sql "<query>" |
#        http <METHOD> <path> [json-body] | list | down
# Commands other than `up` and `list` read the run from $VERIFY_RUN_ID, or use the only live run.
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO="$(git -C "$SKILL_DIR" rev-parse --show-toplevel)"
VERIFY_ROOT="$REPO/.verify"
export SUPABASE_EXPERIMENTAL_STACK=1

START_FLAGS=()
if [[ "$(uname)" == "Darwin" ]]; then
  START_FLAGS=(--runtime native --eager)
fi

die() { echo "verify: $*" >&2; exit 1; }
# macOS has no `timeout`; perl's alarm kills the command after N seconds.
with_timeout() { local secs="$1"; shift; perl -e 'alarm shift; exec @ARGV' "$secs" "$@"; }
port_busy() { lsof -nP -iTCP:"$1" -sTCP:LISTEN >/dev/null 2>&1; }
# Run ids and labels become path components and shell values, so allow only a safe set.
check_name() { [[ "$2" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || die "invalid $1 '$2' (use letters, digits, '.', '_', '-')"; }

resolve_run() {
  local id="${VERIFY_RUN_ID:-}"
  if [[ -z "$id" ]]; then
    local states=()
    for f in "$VERIFY_ROOT"/runs/*/state.env; do [[ -f "$f" ]] && states+=("$f"); done
    [[ ${#states[@]} -eq 1 ]] || die "set VERIFY_RUN_ID (found ${#states[@]} live runs; see 'verify.sh list')"
    id="$(basename "$(dirname "${states[0]}")")"
  fi
  check_name "run id" "$id"
  [[ -f "$VERIFY_ROOT/runs/$id/state.env" ]] || die "no live run '$id' (see 'verify.sh list')"
  # shellcheck disable=SC1090
  source "$VERIFY_ROOT/runs/$id/state.env"
}

http_code() { # METHOD URL KEY [BODY] [OUT_FILE] -> prints the status code
  local method="$1" url="$2" key="$3" body="${4:-}" out="${5:-/dev/null}"
  local args=(-s -m 20 -o "$out" -w '%{http_code}' -X "$method"
    -H "apikey: $key" -H "Authorization: Bearer $key")
  [[ -n "$body" ]] && args+=(-H 'Content-Type: application/json' -d "$body")
  curl "${args[@]}" "$url" || echo 000
}

wait_ready() {
  local deadline=$((SECONDS + 180)) seed="" auth="" storage="" fn=""
  while ((SECONDS < deadline)); do
    seed="$(http_code GET "$SUPABASE_URL/rest/v1/users?select=username&username=eq.supabot" "$SUPABASE_PUBLISHABLE_KEY" "" "$RUN_DIR/ready.users.json")"
    [[ "$seed" == 200 ]] && grep -q supabot "$RUN_DIR/ready.users.json" || seed="no-seed:$seed"
    auth="$(http_code GET "$SUPABASE_URL/auth/v1/health" "$SUPABASE_PUBLISHABLE_KEY")"
    storage="$(http_code GET "$SUPABASE_URL/storage/v1/bucket" "$SUPABASE_SERVICE_ROLE_KEY")"
    fn="$(http_code POST "$SUPABASE_URL/functions/v1/echo" "$SUPABASE_PUBLISHABLE_KEY" '{}')"
    if [[ "$seed" == 200 && "$auth" == 200 && "$storage" == 200 && "$fn" == 200 ]]; then
      echo "ready: rest+seed=200 auth=200 storage=200 functions=200"
      return 0
    fi
    sleep 2
  done
  echo "not ready after 180s: rest+seed=$seed auth=$auth storage=$storage functions=$fn" >&2
  return 1
}

cmd_up() {
  command -v supabase >/dev/null || die "supabase CLI not found (brew install supabase/tap/supabase)"
  local id="${1:-$(date +%Y%m%d-%H%M%S)-$$}"
  check_name "run id" "$id"
  local run="$VERIFY_ROOT/runs/$id"
  [[ -e "$run" ]] && die "run '$id' already exists"

  local base="" b
  for b in $(seq 56400 100 59900); do
    grep -qsx "PORT_BASE=$b" "$VERIFY_ROOT"/runs/*/state.env && continue
    local free=1 p
    for p in 20 21 22 23 24 27 28 29; do port_busy $((b + p)) && { free=0; break; }; done
    ((free)) && { base=$b; break; }
  done
  [[ -n "$base" ]] || die "no free port block between 56400 and 59999"

  mkdir -p "$run" "$VERIFY_ROOT/evidence/$id"
  cp -R "$REPO/Tests/IntegrationTests/supabase" "$run/supabase"
  # Own project id and ports, so this stack never collides with the user's stack (54321-54329),
  # the integration tests, or another verification run.
  BASE="$base" ID="$id" perl -pi -e '
    s/^project_id\s*=.*/project_id = "verify-$ENV{ID}"/;
    s/^(\s*(?:shadow_)?port\s*=\s*)543(\d\d)\s*$/$1 . ($ENV{BASE} + $2) . "\n"/e;
    s/^(\s*inspector_port\s*=\s*)\d+/$1 . ($ENV{BASE} + 28)/e;
  ' "$run/supabase/config.toml"

  echo "starting stack '$id' on ports $((base + 20))-$((base + 29)) (log: $run/start.log)"
  if ! (cd "$run" && with_timeout 600 supabase start ${START_FLAGS[@]+"${START_FLAGS[@]}"} --output-format json) \
    >"$run/start.json" 2>"$run/start.log"; then
    tail -20 "$run/start.log" >&2
    die "supabase start failed; run 'VERIFY_RUN_ID=$id verify.sh down' to clean up"
  fi
  local j="$run/start.json"
  jq -e '.env.API_URL' "$j" >/dev/null || die "unexpected start output in $j"

  # %q escapes each value, so sourcing the file assigns it as-is (paths with spaces included).
  {
    printf 'RUN_ID=%q\n' "$id"
    printf 'RUN_DIR=%q\n' "$run"
    printf 'EVIDENCE_DIR=%q\n' "$VERIFY_ROOT/evidence/$id"
    printf 'PORT_BASE=%q\n' "$base"
    printf 'STACK_ID=%q\n' "$(jq -r '.id' "$j")"
    printf 'SUPABASE_URL=%q\n' "$(jq -r '.env.API_URL' "$j")"
    printf 'SUPABASE_DB_URL=%q\n' "$(jq -r '.env.DB_URL' "$j")"
    printf 'SUPABASE_MAILPIT_URL=%q\n' "$(jq -r '.env.MAILPIT_URL' "$j")"
    printf 'SUPABASE_PUBLISHABLE_KEY=%q\n' "$(jq -r '.env.PUBLISHABLE_KEY' "$j")"
    printf 'SUPABASE_SECRET_KEY=%q\n' "$(jq -r '.env.SECRET_KEY' "$j")"
    printf 'SUPABASE_ANON_KEY=%q\n' "$(jq -r '.env.ANON_KEY' "$j")"
    printf 'SUPABASE_SERVICE_ROLE_KEY=%q\n' "$(jq -r '.env.SERVICE_ROLE_KEY' "$j")"
    printf 'GIT_SHA=%q\n' "$(git -C "$REPO" rev-parse HEAD)"
  } >"$run/state.env"
  # shellcheck disable=SC1090
  source "$run/state.env"
  wait_ready || die "stack started but is not usable; run 'VERIFY_RUN_ID=$id verify.sh down'"
  echo "export VERIFY_RUN_ID=$id"
}

cmd_doctor() {
  resolve_run
  local fail=0
  ok() { echo "  ok   $*"; }
  bad() { echo "  FAIL $*"; fail=1; }
  echo "run $RUN_ID  url $SUPABASE_URL  stack $STACK_ID"

  local status
  status="$(cd "$RUN_DIR" && with_timeout 30 supabase stack status --output-format json 2>/dev/null)" || status=""
  if [[ "$(jq -r '.identity.project_root // empty' <<<"$status" 2>/dev/null)" == "$RUN_DIR" ]]; then
    ok "stack is ours (project_root $RUN_DIR)"
    local life ready
    life="$(jq -r '.lifecycle' <<<"$status")"
    ready="$(jq -r '.readiness' <<<"$status")"
    [[ "$life" == running && "$ready" == ready ]] && ok "lifecycle=$life readiness=$ready" ||
      bad "lifecycle=$life readiness=$ready"
    local unhealthy
    unhealthy="$(jq -r '[.composition.members[] | select(.health != "healthy") | .service] | join(",")' <<<"$status")"
    [[ -z "$unhealthy" ]] && ok "every service healthy" || bad "unhealthy services: $unhealthy"
  else
    bad "supabase stack status did not report this run's stack"
  fi

  port_busy $((PORT_BASE + 21)) && ok "API port $((PORT_BASE + 21)) is listening" ||
    bad "API port $((PORT_BASE + 21)) is not listening"
  wait_ready_once() { # one pass of wait_ready without the loop
    local seed auth fn
    seed="$(http_code GET "$SUPABASE_URL/rest/v1/users?select=username&username=eq.supabot" "$SUPABASE_PUBLISHABLE_KEY" "" "$RUN_DIR/ready.users.json")"
    [[ "$seed" == 200 ]] && grep -q supabot "$RUN_DIR/ready.users.json" && ok "seed row 'supabot' readable over REST" ||
      bad "seed row 'supabot' not readable (status $seed)"
    auth="$(http_code GET "$SUPABASE_URL/auth/v1/health" "$SUPABASE_PUBLISHABLE_KEY")"
    [[ "$auth" == 200 ]] && ok "auth health 200" || bad "auth health $auth"
    fn="$(http_code POST "$SUPABASE_URL/functions/v1/echo" "$SUPABASE_PUBLISHABLE_KEY" '{}')"
    [[ "$fn" == 200 ]] && ok "functions/echo 200" || bad "functions/echo $fn"
  }
  wait_ready_once

  local head dirty
  head="$(git -C "$REPO" rev-parse HEAD)"
  dirty="$(git -C "$REPO" status --porcelain -- Sources Package.swift 'Package@swift-*.swift' | wc -l | tr -d ' ')"
  echo "  info SDK checkout $head ($dirty changed paths under Sources/ and manifests); drive builds this tree"
  [[ "$head" == "$GIT_SHA" ]] || echo "  info HEAD moved since 'up' ($GIT_SHA); the stack schema still comes from 'up' time"
  return $fail
}

ensure_driver() {
  local driver="$VERIFY_ROOT/driver"
  mkdir -p "$driver/Sources/VerifyDrive"
  # SwiftPM names a path dependency after its directory, which is the worktree name here.
  local identity
  identity="$(basename "$REPO" | tr '[:upper:]' '[:lower:]')"
  cat >"$driver/Package.swift.new" <<EOF
// swift-tools-version: 6.0
// Generated by .claude/skills/verify-supabase-swift/scripts/verify.sh. Do not edit.
import PackageDescription

let package = Package(
  name: "VerifyDriver",
  platforms: [.macOS(.v14)],
  dependencies: [.package(path: "$REPO")],
  targets: [
    .executableTarget(
      name: "VerifyDrive",
      dependencies: [.product(name: "Supabase", package: "$identity")]
    )
  ]
)
EOF
  if cmp -s "$driver/Package.swift.new" "$driver/Package.swift"; then
    rm "$driver/Package.swift.new"
  else
    mv "$driver/Package.swift.new" "$driver/Package.swift"
  fi
}

cmd_drive() {
  [[ $# -ge 1 ]] || die "usage: verify.sh drive <journey-name|path.swift> [label]"
  resolve_run
  local journey="$1"
  [[ -f "$journey" ]] || journey="$SKILL_DIR/journeys/$1.swift"
  [[ -f "$journey" ]] || die "no journey '$1' (ls $SKILL_DIR/journeys)"
  local label="${2:-$(basename "$journey" .swift)}"
  check_name label "$label"
  local ev
  mkdir -p "$EVIDENCE_DIR"
  ev="$(mktemp -d "$EVIDENCE_DIR/$label-$(date +%H%M%S)-XXXX")"
  cp "$journey" "$ev/journey.swift"

  # One driver build at a time: SwiftPM shares the build directory.
  local lock="$VERIFY_ROOT/driver.lock"
  until mkdir "$lock" 2>/dev/null; do sleep 2; done
  trap 'rmdir "'"$lock"'" 2>/dev/null || true' EXIT
  ensure_driver
  local driver="$VERIFY_ROOT/driver"
  cp "$journey" "$driver/Sources/VerifyDrive/main.swift"
  cp "$SKILL_DIR/journeys/Support/Verify.swift" "$driver/Sources/VerifyDrive/Verify.swift"
  echo "building journey '$label' against $REPO (log: $ev/build.log)"
  if ! swift build --package-path "$driver" --product VerifyDrive >"$ev/build.log" 2>&1; then
    rmdir "$lock"; trap - EXIT
    echo 2 >"$ev/exit_code"
    grep -E 'error:' "$ev/build.log" | head -20 >&2
    echo "verify: journey build failed; evidence in $ev" >&2
    exit 2
  fi
  local bin
  bin="$(swift build --package-path "$driver" --show-bin-path)/VerifyDrive"
  mkdir -p "$RUN_DIR/bin"
  cp "$bin" "$RUN_DIR/bin/$label"
  rmdir "$lock"; trap - EXIT

  local started code=0
  started="$(date -u +%FT%TZ)"
  env SUPABASE_URL="$SUPABASE_URL" SUPABASE_PUBLISHABLE_KEY="$SUPABASE_PUBLISHABLE_KEY" \
    SUPABASE_SERVICE_ROLE_KEY="$SUPABASE_SERVICE_ROLE_KEY" VERIFY_EVIDENCE_DIR="$ev" \
    VERIFY_RUN_ID="$RUN_ID" \
    "$RUN_DIR/bin/$label" > >(tee "$ev/stdout.txt") 2> >(tee "$ev/stderr.txt" >&2) || code=$?
  wait
  echo "$code" >"$ev/exit_code"
  jq -n --arg run "$RUN_ID" --arg label "$label" --arg journey "$1" --arg sha "$(git -C "$REPO" rev-parse HEAD)" \
    --arg diff "$(git -C "$REPO" diff --stat HEAD -- Sources | tail -1)" --arg started "$started" \
    --arg finished "$(date -u +%FT%TZ)" --arg url "$SUPABASE_URL" --argjson code "$code" \
    '{run: $run, label: $label, journey: $journey, sdk_head: $sha, sdk_uncommitted_sources: $diff,
      supabase_url: $url, started: $started, finished: $finished, exit_code: $code}' >"$ev/meta.json"
  echo "evidence: $ev (exit $code)"
  return "$code"
}

cmd_sql() {
  [[ $# -ge 1 ]] || die "usage: verify.sh sql \"<query>\""
  resolve_run
  (cd "$RUN_DIR" && with_timeout 60 supabase db query --local --output-format json "$1" 2>/dev/null) | jq '.rows'
}

cmd_http() {
  [[ $# -ge 2 ]] || die "usage: verify.sh http <METHOD> </path> [json-body]"
  resolve_run
  local body_file
  body_file="$(mktemp)"
  local code
  code="$(http_code "$1" "$SUPABASE_URL$2" "$SUPABASE_SERVICE_ROLE_KEY" "${3:-}" "$body_file")"
  echo "HTTP $code"
  cat "$body_file"; echo
  rm -f "$body_file"
}

cmd_list() {
  local f
  for f in "$VERIFY_ROOT"/runs/*/state.env; do
    [[ -f "$f" ]] || continue
    (source "$f"; echo "live  $RUN_ID  $SUPABASE_URL  stack $STACK_ID")
  done
  for f in "$VERIFY_ROOT"/evidence/*/; do
    [[ -d "$f" ]] && echo "evidence  $f"
  done
  return 0
}

cmd_down() {
  local id="${VERIFY_RUN_ID:-}"
  if [[ -z "$id" ]]; then resolve_run; id="$RUN_ID"; fi
  check_name "run id" "$id"
  local run="$VERIFY_ROOT/runs/$id"
  [[ -d "$run" ]] || die "no run directory '$run'"
  if [[ -d "$run/supabase" ]]; then
    (cd "$run" && with_timeout 120 supabase stop >/dev/null 2>&1) || echo "verify: supabase stop failed" >&2
    local out
    # "No managed stack" means a failed `up` never created one; anything else keeps the run
    # folder so the teardown can be retried.
    if ! out="$(cd "$run" && with_timeout 120 supabase stack destroy --yes 2>&1)" &&
      ! grep -q 'No managed stack was found' <<<"$out"; then
      echo "$out" | tail -5 >&2
      die "stack destroy failed; kept $run. Retry 'verify.sh down', or run 'supabase stack destroy --yes' in $run"
    fi
  fi
  local base=""
  [[ -f "$run/state.env" ]] && base="$(sed -n 's/^PORT_BASE=//p' "$run/state.env")"
  rm -rf "$run"
  if [[ -n "$base" ]] && port_busy $((base + 21)); then
    echo "verify: port $((base + 21)) still listening after teardown" >&2
    exit 1
  fi
  echo "run '$id' torn down; evidence kept in $VERIFY_ROOT/evidence/$id"
}

case "${1:-}" in
  up) shift; cmd_up "$@" ;;
  doctor) shift; cmd_doctor "$@" ;;
  drive) shift; cmd_drive "$@" ;;
  sql) shift; cmd_sql "$@" ;;
  http) shift; cmd_http "$@" ;;
  list) shift; cmd_list "$@" ;;
  down) shift; cmd_down "$@" ;;
  *) sed -n '2,5p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 64 ;;
esac
