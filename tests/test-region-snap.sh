#!/bin/bash
set -euo pipefail

REGION_SNAP_TEST_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REGION_SNAP_TEST_TMP="$(mktemp -d -t macshot-region-snap)"
trap 'rm -rf "$REGION_SNAP_TEST_TMP"' EXIT

swiftc -parse-as-library -default-isolation MainActor \
    -enable-upcoming-feature NonisolatedNonsendingByDefault \
    "$REGION_SNAP_TEST_ROOT/macshot/UI/Overlay/Selection/RegionSnapDetector.swift" \
    "$REGION_SNAP_TEST_ROOT/tests/RegionSnapTests.swift" \
    -o "$REGION_SNAP_TEST_TMP/region-snap-tests"
"$REGION_SNAP_TEST_TMP/region-snap-tests"
