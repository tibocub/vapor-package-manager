#!/bin/sh
# tools/publish-index.sh INDEX_OUT REPO_DIR : copy a built and signed index into the vpm-index checkout as ONE orphan commit and force-push it (GitHub Pages serves main).
# INDEX_OUT holds index/ and blobs/ (the output of index-builder/build.lua emit + sign.lua sign). Never put key.pem there.
set -e
out=$1 repo=$2
[ -d "$out/index/v1" ] && [ -f "$out/index/v1/meta.json.sig" ] || { echo "not a signed index: $out" >&2; exit 1; }
find "$out" -name '*.pem' | grep -q . && { echo "refusing: a .pem file is inside $out" >&2; exit 1; }
cd "$repo"
git checkout -q --orphan next
git rm -rqf . >/dev/null 2>&1 || true
cp -a "$out/index" "$out/blobs" .
touch .nojekyll
git checkout -q main -- README.md 2>/dev/null || true
git add -A
git commit -qm "vpm index $(date +%F)"
git branch -M main
git push -f origin main
