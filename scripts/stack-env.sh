#!/usr/bin/env bash
# Prints the endpoints the integration tests read from a running experimental stack, as KEY=value
# lines. The stack picks its own ports, so the tests cannot assume the defaults.
#
#   scripts/stack-env.sh Tests/IntegrationTests                  # print
#   scripts/stack-env.sh Tests/IntegrationTests test             # a project started with --stack test
#   export $(scripts/stack-env.sh Tests/IntegrationTests)        # use in the current shell
#   scripts/stack-env.sh Tests/IntegrationTests >> "$GITHUB_ENV" # use in later CI steps
#
# Run it after `supabase start`, with SUPABASE_EXPERIMENTAL_STACK=1 set. The Docker stack
# (Linux) keeps the default ports, which the tests already use, so skip this script there.
set -euo pipefail

project="${1:?usage: stack-env.sh <supabase project directory> [stack name]}"
stack_args=()
if [[ -n "${2:-}" ]]; then
  stack_args=(--stack "$2")
fi
export SUPABASE_EXPERIMENTAL_STACK=1

status="$(cd "$project" && supabase status ${stack_args[@]+"${stack_args[@]}"} --env --output-format text)"
api_url="$(sed -n "s/^API_URL='\(.*\)'$/\1/p" <<<"$status")"
mailpit_url="$(sed -n "s/^MAILPIT_URL='\(.*\)'$/\1/p" <<<"$status")"

if [[ -z "$api_url" ]]; then
  echo "stack-env.sh: no API_URL in 'supabase status' for $project" >&2
  exit 1
fi

echo "SUPABASE_URL=$api_url"
# A project that turns Mailpit off has no MAILPIT_URL.
if [[ -n "$mailpit_url" ]]; then
  echo "MAILPIT_URL=$mailpit_url"
fi
