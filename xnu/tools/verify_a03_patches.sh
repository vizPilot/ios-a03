#!/bin/bash
# Verify that xnu/patches-a03/*.patch apply cleanly, in order, to a tree that
# already contains the Bergamota donor series. Set A03_XNU_ROOT to that tree;
# it defaults to the pristine xnu-src for backwards compatibility.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
PATCHES="$HERE/../patches-a03"
BASE="${A03_XNU_ROOT:-$HERE/../../xnu-src}"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
cp -a "$BASE" "$WORK/xnu"
cd "$WORK/xnu"
for p in "$PATCHES"/*.patch; do
    # Donor-patched trees may already contain 0006/0009; the generator then
    # emits an empty file, which `git apply` rejects as "no valid patches".
    if ! grep -q '^@@' "$p"; then
        echo "== $(basename "$p") (sin hunks, omitido)"
        continue
    fi
    echo "== $(basename "$p")"
    git apply --check "$p"
    git apply "$p"
done
echo "ALL PATCHES APPLIED"
grep -n "A03" makedefs/MakeInc.def | head -10
ls -l config/MASTER.arm64.a03 pexpert/pexpert/arm64/A03.h osfmk/arm64/a03_early.c
