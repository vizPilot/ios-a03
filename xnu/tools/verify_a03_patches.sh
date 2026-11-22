#!/bin/bash
# Verify that xnu/patches-a03/*.patch apply cleanly, in order, to a pristine
# xnu-12377.121.6 tree. The tree itself is never modified.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
PATCHES="$HERE/../patches-a03"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
cp -a "$HERE/../../xnu-src" "$WORK/xnu"
cd "$WORK/xnu"
for p in "$PATCHES"/*.patch; do
    echo "== $(basename "$p")"
    git apply --check "$p"
    git apply "$p"
done
echo "ALL PATCHES APPLIED"
grep -n "A03" makedefs/MakeInc.def | head -10
ls -l config/MASTER.arm64.a03 pexpert/pexpert/arm64/A03.h osfmk/arm64/a03_early.c
