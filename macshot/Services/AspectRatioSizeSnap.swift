import Foundation
import CoreGraphics

enum SelectionSizeSnapMode: Int {
    case off = 0
    case lockedAspectRatioOnly = 1
    case allSelections = 2
}

enum AspectRatioSnapAxis {
    case width
    case height
}

struct AspectRatioSnapResult {
    let size: CGSize
    let isSnapped: Bool
    let snappedDimension: CGFloat?
}

struct FreeformSizeSnapResult {
    let size: CGSize
    let widthSnapped: Bool
    let heightSnapped: Bool

    var isSnapped: Bool {
        widthSnapped || heightSnapped
    }
}

func isAspectRatioSnapTarget(
    _ dimension: CGFloat,
    for size: CGSize,
    tolerance: CGFloat = 0.5
) -> Bool {
    let step = aspectRatioSnapStep(for: size)
    let target = (dimension / step).rounded() * step
    return abs(dimension - target) <= tolerance
}

func aspectRatioSnapStep(for size: CGSize) -> CGFloat {
    let shortEdge = min(size.width, size.height)
    return shortEdge < 400 ? 50 : 100
}

private func snapDimensionToStep(
    _ dimension: CGFloat,
    step: CGFloat,
    threshold: CGFloat,
    minSize: CGFloat
) -> (value: CGFloat, isSnapped: Bool) {
    let clamped = max(minSize, dimension)
    let target = (clamped / step).rounded() * step
    let shouldSnap = abs(clamped - target) <= threshold
    return (shouldSnap ? max(minSize, target) : clamped, shouldSnap)
}

func snapAspectRatioSize(
    drivingDimension: CGFloat,
    threshold: CGFloat,
    ratio: CGFloat,
    minSize: CGFloat,
    snapAxis: AspectRatioSnapAxis,
    currentSize: CGSize
) -> AspectRatioSnapResult {
    let step = aspectRatioSnapStep(for: currentSize)
    let snapped = snapDimensionToStep(
        drivingDimension,
        step: step,
        threshold: threshold,
        minSize: minSize
    )
    let finalDriving = snapped.value

    switch snapAxis {
    case .width:
        let width = finalDriving
        let height = max(minSize, width / ratio)
        return AspectRatioSnapResult(
            size: CGSize(width: width, height: height),
            isSnapped: snapped.isSnapped,
            snappedDimension: snapped.isSnapped ? width : nil
        )
    case .height:
        let height = finalDriving
        let width = max(minSize, height * ratio)
        return AspectRatioSnapResult(
            size: CGSize(width: width, height: height),
            isSnapped: snapped.isSnapped,
            snappedDimension: snapped.isSnapped ? height : nil
        )
    }
}

func snapFreeformSize(
    size: CGSize,
    threshold: CGFloat,
    minSize: CGFloat,
    snapWidth: Bool = true,
    snapHeight: Bool = true
) -> FreeformSizeSnapResult {
    let step = aspectRatioSnapStep(for: size)
    let snappedWidth = snapWidth
        ? snapDimensionToStep(
            size.width,
            step: step,
            threshold: threshold,
            minSize: minSize
        )
        : (value: max(minSize, size.width), isSnapped: false)
    let snappedHeight = snapHeight
        ? snapDimensionToStep(
            size.height,
            step: step,
            threshold: threshold,
            minSize: minSize
        )
        : (value: max(minSize, size.height), isSnapped: false)

    return FreeformSizeSnapResult(
        size: CGSize(width: snappedWidth.value, height: snappedHeight.value),
        widthSnapped: snappedWidth.isSnapped,
        heightSnapped: snappedHeight.isSnapped
    )
}
