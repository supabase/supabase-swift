#!/usr/bin/env bash

env_file="${1:-.env}"

if [ ! -f "$env_file" ]; then
    echo "Error: Environment file '$env_file' not found." >&2
    exit 1
fi

while IFS= read -r line; do
    line="$(echo "${line%%#*}" | xargs)"
    if [ -n "$line" ]; then
        export "$line" || {
            echo "Error exporting: $line" >&2
            exit 1
        }
    fi
done <"$env_file"
