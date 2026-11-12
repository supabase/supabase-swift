#!/usr/bin/env bash
# Fails when a DocC article is not linked from the landing page of its catalog. An article that
# no page links to does not show in the navigation.
set -euo pipefail

status=0
for catalog in Sources/*/*.docc; do
  module=$(basename "$catalog" .docc)
  landing="$catalog/$module.md"
  if [[ ! -f "$landing" ]]; then
    echo "$catalog: no landing page ($module.md)"
    status=1
    continue
  fi
  for article in "$catalog"/*.md; do
    name=$(basename "$article" .md)
    [[ "$name" == "$module" ]] && continue
    # An extension file documents a symbol, so it needs no link.
    head -n 1 "$article" | grep -q '^# ``' && continue
    if ! grep -q "<doc:$name>" "$landing"; then
      echo "$article: not linked from $landing (add \"- <doc:$name>\" to a Topics group)"
      status=1
    fi
  done
done

for module in Auth Functions PostgREST Realtime Storage Supabase; do
  if [[ ! -d "Sources/$module/$module.docc" ]]; then
    echo "Sources/$module: no DocC catalog"
    status=1
  fi
done

exit "$status"
