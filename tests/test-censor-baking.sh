#!/bin/bash
set -euo pipefail

CENSOR_TEST_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CENSOR_TEST_TMP="$(mktemp -d -t macshot-censor-baking)"
trap 'rm -rf "$CENSOR_TEST_TMP"' EXIT

cat "$CENSOR_TEST_ROOT/macshot/Processors/ImageRasterizer.swift" \
    "$CENSOR_TEST_ROOT/macshot/UI/Overlay/Rendering/Renderers/Annotation+DrawingCensor.swift" \
    "$CENSOR_TEST_ROOT/tests/CensorBakingTests.swift" > "$CENSOR_TEST_TMP/main.swift"

# Strip duplicate imports after concatenation while keeping the top imports
python3 - << 'PY' "$CENSOR_TEST_TMP/main.swift"
import sys
path = sys.argv[1]
with open(path, "r") as f:
    lines = f.readlines()
seen_imports = set()
out = []
for line in lines:
    s = line.strip()
    if s.startswith("import "):
        if s in seen_imports:
            continue
        seen_imports.add(s)
    out.append(line)
with open(path, "w") as f:
    f.writelines(out)
PY

swiftc -parse-as-library -O "$CENSOR_TEST_TMP/main.swift" -o "$CENSOR_TEST_TMP/run"
"$CENSOR_TEST_TMP/run"
