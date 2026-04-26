import AppKit

final class OverlayToolbarState {
    var bottomButtons: [ToolbarButton] = []
    var rightButtons: [ToolbarButton] = []
    var bottomBarRect: NSRect = .zero
    var rightBarRect: NSRect = .zero
    var showToolbars: Bool = false
    var topStripView: ToolbarStripView?
    var bottomStripView: ToolbarStripView?
    var rightStripView: ToolbarStripView?
    var toolOptionsRowView: ToolOptionsRowView?
    var widthLabelRect: NSRect = .zero
    var heightLabelRect: NSRect = .zero
    var sizeLabelRect: NSRect = .zero
    var hoveredTooltip: String?
    weak var hoveredTooltipButtonView: NSView?
    var editorTooltipView: NSView?
    var overlayErrorTimer: Timer?
    var pendingToolbarRebuild = false
}

extension OverlayView {
    var bottomButtons: [ToolbarButton] {
        get { toolbarState.bottomButtons }
        set { toolbarState.bottomButtons = newValue }
    }

    var rightButtons: [ToolbarButton] {
        get { toolbarState.rightButtons }
        set { toolbarState.rightButtons = newValue }
    }

    var bottomBarRect: NSRect {
        get { toolbarState.bottomBarRect }
        set { toolbarState.bottomBarRect = newValue }
    }

    var rightBarRect: NSRect {
        get { toolbarState.rightBarRect }
        set { toolbarState.rightBarRect = newValue }
    }

    var showToolbars: Bool {
        get { toolbarState.showToolbars }
        set {
            let oldValue = toolbarState.showToolbars
            toolbarState.showToolbars = newValue
            if newValue && !oldValue {
                scheduleDeferredToolbarRebuild()
            } else if !newValue && oldValue {
                bottomStripView?.isHidden = true
                rightStripView?.isHidden = true
                toolOptionsRowView?.isHidden = true
            }
        }
    }

    var topStripView: ToolbarStripView? {
        get { toolbarState.topStripView }
        set { toolbarState.topStripView = newValue }
    }

    var bottomStripView: ToolbarStripView? {
        get { toolbarState.bottomStripView }
        set { toolbarState.bottomStripView = newValue }
    }

    var rightStripView: ToolbarStripView? {
        get { toolbarState.rightStripView }
        set { toolbarState.rightStripView = newValue }
    }

    var toolOptionsRowView: ToolOptionsRowView? {
        get { toolbarState.toolOptionsRowView }
        set { toolbarState.toolOptionsRowView = newValue }
    }

    var sharedToolOptionsRowView: ToolOptionsRowView? { toolOptionsRowView }

    var widthLabelRect: NSRect {
        get { toolbarState.widthLabelRect }
        set { toolbarState.widthLabelRect = newValue }
    }

    var heightLabelRect: NSRect {
        get { toolbarState.heightLabelRect }
        set { toolbarState.heightLabelRect = newValue }
    }

    var sizeLabelRect: NSRect {
        get { toolbarState.sizeLabelRect }
        set { toolbarState.sizeLabelRect = newValue }
    }

    var sharedSizeLabelRect: NSRect { sizeLabelRect }

    var hoveredTooltip: String? {
        get { toolbarState.hoveredTooltip }
        set { toolbarState.hoveredTooltip = newValue }
    }

    var hoveredTooltipButtonView: NSView? {
        get { toolbarState.hoveredTooltipButtonView }
        set { toolbarState.hoveredTooltipButtonView = newValue }
    }

    var editorTooltipView: NSView? {
        get { toolbarState.editorTooltipView }
        set { toolbarState.editorTooltipView = newValue }
    }

    var overlayErrorTimer: Timer? {
        get { toolbarState.overlayErrorTimer }
        set { toolbarState.overlayErrorTimer = newValue }
    }

    var pendingToolbarRebuild: Bool {
        get { toolbarState.pendingToolbarRebuild }
        set { toolbarState.pendingToolbarRebuild = newValue }
    }
}
