#!/usr/bin/env bash
# Turns on the Storage features the Supabase CLI leaves off, for the integration tests.
#
# The CLI starts Storage without object lifecycles, object versioning, analytics (Iceberg) buckets
# or a CDN purge endpoint, and has no setting for them. On the Docker stack, this script recreates the CLI's
# storage container with the same configuration plus:
#
# - STORAGE_LIFECYCLE_ENABLED=true, STORAGE_VERSIONING_ENABLED=true and ICEBERG_ENABLED=true;
# - CDN_PURGE_ENDPOINT_URL pointing at a stub that records each purge Storage forwards. The stub
#   answers `GET /requests` with them and `DELETE /requests` clears them, on host port 54329.
#
# Run it after `supabase start`, then run the tests with STORAGE_TEST_FEATURES=1. The native
# stack (macOS) runs no containers, so it cannot use this script; its tests check that Storage
# refuses each call instead.
#
# Usage: enable-storage-test-features.sh [project-dir]  (default: Tests/IntegrationTests)
set -euo pipefail

PROJECT_DIR=${1:-Tests/IntegrationTests}
PROJECT_ID=$(sed -n 's/^project_id *= *"\(.*\)"/\1/p' "$PROJECT_DIR/supabase/config.toml")
STORAGE="supabase_storage_$PROJECT_ID"
if [[ -z "$PROJECT_ID" ]] || ! docker inspect "$STORAGE" >/dev/null 2>&1; then
  echo "No $STORAGE container is running. Start the Docker stack in $PROJECT_DIR first." >&2
  exit 1
fi
NETWORK=$(docker inspect "$STORAGE" --format '{{.HostConfig.NetworkMode}}')
IMAGE=$(docker inspect "$STORAGE" --format '{{.Config.Image}}')
VOLUME=$(docker inspect "$STORAGE" --format '{{range .Mounts}}{{.Name}}{{end}}')

# The CLI's labels, so `supabase stop` removes both containers with the rest of the stack.
LABELS=()
while IFS= read -r label; do
  [[ -n "$label" ]] && LABELS+=(--label "$label")
done < <(docker inspect "$STORAGE" --format '{{range $k, $v := .Config.Labels}}{{println $k "=" $v}}{{end}}' | sed 's/ = /=/')

docker rm -f supabase_cdn_purge_stub >/dev/null 2>&1 || true
docker run -d --name supabase_cdn_purge_stub "${LABELS[@]}" \
  --network "$NETWORK" --network-alias cdn-purge-stub \
  -p 127.0.0.1:54329:8080 python:3.13-alpine python -c '
import json
from http.server import BaseHTTPRequestHandler, HTTPServer

requests = []

class Handler(BaseHTTPRequestHandler):
    def reply(self, body=b"{}"):
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        requests.append({"path": self.path, "body": json.loads(self.rfile.read(length) or b"null")})
        self.reply()

    def do_GET(self):
        self.reply(json.dumps(requests).encode())

    def do_DELETE(self):
        requests.clear()
        self.reply()

HTTPServer(("0.0.0.0", 8080), Handler).serve_forever()
' >/dev/null

ARGS=()
while IFS= read -r variable; do
  [[ -n "$variable" ]] && ARGS+=(-e "$variable")
done < <(docker inspect "$STORAGE" --format '{{range .Config.Env}}{{println .}}{{end}}')
ARGS+=(
  -e STORAGE_LIFECYCLE_ENABLED=true
  -e STORAGE_VERSIONING_ENABLED=true
  -e ICEBERG_ENABLED=true
  -e CDN_PURGE_ENDPOINT_URL=http://cdn-purge-stub:8080
)

docker rm -f "$STORAGE" >/dev/null
docker run -d --name "$STORAGE" "${LABELS[@]}" --network "$NETWORK" --network-alias storage -v "$VOLUME:/mnt" \
  --health-cmd 'wget --no-verbose --tries=1 --spider http://127.0.0.1:5000/status' \
  --health-interval 2s "${ARGS[@]}" "$IMAGE" node dist/start/server.js >/dev/null

for _ in $(seq 1 60); do
  if [[ "$(docker inspect "$STORAGE" --format '{{.State.Health.Status}}')" == healthy ]] \
    && curl -fsS http://127.0.0.1:54329/requests >/dev/null 2>&1; then
    echo "Storage restarted with lifecycles, versioning, Iceberg and a CDN purge stub."
    exit 0
  fi
  sleep 1
done
docker logs "$STORAGE" | tail -20
exit 1
