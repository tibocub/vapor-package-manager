#!/bin/sh
# Run all tests from the repository root: tests/run.sh
cd "$(dirname "$0")/.." && for t in tests/test_*.lua; do lua "$t" || exit 1; done
