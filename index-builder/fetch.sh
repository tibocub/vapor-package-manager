#!/bin/sh
# fetch.sh LIST DIR -- download "name version" lines as rockspecs into DIR (8 in parallel, skips existing).
# ~5000 files of 1-3 KB; polite: 8 connections, retries, one file per request.
set -eu
list=$1; dir=$2
mkdir -p "$dir"
awk '{print $1 "-" $2 ".rockspec"}' "$list" | while read -r f; do [ -s "$dir/$f" ] || echo "$f"; done |
  xargs -P 8 -I{} sh -c 'curl -sSf --retry 2 -m 30 -o "'"$dir"'/{}" "https://luarocks.org/{}" 2>>"'"$dir"'/.errors" || rm -f "'"$dir"'/{}"'
echo "have $(ls "$dir" | wc -l) rockspecs, $(wc -l < "$dir/.errors" 2>/dev/null || echo 0) errors"
