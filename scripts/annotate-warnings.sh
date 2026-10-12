#!/usr/bin/env bash
# Emits one GitHub Actions warning annotation per unique compiler warning, merging the
# per-job files produced by scripts/collect-warnings.sh.
#
# The build matrix compiles the same sources for every platform, Xcode version and
# configuration, so letting each job annotate its own warnings puts the same diagnostic on
# the same line ten-plus times in the pull request diff. Instead the matrix jobs only
# collect, and this script (running once, in the `warnings` job) annotates the union.
#
# Usage: scripts/annotate-warnings.sh <directory-with-collected-warnings>
set -euo pipefail

DIRECTORY="${1?usage: annotate-warnings.sh <directory>}"

MERGED="$(mktemp)"
trap 'rm -f "$MERGED"' EXIT

if [[ -d "$DIRECTORY" ]]; then
  find "$DIRECTORY" -type f -name '*.tsv' -exec cat {} + | sort -u -o "$MERGED" || true
fi

COUNT=$(wc -l <"$MERGED" | tr -d ' ')

summary() {
  if [[ -n "${GITHUB_STEP_SUMMARY-}" ]]; then
    cat >>"$GITHUB_STEP_SUMMARY"
  else
    cat
  fi
}

if [[ "$COUNT" -eq 0 ]]; then
  echo "No compiler warnings collected."
  echo "### ✅ No compiler warnings" | summary
  exit 0
fi

# GitHub only surfaces the first handful of annotations per step, so the summary carries
# the full list.
{
  echo "### ⚠️ $COUNT unique compiler warning(s)"
  echo
  echo "| File | Line | Warning |"
  echo "| --- | --- | --- |"
  while IFS=$'\t' read -r path line column message; do
    echo "| \`$path\` | $line | ${message//|/\\|} |"
  done <"$MERGED"
  echo
  echo "Annotations shown in the diff are deduplicated across the whole build matrix."
} | summary

while IFS=$'\t' read -r path line column message; do
  # Percent, carriage return and newline are the characters GitHub's workflow command
  # parser treats specially in an annotation message.
  escaped="${message//\%/%25}"
  escaped="${escaped//$'\r'/%0D}"
  escaped="${escaped//$'\n'/%0A}"
  echo "::warning file=$path,line=$line,col=$column::$escaped"
done <"$MERGED"
