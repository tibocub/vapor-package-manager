#!/bin/sh
# Run all tests from the repository root: tests/run.sh   (vpm runs on vlr; VLR=/path/to/vlr overrides)
cd "$(dirname "$0")/.." && VLR=${VLR:-vlr} && export VLR && for t in tests/test_*.lua; do "$VLR" "$t" || exit 1; done
