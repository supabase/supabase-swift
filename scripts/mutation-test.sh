#!/usr/bin/env bash
# Runs swift-mutation-testing on the critical parts of the SDK.
#
# Usage: scripts/mutation-test.sh [scope|all] [swift-mutation-testing options]
#
# Scopes: auth, helpers, postgrest, realtime, realtime-core.
#
# The tool cannot run at the repository root: Supabase.xcworkspace references the root itself
# (`group:`), which the tool refuses, and a plain SwiftPM run cannot build the tests without the
# macOS test flags. So the package is copied into .mutation-testing/<scope>/supabase-swift/ and
# built through a workspace that references that folder. The copy keeps file times, so the tool's
# kept sandboxes build incrementally between runs.
#
# Reports go to .mutation-testing/reports/<scope>.{json,md}. The exit code is 0 when every run
# passed, 2 when a quality gate failed, and 1 on any other error.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${MUTATION_WORKDIR:-$ROOT/.mutation-testing}"
REPORTS="$WORK/reports"

# scope scheme source-file (relative to Sources/) [extra swift-mutation-testing options]
#
# Realtime: under xcodebuild the suite takes 140-170 s with no mutation, more than the tool's
# default 120 s timeout. A timeout counts as detected, so a limit below the suite's own time
# reports every survivor as detected. Each Realtime file takes about two hours, so each is a scope
# of its own.
# RealtimeCore+Connection.swift and PersistedSessionCodec.swift join arrays and strings with `+`.
# A mutant that makes it `-` does not compile, and in a schematized build it takes every other
# mutant of the file down with it.
SCOPES=(
  "helpers Helpers Helpers/HTTP/RetryRequestInterceptor.swift"
  "helpers Helpers Helpers/HTTP/RetryPolicy.swift"
  "helpers Helpers Helpers/HTTP/AccessTokenMiddleware.swift"
  "helpers Helpers Helpers/Logger/LogRedaction.swift"
  "auth Auth Auth/Internal/PKCE.swift"
  "auth Auth Auth/Internal/SessionStore.swift"
  "auth Auth Auth/Internal/Refresher.swift"
  "auth Auth Auth/Internal/Persistence/PersistedSessionCodec.swift --disable-mutator ArithmeticOperatorReplacement"
  "postgrest PostgREST PostgREST/Filters/PostgrestFilterValue.swift"
  "postgrest PostgREST PostgREST/Untyped/PostgrestFilterBuilder.swift"
  "realtime Realtime Realtime/Shell/ClientState.swift --timeout 300"
  "realtime-core Realtime Realtime/Core/RealtimeCore+Connection.swift --timeout 300 --disable-mutator ArithmeticOperatorReplacement"
)

FILTER="all"
if [[ $# -gt 0 && "$1" != -* ]]; then
  FILTER="$1"
  shift
fi
case "$FILTER" in
  all | auth | helpers | postgrest | realtime | realtime-core) ;;
  *)
    echo "Unknown scope: $FILTER (expected auth, helpers, postgrest, realtime, realtime-core or all)" >&2
    exit 1
    ;;
esac

if ! command -v swift-mutation-testing >/dev/null; then
  echo "swift-mutation-testing is not installed. See \"Mutation testing\" in DEVELOPMENT.md." >&2
  exit 1
fi

# Each module gets its own wrapper folder: the tool keys its kept sandboxes by project path, and
# a sandbox built for one scheme must not be reused for another.
prepare() {
  local dir="$1"
  mkdir -p "$dir/supabase-swift" "$dir/Mutation.xcworkspace/xcshareddata/xcschemes"
  rsync -a --delete \
    --exclude /.build --exclude /.git --exclude /.mutation-testing --exclude /.swiftpm \
    --exclude /Examples --exclude /Supabase.xcworkspace --exclude /docs --exclude /supabase \
    --exclude /tools \
    "$ROOT/" "$dir/supabase-swift/"
  cat >"$dir/Mutation.xcworkspace/contents.xcworkspacedata" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<Workspace
   version = "1.0">
   <FileRef
      location = "group:supabase-swift">
   </FileRef>
</Workspace>
EOF
  # Xcode's generated product schemes (Auth, PostgREST, ...) have no test bundles. The shared
  # schemes do, but they refer to the root package as `container:`, which is the copy here.
  local scheme
  for scheme in "$ROOT"/Supabase.xcworkspace/xcshareddata/xcschemes/*.xcscheme; do
    sed 's|ReferencedContainer = "container:"|ReferencedContainer = "container:supabase-swift"|' \
      "$scheme" >"$dir/Mutation.xcworkspace/xcshareddata/xcschemes/$(basename "$scheme")"
  done
  # Helpers has no shared scheme, and Xcode generates none once shared schemes exist.
  sed 's|"Auth|"Helpers|g' "$dir/Mutation.xcworkspace/xcshareddata/xcschemes/Auth.xcscheme" \
    >"$dir/Mutation.xcworkspace/xcshareddata/xcschemes/Helpers.xcscheme"
  cp "$ROOT/scripts/mutation-testing.yml" "$dir/.swift-mutation-testing.yml"
}

mkdir -p "$REPORTS"
prepared=" "
status=0
summary=()
for scope in "${SCOPES[@]}"; do
  read -r module scheme file options <<<"$scope"
  read -ra extra <<<"${options:-}"
  [[ "$FILTER" == "all" || "$FILTER" == "$module" ]] || continue

  dir="$WORK/$module"
  if [[ "$prepared" != *" $module "* ]]; then
    prepare "$dir"
    prepared+="$module "
  fi

  name="$(basename "$file" .swift)"
  echo "==> $module: $file"
  set +e
  (cd "$dir" && swift-mutation-testing . \
    --scheme "$scheme" \
    --sources-path "supabase-swift/Sources/$file" \
    ${extra[@]+"${extra[@]}"} \
    --output "$REPORTS/$name.json" \
    --markdown-output "$REPORTS/$name.md" \
    "$@")
  code=$?
  set -e

  summary+=("$(printf '%-40s exit %s' "$file" "$code")")
  if [[ $code -eq 1 ]]; then
    status=1
  elif [[ $code -eq 2 && $status -eq 0 ]]; then
    status=2
  fi
done

echo
echo "Reports: $REPORTS"
printf '%s\n' "${summary[@]}"
exit "$status"
