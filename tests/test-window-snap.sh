#!/bin/bash
set -euo pipefail

WINDOW_SNAP_TEST_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WINDOW_SNAP_TEST_TMP="$(mktemp -d -t macshot-window-snap)"
trap 'rm -rf "$WINDOW_SNAP_TEST_TMP"' EXIT

# 与应用一致启用 MainActor 默认隔离，防止普通 swiftc 掩盖隔离问题。
swiftc -parse-as-library -default-isolation MainActor \
    -enable-upcoming-feature NonisolatedNonsendingByDefault \
    "$WINDOW_SNAP_TEST_ROOT/macshot/UI/Overlay/Selection/WindowSnapDetector.swift" \
    "$WINDOW_SNAP_TEST_ROOT/macshot/UI/Overlay/Selection/WindowSnapHoverTracker.swift" \
    "$WINDOW_SNAP_TEST_ROOT/tests/WindowSnapTests.swift" \
    -o "$WINDOW_SNAP_TEST_TMP/window-snap-tests"
"$WINDOW_SNAP_TEST_TMP/window-snap-tests"
