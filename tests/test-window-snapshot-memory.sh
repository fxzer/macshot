#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR="$(mktemp -d -t macshot-snapshot-mem)"
TEST_BIN="$TEST_DIR/snapshot-leak-test"
TEST_MAIN="$TEST_DIR/main.swift"
trap 'rm -rf "$TEST_DIR"' EXIT

cat > "$TEST_MAIN" <<'EOF'
import Cocoa
import CoreGraphics

let displayID = CGMainDisplayID()

for _ in 0..<4 {
    autoreleasepool {
        // 通道 1：无排除窗口，走 CGDisplayCreateImage
        let img1 = WindowListDisplaySnapshot.captureDisplay(displayID, excludingWindowIDs: [])
        precondition(img1 != nil && img1!.width > 0 && img1!.height > 0, "CGDisplayCreateImage 返回空图像")

        // 通道 2：有排除窗口，走 CGWindowListCreateImageFromArray
        let img2 = WindowListDisplaySnapshot.captureDisplay(displayID, excludingWindowIDs: [1])
        precondition(img2 != nil && img2!.width > 0 && img2!.height > 0, "CGWindowListCreateImageFromArray 返回空图像")
    }
}
print("Captured 8 full-display snapshots successfully.")
EOF

swiftc \
    "$ROOT_DIR/macshot/Capture/WindowListDisplaySnapshot.swift" \
    "$TEST_MAIN" \
    -o "$TEST_BIN"

LEAKS_OUTPUT="$(leaks --atExit -- "$TEST_BIN" 2>&1)" || {
    echo "$LEAKS_OUTPUT"
    exit 1
}

echo "$LEAKS_OUTPUT" | grep -E "Captured |leaks for"
echo "$LEAKS_OUTPUT" | grep -q "0 leaks for 0 total leaked bytes"
echo "PASS: WindowListDisplaySnapshot zero-leak check passed."
