import AppKit

extension OverlayView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        if isSharingActive {
            return nil
        }
        if isEditorMode, let parent = chromeParentView {
            let localInParent = parent.convert(point, from: superview)
            if let topBar = findTopBar(), topBar.frame.contains(localInParent) {
                return nil
            }
            if let strip = bottomStripView, !strip.isHidden,
               strip.frame.contains(localInParent) {
                return nil
            }
            if let strip = rightStripView, !strip.isHidden,
               strip.frame.contains(localInParent) {
                return nil
            }
            if let row = toolOptionsRowView, !row.isHidden,
               row.frame.contains(localInParent) {
                return nil
            }
        } else {
            let localPoint = convert(point, from: superview)
            if let strip = bottomStripView, !strip.isHidden, strip.frame.contains(localPoint) {
                return strip.hitTest(localPoint)
            }
            if let strip = rightStripView, !strip.isHidden, strip.frame.contains(localPoint) {
                return strip.hitTest(localPoint)
            }
            if let row = toolOptionsRowView, !row.isHidden, row.frame.contains(localPoint) {
                return row.hitTest(localPoint)
            }
        }
        // 文本框内侧的边缘事件也必须交给画布，不能被 NSTextView 当作选字吞掉。
        if liveTextChromeContains(convert(point, from: superview)) { return self }
        return super.hitTest(point)
    }
}
