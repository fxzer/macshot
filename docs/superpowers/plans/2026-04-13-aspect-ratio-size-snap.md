# Aspect Ratio Size Snap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add adaptive size snapping for locked-aspect-ratio selection during both initial area selection and later resize, with temporary snap guide lines and size-label emphasis.

**Architecture:** Extract the snap math into a small pure Swift helper so the adaptive `50/100` stepping and threshold behavior can be verified independently from `OverlayView`. Then integrate that helper into the two existing selection paths in `OverlayView`, add transient snap state for rendering, and reuse a dedicated guide-line drawing path so the feedback stays localized to locked-ratio selection only.

**Tech Stack:** Swift, AppKit, `OverlayView`, pure Foundation/CoreGraphics helper code, standalone Swift verification script run with the Swift toolchain.

---

## File Map

- Create: `macshot/Services/AspectRatioSizeSnap.swift`
  Purpose: Pure snap math and small data types for adaptive step selection, threshold checking, and snapped-size results.

- Create: `scripts/verify_aspect_ratio_size_snap.swift`
  Purpose: Standalone verification script covering snap math edge cases without needing a full XCTest target.

- Modify: `macshot/UI/Overlay/OverlayView.swift`
  Purpose: Integrate snap logic into initial selection and later resize, track snap state, style the size label, and draw temporary snap guide lines.

- Reference: `docs/superpowers/specs/2026-04-13-aspect-ratio-size-snap-design.md`
  Purpose: Approved behavior reference for this implementation. Keep the shipped behavior aligned with this spec and leave the spec file unchanged in this plan.

---

### Task 1: Extract Snap Math Into a Pure Helper

**Files:**
- Create: `macshot/Services/AspectRatioSizeSnap.swift`
- Test: `scripts/verify_aspect_ratio_size_snap.swift`

- [ ] **Step 1: Write the failing verification script**

Create `scripts/verify_aspect_ratio_size_snap.swift` with the failing expectations first:

```swift
import Foundation
import CoreGraphics

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

let smallStep = aspectRatioSnapStep(for: CGSize(width: 350, height: 200))
expect(smallStep == 50, "short edge below 400 should use 50-point snapping")

let largeStep = aspectRatioSnapStep(for: CGSize(width: 900, height: 450))
expect(largeStep == 100, "short edge at or above 400 should use 100-point snapping")

let snapped = snapAspectRatioSize(
    drivingDimension: 297,
    step: 100,
    threshold: 10,
    ratio: 3.0 / 2.0,
    minSize: 10,
    snapAxis: .width
)
expect(snapped.isSnapped, "297 should snap to 300 within threshold")
expect(snapped.size.width == 300, "snapped width should be 300")
expect(snapped.size.height == 200, "paired height should be recomputed from ratio")

let unsnapped = snapAspectRatioSize(
    drivingDimension: 286,
    step: 100,
    threshold: 10,
    ratio: 3.0 / 2.0,
    minSize: 10,
    snapAxis: .width
)
expect(!unsnapped.isSnapped, "286 should not snap when outside threshold")
expect(unsnapped.size.width == 286, "unsnapped width should remain unchanged")

print("OK: aspect ratio size snap verification passed")
```

- [ ] **Step 2: Run the verification script to confirm it fails**

Run:

```bash
swift scripts/verify_aspect_ratio_size_snap.swift
```

Expected:

```text
FAIL: cannot find 'aspectRatioSnapStep' in scope
```

- [ ] **Step 3: Write the minimal pure helper implementation**

Create `macshot/Services/AspectRatioSizeSnap.swift`:

```swift
import Foundation
import CoreGraphics

enum AspectRatioSnapAxis {
    case width
    case height
}

struct AspectRatioSnapResult {
    let size: CGSize
    let isSnapped: Bool
    let snappedDimension: CGFloat?
}

func aspectRatioSnapStep(for size: CGSize) -> CGFloat {
    let shortEdge = min(size.width, size.height)
    return shortEdge < 400 ? 50 : 100
}

func snapAspectRatioSize(
    drivingDimension: CGFloat,
    step: CGFloat,
    threshold: CGFloat,
    ratio: CGFloat,
    minSize: CGFloat,
    snapAxis: AspectRatioSnapAxis
) -> AspectRatioSnapResult {
    let clampedDriving = max(minSize, drivingDimension)
    let target = (clampedDriving / step).rounded() * step
    let shouldSnap = abs(clampedDriving - target) <= threshold
    let finalDriving = shouldSnap ? max(minSize, target) : clampedDriving

    switch snapAxis {
    case .width:
        let width = finalDriving
        let height = max(minSize, width / ratio)
        return AspectRatioSnapResult(
            size: CGSize(width: width, height: height),
            isSnapped: shouldSnap,
            snappedDimension: shouldSnap ? width : nil
        )
    case .height:
        let height = finalDriving
        let width = max(minSize, height * ratio)
        return AspectRatioSnapResult(
            size: CGSize(width: width, height: height),
            isSnapped: shouldSnap,
            snappedDimension: shouldSnap ? height : nil
        )
    }
}
```

- [ ] **Step 4: Update the verification script so it compiles together with the helper**

Keep `scripts/verify_aspect_ratio_size_snap.swift` as the verification harness from Step 1, and run it together with the new helper file:

```bash
swift macshot/Services/AspectRatioSizeSnap.swift scripts/verify_aspect_ratio_size_snap.swift
```

Expected:

```text
OK: aspect ratio size snap verification passed
```

- [ ] **Step 5: Commit**

```bash
git add macshot/Services/AspectRatioSizeSnap.swift scripts/verify_aspect_ratio_size_snap.swift
git commit -m "feat: add aspect ratio size snap helper"
```

---

### Task 2: Integrate Snap Logic Into Initial Selection Drag

**Files:**
- Modify: `macshot/UI/Overlay/OverlayView.swift:5355-5404`
- Test: `scripts/verify_aspect_ratio_size_snap.swift`

- [ ] **Step 1: Add transient snap state storage to `OverlayView`**

In `OverlayView.swift`, add local state near the existing snap-guide properties:

```swift
    private var selectionSizeSnapActive = false
    private var selectionSizeSnapGuideX: CGFloat?
    private var selectionSizeSnapGuideY: CGFloat?
    private let selectionSizeSnapThreshold: CGFloat = 10
```

- [ ] **Step 2: Add a small helper for clearing transient selection-size snap state**

Add this private helper near the other selection helpers:

```swift
    private func clearSelectionSizeSnapState() {
        selectionSizeSnapActive = false
        selectionSizeSnapGuideX = nil
        selectionSizeSnapGuideY = nil
    }
```

- [ ] **Step 3: Add a helper that snaps a locked-ratio size and returns the adjusted size plus guide positions**

Add this helper inside `OverlayView.swift`:

```swift
    private func snappedLockedSelectionSize(
        width: CGFloat,
        height: CGFloat,
        ratio: CGFloat,
        snapAxis: AspectRatioSnapAxis,
        minSize: CGFloat
    ) -> CGSize {
        let rawSize = CGSize(width: width, height: height)
        let step = aspectRatioSnapStep(for: rawSize)
        let drivingDimension = snapAxis == .width ? width : height
        let result = snapAspectRatioSize(
            drivingDimension: drivingDimension,
            step: step,
            threshold: selectionSizeSnapThreshold,
            ratio: ratio,
            minSize: minSize,
            snapAxis: snapAxis
        )

        selectionSizeSnapActive = result.isSnapped
        if !result.isSnapped {
            selectionSizeSnapGuideX = nil
            selectionSizeSnapGuideY = nil
        }

        return result.size
    }
```

- [ ] **Step 4: Wire the helper into the `.selecting` locked-ratio branch**

Replace the current width/height-only logic in `mouseDragged` with this shape:

```swift
            if aspectRatioLock != .none {
                let targetRatio = aspectRatioLock.ratio
                let minSelectionSize: CGFloat = 1

                if rawH > 0 {
                    let proposedW = rawH * targetRatio
                    if proposedW <= rawW {
                        let snapped = snappedLockedSelectionSize(
                            width: max(1, proposedW),
                            height: max(1, rawH),
                            ratio: targetRatio,
                            snapAxis: .height,
                            minSize: minSelectionSize
                        )
                        w = snapped.width
                        h = snapped.height
                    } else {
                        let snapped = snappedLockedSelectionSize(
                            width: max(1, rawW),
                            height: max(1, rawW / targetRatio),
                            ratio: targetRatio,
                            snapAxis: .width,
                            minSize: minSelectionSize
                        )
                        w = snapped.width
                        h = snapped.height
                    }
                } else {
                    let snapped = snappedLockedSelectionSize(
                        width: max(1, rawW),
                        height: max(1, rawW / targetRatio),
                        ratio: targetRatio,
                        snapAxis: .width,
                        minSize: minSelectionSize
                    )
                    w = snapped.width
                    h = snapped.height
                }
            } else if shiftHeld {
                clearSelectionSizeSnapState()
                w = max(1, min(rawW, rawH))
                h = max(1, min(rawW, rawH))
            } else {
                clearSelectionSizeSnapState()
                w = max(1, rawW)
                h = max(1, rawH)
            }

            let x = selectionStart.x < point.x ? selectionStart.x : selectionStart.x - w
            let y = selectionStart.y < point.y ? selectionStart.y : selectionStart.y - h
            selectionRect = NSRect(x: x, y: y, width: w, height: h)

            if selectionSizeSnapActive {
                selectionSizeSnapGuideX = selectionStart.x < point.x ? selectionRect.maxX : selectionRect.minX
                selectionSizeSnapGuideY = selectionStart.y < point.y ? selectionRect.maxY : selectionRect.minY
            }
```

- [ ] **Step 5: Re-run the verification script**

Run:

```bash
swift macshot/Services/AspectRatioSizeSnap.swift scripts/verify_aspect_ratio_size_snap.swift
```

Expected:

```text
OK: aspect ratio size snap verification passed
```

- [ ] **Step 6: Commit**

```bash
git add macshot/UI/Overlay/OverlayView.swift
git commit -m "feat: snap locked aspect ratio during initial selection"
```

---

### Task 3: Integrate Snap Logic Into Existing Selection Resize

**Files:**
- Modify: `macshot/UI/Overlay/OverlayView.swift:6234-6340`
- Test: `scripts/verify_aspect_ratio_size_snap.swift`

- [ ] **Step 1: Add a small helper to classify which dimension drives each resize handle**

Add this helper near `resizedSelectionRect`:

```swift
    private func snapAxis(for handle: ResizeHandle) -> AspectRatioSnapAxis {
        switch handle {
        case .top, .bottom:
            return .height
        default:
            return .width
        }
    }
```

- [ ] **Step 2: Refactor the locked-ratio branch of `resizedSelectionRect` to snap before returning**

Adjust the locked-ratio branch into this shape:

```swift
        if let targetRatio = aspectRatio, targetRatio > 0 {
            let axis = snapAxis(for: handle)

            switch handle {
            case .bottomRight:
                let rawWidth = max(minSize, point.x - r.minX)
                let snapped = snappedLockedSelectionSize(
                    width: rawWidth,
                    height: rawWidth / targetRatio,
                    ratio: targetRatio,
                    snapAxis: axis,
                    minSize: minSize
                )
                let newOriginY = r.maxY - snapped.height
                let snappedRect = NSRect(x: r.minX, y: newOriginY, width: snapped.width, height: snapped.height)
                selectionSizeSnapGuideX = snappedRect.maxX
                selectionSizeSnapGuideY = snappedRect.minY
                return snappedRect

            case .bottomLeft:
                let rawWidth = max(minSize, r.maxX - point.x)
                let snapped = snappedLockedSelectionSize(
                    width: rawWidth,
                    height: rawWidth / targetRatio,
                    ratio: targetRatio,
                    snapAxis: axis,
                    minSize: minSize
                )
                let newOriginX = r.maxX - snapped.width
                let newOriginY = r.maxY - snapped.height
                let snappedRect = NSRect(x: newOriginX, y: newOriginY, width: snapped.width, height: snapped.height)
                selectionSizeSnapGuideX = snappedRect.minX
                selectionSizeSnapGuideY = snappedRect.minY
                return snappedRect

            case .topRight:
                let rawWidth = max(minSize, point.x - r.minX)
                let snapped = snappedLockedSelectionSize(
                    width: rawWidth,
                    height: rawWidth / targetRatio,
                    ratio: targetRatio,
                    snapAxis: axis,
                    minSize: minSize
                )
                let snappedRect = NSRect(x: r.minX, y: r.minY, width: snapped.width, height: snapped.height)
                selectionSizeSnapGuideX = snappedRect.maxX
                selectionSizeSnapGuideY = snappedRect.maxY
                return snappedRect

            case .topLeft:
                let rawWidth = max(minSize, r.maxX - point.x)
                let snapped = snappedLockedSelectionSize(
                    width: rawWidth,
                    height: rawWidth / targetRatio,
                    ratio: targetRatio,
                    snapAxis: axis,
                    minSize: minSize
                )
                let newOriginX = r.maxX - snapped.width
                let snappedRect = NSRect(x: newOriginX, y: r.minY, width: snapped.width, height: snapped.height)
                selectionSizeSnapGuideX = snappedRect.minX
                selectionSizeSnapGuideY = snappedRect.maxY
                return snappedRect

            case .right:
                let rawWidth = max(minSize, point.x - r.minX)
                let snapped = snappedLockedSelectionSize(
                    width: rawWidth,
                    height: rawWidth / targetRatio,
                    ratio: targetRatio,
                    snapAxis: axis,
                    minSize: minSize
                )
                let newOriginY = r.maxY - snapped.height
                let snappedRect = NSRect(x: r.minX, y: newOriginY, width: snapped.width, height: snapped.height)
                selectionSizeSnapGuideX = snappedRect.maxX
                selectionSizeSnapGuideY = snappedRect.minY
                return snappedRect

            case .left:
                let rawWidth = max(minSize, r.maxX - point.x)
                let snapped = snappedLockedSelectionSize(
                    width: rawWidth,
                    height: rawWidth / targetRatio,
                    ratio: targetRatio,
                    snapAxis: axis,
                    minSize: minSize
                )
                let newOriginX = r.maxX - snapped.width
                let newOriginY = r.maxY - snapped.height
                let snappedRect = NSRect(x: newOriginX, y: newOriginY, width: snapped.width, height: snapped.height)
                selectionSizeSnapGuideX = snappedRect.minX
                selectionSizeSnapGuideY = snappedRect.minY
                return snappedRect

            case .bottom:
                let rawHeight = max(minSize, r.maxY - point.y)
                let snapped = snappedLockedSelectionSize(
                    width: rawHeight * targetRatio,
                    height: rawHeight,
                    ratio: targetRatio,
                    snapAxis: axis,
                    minSize: minSize
                )
                let newOriginY = r.maxY - snapped.height
                let snappedRect = NSRect(x: r.minX, y: newOriginY, width: snapped.width, height: snapped.height)
                selectionSizeSnapGuideX = snappedRect.maxX
                selectionSizeSnapGuideY = snappedRect.minY
                return snappedRect

            case .top:
                let rawHeight = max(minSize, point.y - r.minY)
                let snapped = snappedLockedSelectionSize(
                    width: rawHeight * targetRatio,
                    height: rawHeight,
                    ratio: targetRatio,
                    snapAxis: axis,
                    minSize: minSize
                )
                let snappedRect = NSRect(x: r.minX, y: r.minY, width: snapped.width, height: snapped.height)
                selectionSizeSnapGuideX = snappedRect.maxX
                selectionSizeSnapGuideY = snappedRect.maxY
                return snappedRect

            default:
                clearSelectionSizeSnapState()
                return r
            }
        }
```

The important implementation rule for every case:

- preserve the current fixed edge/corner
- snap the handle’s driving dimension
- recompute the paired dimension from the ratio

- [ ] **Step 3: Clear transient snap state for freeform resize paths**

At the start of the non-locked branch of `resizedSelectionRect`, add:

```swift
        clearSelectionSizeSnapState()
```

And in `resizeSelection(to:)`, clear state when no locked ratio is active:

```swift
    private func resizeSelection(to point: NSPoint) {
        let minSize: CGFloat = 10
        if activeAspectRatio == nil {
            clearSelectionSizeSnapState()
        }
        selectionRect = resizedSelectionRect(
            from: selectionRect,
            handle: resizeHandle,
            to: point,
            minSize: minSize,
            aspectRatio: activeAspectRatio
        )
    }
```

- [ ] **Step 4: Re-run the verification script**

Run:

```bash
swift macshot/Services/AspectRatioSizeSnap.swift scripts/verify_aspect_ratio_size_snap.swift
```

Expected:

```text
OK: aspect ratio size snap verification passed
```

- [ ] **Step 5: Commit**

```bash
git add macshot/UI/Overlay/OverlayView.swift
git commit -m "feat: snap locked aspect ratio during resize"
```

---

### Task 4: Render Size-Label Emphasis and Temporary Snap Guide Lines

**Files:**
- Modify: `macshot/UI/Overlay/OverlayView.swift:2463-2538`
- Modify: `macshot/UI/Overlay/OverlayView.swift:3495-3520`
- Test: `scripts/verify_aspect_ratio_size_snap.swift`

- [ ] **Step 1: Add a highlighted style for the size label when snapping is active**

Replace the current size-label attributes with a computed style:

```swift
    private var sizeLabelAttrs: [NSAttributedString.Key: Any] {
        let color = selectionSizeSnapActive
            ? NSColor.controlAccentColor
            : ToolbarLayout.iconColor
        return [
            .font: Self.sizeLabelFont,
            .foregroundColor: color
        ]
    }
```

- [ ] **Step 2: Add a dedicated draw helper for selection-size snap guide lines**

Add this helper near the existing `drawSnapGuides()` code:

```swift
    private func drawSelectionSizeSnapGuides() {
        guard selectionSizeSnapActive else { return }

        let guideColor = NSColor.controlAccentColor.withAlphaComponent(0.75)
        guideColor.setStroke()

        if let gx = selectionSizeSnapGuideX {
            let line = NSBezierPath()
            line.move(to: NSPoint(x: gx, y: selectionRect.minY))
            line.line(to: NSPoint(x: gx, y: selectionRect.maxY))
            line.lineWidth = 1
            let pattern: [CGFloat] = [6, 4]
            line.setLineDash(pattern, count: pattern.count, phase: 0)
            line.stroke()
        }

        if let gy = selectionSizeSnapGuideY {
            let line = NSBezierPath()
            line.move(to: NSPoint(x: selectionRect.minX, y: gy))
            line.line(to: NSPoint(x: selectionRect.maxX, y: gy))
            line.lineWidth = 1
            let pattern: [CGFloat] = [6, 4]
            line.setLineDash(pattern, count: pattern.count, phase: 0)
            line.stroke()
        }
    }
```

- [ ] **Step 3: Call the new guide-line helper in the same draw phases that render selection overlays**

Add calls in the same regions that currently call `drawSnapGuides()`:

```swift
                if selectionSizeSnapActive {
                    drawSelectionSizeSnapGuides()
                }
                if snapGuideX != nil || snapGuideY != nil {
                    drawSnapGuides()
                }
```

- [ ] **Step 4: Clear snap state when selection interactions end or reset**

In the mouse-up / reset paths that already clear selection drag state, add:

```swift
        clearSelectionSizeSnapState()
```

Add that call in these exact places:

- `mouseUp(with:)` inside `case .selecting`, after the new selection has been finalized and delegate callbacks have been queued
- `mouseUp(with:)` inside `case .selected` when `isResizingSelection` changes back to `false`
- `clearSelection()`
- `reset()`

- [ ] **Step 5: Re-run the verification script**

Run:

```bash
swift macshot/Services/AspectRatioSizeSnap.swift scripts/verify_aspect_ratio_size_snap.swift
```

Expected:

```text
OK: aspect ratio size snap verification passed
```

- [ ] **Step 6: Commit**

```bash
git add macshot/UI/Overlay/OverlayView.swift
git commit -m "feat: render locked ratio size snap feedback"
```

---

### Task 5: Final Verification and Spec Sync

**Files:**
- Test: `scripts/verify_aspect_ratio_size_snap.swift`
- Reference: `docs/superpowers/specs/2026-04-13-aspect-ratio-size-snap-design.md`

- [ ] **Step 1: Run the standalone verification script**

Run:

```bash
swift macshot/Services/AspectRatioSizeSnap.swift scripts/verify_aspect_ratio_size_snap.swift
```

Expected:

```text
OK: aspect ratio size snap verification passed
```

- [ ] **Step 2: Build the app**

Run:

```bash
xcodebuild -project macshot.xcodeproj -scheme macshot -configuration Debug build
```

Expected:

```text
** BUILD SUCCEEDED **
```

- [ ] **Step 3: Manually verify the approved interaction cases**

Run through this checklist in the built app:

```text
1. Lock 1:1 and drag a small region near 150, 200, 250 to confirm 50-step snap.
2. Lock 16:9 and drag a larger region near 700/800 to confirm 100-step snap.
3. Resize a locked selection from corner handles and side handles.
4. Confirm temporary guide lines appear only while snapped.
5. Confirm the size label changes appearance only while snapped.
6. Turn aspect ratio lock off and confirm no size snap occurs.
```

Expected:

```text
All six checks pass with no regressions in freeform selection.
```

- [ ] **Step 4: Confirm the shipped behavior still matches the approved spec**

Before the final commit, compare the implementation against `docs/superpowers/specs/2026-04-13-aspect-ratio-size-snap-design.md` and confirm all of these are still true:

```text
1. The feature only runs when aspect ratio lock is active.
2. Initial selection drag and later resize both participate.
3. Short edge below 400 snaps in 50-point increments.
4. Short edge at or above 400 snaps in 100-point increments.
5. The snap threshold remains 10 points.
6. Temporary guide lines and size-label emphasis appear only while snapping.
```

If any of the six checks would fail, stop the code change there and revise the spec in a separate documentation change before shipping the feature.

- [ ] **Step 5: Commit**

```bash
git add macshot/Services/AspectRatioSizeSnap.swift \
        scripts/verify_aspect_ratio_size_snap.swift \
        macshot/UI/Overlay/OverlayView.swift
git commit -m "feat: add locked aspect ratio size snapping"
```
