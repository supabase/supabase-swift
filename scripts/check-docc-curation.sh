#!/usr/bin/env bash
# Fails when a DocC article is not a Topics list item on the landing page of its catalog. An article that
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
  while IFS= read -r article; do
    name=$(basename "$article" .md)
    [[ "$name" == "$module" ]] && continue
    # An extension file documents a symbol, so it needs no link.
    head -n 1 "$article" | grep -q '^# ``' && continue
    if ! grep -Eq "^- <doc:$name>[[:space:]]*$" "$landing"; then
      echo "$article: not linked from $landing (add \"- <doc:$name>\" to a Topics group)"
      status=1
    fi
  done < <(find "$catalog" -name '*.md' | sort)
done

for module in Auth Functions PostgREST Realtime Storage Supabase; do
  if [[ ! -d "Sources/$module/$module.docc" ]]; then
    echo "Sources/$module: no DocC catalog"
    status=1
  fi
done

exit "$status"
