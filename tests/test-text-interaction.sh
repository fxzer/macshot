#!/bin/bash
set -euo pipefail

TEXT_TEST_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEXT_TEST_TMP="$(mktemp -d -t macshot-text-interaction)"
trap 'rm -rf "$TEXT_TEST_TMP"' EXIT

# 直接运行生产事件路由与拖动逻辑；不复制待测命中算法。
cat "$TEXT_TEST_ROOT/macshot/UI/Overlay/Input/OverlayView+HitTesting.swift" \
    "$TEXT_TEST_ROOT/macshot/UI/Overlay/Input/OverlayView+LiveTextInteraction.swift" \
    "$TEXT_TEST_ROOT/tests/TextInteractionTests.swift" > "$TEXT_TEST_TMP/main.swift"
swift "$TEXT_TEST_TMP/main.swift"
