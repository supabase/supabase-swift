#!/usr/bin/env bash
set -euo pipefail

(cd Tests/IntegrationTests && supabase start && supabase db reset)
swift test --filter IntegrationTests --no-parallel
(cd Tests/IntegrationTests && supabase stop)
