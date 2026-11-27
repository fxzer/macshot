#!/bin/bash
set -euo pipefail

LATENCY_TEST_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LATENCY_TEST_TMP="$(mktemp -d -t macshot-capture-latency)"
trap 'rm -rf "$LATENCY_TEST_TMP"' EXIT

# 与应用一致启用 MainActor 默认隔离，防止普通 swiftc 掩盖主线程阻塞。
swiftc -O -parse-as-library -default-isolation MainActor \
    -enable-upcoming-feature NonisolatedNonsendingByDefault \
    "$LATENCY_TEST_ROOT/macshot/Capture/WindowListDisplaySnapshot.swift" \
    "$LATENCY_TEST_ROOT/macshot/App/CaptureRequestWatchdog.swift" \
    "$LATENCY_TEST_ROOT/tests/CaptureLatencyTests.swift" \
    -o "$LATENCY_TEST_TMP/capture-latency-tests"
"$LATENCY_TEST_TMP/capture-latency-tests"
