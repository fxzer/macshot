#!/bin/bash
set -euo pipefail

BACKDROP_TEST_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BACKDROP_TEST_TMP="$(mktemp -d -t macshot-overlay-backdrop)"
trap 'rm -rf "$BACKDROP_TEST_TMP"' EXIT

# 提取生产背景绘制方法，直接验证输出像素，不另写一套待测实现。
python3 - "$BACKDROP_TEST_ROOT" "$BACKDROP_TEST_TMP/main.swift" <<'PY'
import sys
from pathlib import Path
root = Path(sys.argv[1])
source = (root / 'macshot/UI/Overlay/Rendering/OverlayView+DrawPipeline.swift').read_text()
start = source.index('    private func drawOverlayBackdrop(')
end = source.index('    private func drawRemoteSelectionIfNeeded(', start)
tests = (root / 'tests/OverlayBackdropTests.swift').read_text()
Path(sys.argv[2]).write_text(tests + '\nextension OverlayView {\n' + source[start:end] + '\n}\n')
PY
swiftc -O -parse-as-library -default-isolation MainActor \
    "$BACKDROP_TEST_TMP/main.swift" -o "$BACKDROP_TEST_TMP/overlay-backdrop-tests"
"$BACKDROP_TEST_TMP/overlay-backdrop-tests"
