#!/bin/sh
# report.sh MANIFEST RSPEC_DIR -- run the filter over downloaded rockspecs (index-builder/run.lua report) under process limits:
# 1 GB of address space and 10 minutes of CPU, so a rockspec that gets past the sandbox's own limits still cannot take the machine.
# Run it with a vlr (VLR=path, default "vlr").
set -eu
cd "$(dirname "$0")/.."
ulimit -v 1048576
ulimit -t 600
exec "${VLR:-vlr}" index-builder/run.lua report "$1" "$2"
