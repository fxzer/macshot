#!/bin/bash
set -euo pipefail

PRESENTATION_TEST_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PRESENTATION_TEST_TMP="$(mktemp -d -t macshot-overlay-presentation)"
trap 'rm -rf "$PRESENTATION_TEST_TMP"' EXIT

swiftc -parse-as-library \
    "$PRESENTATION_TEST_ROOT/macshot/UI/Overlay/Window/OverlayWindowController+Window.swift" \
    "$PRESENTATION_TEST_ROOT/macshot/UI/Overlay/Window/OverlayWindowController+Presentation.swift" \
    "$PRESENTATION_TEST_ROOT/tests/OverlayPresentationTests.swift" \
    -o "$PRESENTATION_TEST_TMP/overlay-presentation-tests"
"$PRESENTATION_TEST_TMP/overlay-presentation-tests"
