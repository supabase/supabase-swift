#!/usr/bin/env bash
set -euo pipefail

(cd Tests/IntegrationTests && supabase start && supabase db reset)
swift test --filter IntegrationTests
(cd Tests/IntegrationTests && supabase stop)
