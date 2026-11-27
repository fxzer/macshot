#!/bin/bash
set -euo pipefail

TEXT_TEST_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEXT_TEST_TMP="$(mktemp -d -t macshot-text-interaction)"
trap 'rm -rf "$TEXT_TEST_TMP"' EXIT

# 直接运行生产事件路由、拖动逻辑与文本编辑器；不复制待测命中和排版算法。
cat "$TEXT_TEST_ROOT/macshot/UI/Tools/TextEditingController.swift" \
    "$TEXT_TEST_ROOT/macshot/UI/Overlay/Input/OverlayView+HitTesting.swift" \
    "$TEXT_TEST_ROOT/macshot/UI/Overlay/Input/OverlayView+LiveTextInteraction.swift" \
    "$TEXT_TEST_ROOT/tests/TextInteractionTests.swift" > "$TEXT_TEST_TMP/main.swift"
# 解释执行会在编译这个体量的文件时崩溃前端，先编译再运行。
swiftc -O "$TEXT_TEST_TMP/main.swift" -o "$TEXT_TEST_TMP/run"
"$TEXT_TEST_TMP/run"
