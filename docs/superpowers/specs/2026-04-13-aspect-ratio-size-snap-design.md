# Aspect Ratio Size Snap Design

Date: 2026-04-13
Project: macshot
Status: Approved for spec review

## Summary

When aspect ratio lock is enabled during area selection, resizing is currently precise but easy to overshoot. The goal is to add a light-weight size snap behavior that makes locked-ratio selection feel more deliberate, especially when aiming for clean round sizes such as `300 x 200` or `800 x 450`.

This feature will only apply while aspect ratio lock is active. It will affect both:

- Initial selection drag while creating a new capture region
- Later resize drag when adjusting an existing locked-ratio selection

The interaction will use adaptive snap steps:

- Smaller selections snap to multiples of `50`
- Larger selections snap to multiples of `100`

The feedback will stay light but explicit: the size label will visually emphasize the snapped state, and temporary snap guide lines will appear while a snap target is engaged.

## Goals

- Reduce overshooting when dragging a locked-ratio selection
- Preserve the current fast screenshot workflow
- Keep the behavior predictable across both initial selection and later resize
- Avoid turning the selection experience into a full design-tool UI

## Non-Goals

- No snapping when aspect ratio lock is off
- No snapping for annotation resize, text boxes, or other editor objects
- No persistent ruler system or full design-tool overlay
- No new settings toggle in this iteration

## User Experience

### Trigger Conditions

Snap behavior is active only when all of the following are true:

- The user is selecting or resizing the screenshot region
- Aspect ratio lock is active
- The selection is being changed by drag interaction

Snap behavior is inactive when:

- Aspect ratio lock is off
- The user is moving the selection instead of resizing it
- The interaction is unrelated to the main screenshot region

### Snap Model

The size snap uses the locked-ratio result as its source of truth. The system should:

1. Compute the selection size using the existing aspect-ratio logic
2. Determine which snap interval applies
3. If the computed size is close enough to a snap target, adjust it to the target
4. Recompute the paired dimension from the locked ratio

This ensures the snap is based on the final rectangle the user sees, not the raw pointer position.

### Adaptive Step Rule

The adaptive rule is based on the shorter edge of the computed selection:

- If the shorter edge is below `400`, snap using `50`
- If the shorter edge is `400` or above, snap using `100`

This keeps small regions controllable and larger regions tidy.

### Snap Threshold

Snap should not force hard stepping at all times. Instead, it should only engage when near a target value.

Required threshold:

- Use a threshold of `10 px`

Interpretation:

- If the snap-driving dimension is within `10 px` of a valid target, snap
- If the drag moves beyond that threshold, release the snap naturally

### Visual Feedback

Feedback should stay subtle:

- Reuse the existing size label
- When snap is active, render the size label in an emphasized style
- When snap is not active, keep the current default appearance
- When snap is active, show temporary guide lines that make the snapped width/height feel intentional

Guide line behavior:

- Only show while the drag is currently snapped
- Disappear immediately when the drag exits the snap threshold
- Use a light-weight visual style, closer to a temporary canvas aid than a persistent measurement tool
- Prefer one or two clean guide lines over a dense overlay
No extra flashing or sound in this version.

## Interaction Details

### Initial Selection

Current initial selection under aspect ratio lock lives in the `.selecting` path in `OverlayView.mouseDragged`.

New behavior:

- After width/height are derived from the locked ratio, run them through the snap engine
- Apply the snapped dimensions before the final `selectionRect` is committed
- Preserve the current origin logic so the region still grows from the original drag direction

### Resize Existing Selection

Current resize of an existing selection flows through:

- `resizeSelection(to:)`
- `resizedSelectionRect(from:handle:to:minSize:aspectRatio:)`

New behavior:

- Keep the existing handle-specific geometry logic
- After the aspect-ratio-constrained width/height are calculated, apply size snapping
- Rebuild the rect while preserving the handle’s anchor behavior

This is important: the fixed corner/edge must stay stable so the selection does not appear to jump incorrectly.

## Proposed Architecture

### New Helper

Add a focused helper inside `OverlayView` or a nearby private extension, responsible for snapping locked-ratio selection sizes.

Recommended shape:

- A small helper that receives:
  - computed width
  - computed height
  - active aspect ratio
  - minimum size
- It returns:
  - snapped width
  - snapped height
  - whether snapping is active

Example responsibility split:

- `snapStep(for width:height:)`
- `snappedSize(width:height:aspectRatio:minSize:)`

This keeps the selection math readable and avoids duplicating step/threshold rules.

### Snap-Driving Dimension

To keep behavior stable, use a single driving dimension:

- If width was the dimension used to derive height, snap width and recalculate height
- If height was the dimension used to derive width, snap height and recalculate width

For initial selection, the current logic already decides whether width or height dominates. The snap helper should accept that result rather than second-guessing it.

For handle-based resize, the same principle applies: preserve the current handle semantics and snap the dimension naturally controlled by that handle.

## State and Rendering

Add transient state for snapped feedback:

- A boolean such as `selectionSizeSnapActive`
- Optional temporary snap guide positions, such as:
  - snapped width guide x-position
  - snapped height guide y-position

This state should:

- Update during drag
- Reset when selection drag/resizing ends
- Reset when aspect ratio lock is cleared

The existing size label rendering should read this state and switch to the emphasized appearance when true.
The drawing layer should also read the transient guide positions and render the temporary snap lines only while snapping is active.

## Edge Cases

### Minimum Size

Snap must never produce a size smaller than the current minimum allowed selection.

### Tiny Locked Regions

If the selection is very small, snapping should not make the interaction feel sticky near the minimum size. The snap helper must clamp after computing the target and only snap if the final result remains valid.

### Guide Line Clarity

Temporary guide lines must not be confused with annotation alignment guides or window snap guides. They should:

- use a distinct visual style
- only appear during locked-ratio size snapping
- be scoped to the active selection interaction

### Cross-Screen Remote Selection

The current code also has remote selection resizing. This feature does not apply there in this version. The scope is limited to the local main selection only.

### Inverted Ratios

No special handling is needed beyond the existing `aspectRatioLock.ratio`. Once the ratio is active, snapping works the same way.

## Testing Plan

### Manual Verification

1. Lock to `1:1`, create a small selection, and confirm sizes near `50 / 100 / 150` snap cleanly.
2. Lock to `16:9` or `4:3`, create a medium and large selection, and confirm near-target sizes snap to clean round values.
3. Resize an existing locked selection from corners and edges, and confirm snapping works there too.
4. Drag beyond the threshold after snapping, and confirm the selection releases naturally.
5. Turn aspect ratio lock off, and confirm no snap behavior occurs.
6. Confirm the size label visibly indicates when snapping is active.
7. Confirm temporary guide lines appear only while snapped and disappear immediately when released.

### Regression Checks

- Freeform selection still behaves exactly as before
- Locked-ratio selection still respects drag direction and anchor points
- Existing aspect ratio shortcuts and hint UI remain unchanged
- Selection move behavior is unaffected

## Implementation Notes

- Prefer integrating the snap decision after existing aspect-ratio math rather than rewriting selection geometry
- Keep thresholds/constants localized and easy to tune
- Start with one threshold value instead of introducing preferences
- Scope this change to the capture region selection code only

## Recommendation

Implement the adaptive snapping with:

- `50` step below a `400` short-edge threshold
- `100` step at or above that threshold
- `10 px` snap threshold
- size-label emphasis plus temporary snap guide lines as the user-visible feedback

This is the best balance of usability, simplicity, and visual restraint for macshot.
