# 已移除的宽高内联输入代码 — 重新实现参考

> 这些代码从 OverlayView.swift 和 OverlayWindowController.swift 中移除。
> 功能：点击截图区域顶部的「宽×高」标签后，可内联编辑宽高值，支持比例锁定联动、防抖实时更新。
> 移除原因：field editor 焦点无法正确建立，输入框不能正常接收键盘事件。

---

## 1. 属性声明（OverlayView.swift，原约 407-410 行）

```swift
// Size labels (split into width and height for independent editing)
private var widthInputField: NSTextField?
private var heightInputField: NSTextField?
private var sizeInputField: NSTextField?  // Kept for backward compatibility
```

`isEditingInlineField` 需要包含这些字段：
```swift
private var isEditingInlineField: Bool {
    widthInputField != nil || heightInputField != nil
        || zoomInputField != nil || sizeInputField != nil
}
```

---

## 2. drawSizeLabel() 中的编辑态跳过绘制（原约 2359-2370 行）

```swift
let editingSize = widthInputField != nil || heightInputField != nil
if !editingSize {
    (widthText as NSString).draw(
        at: NSPoint(x: widthRect.minX + padding, y: widthRect.minY + padding / 2), withAttributes: attrs)
    (heightText as NSString).draw(
        at: NSPoint(x: heightRect.minX + padding, y: heightRect.minY + padding / 2), withAttributes: attrs)
}

sizeLabelRect = NSRect(x: baseX, y: baseY, width: totalW, height: labelH)

if let w = widthInputField { w.frame = widthRect }
if let h = heightInputField { h.frame = heightRect }
```

---

## 3. showSizeInput / showBothSizeInputs / showWidthInput / showHeightInput

```swift
private func showSizeInput() {
    guard widthInputField == nil && heightInputField == nil else { return }
    showBothSizeInputs()
}

private func showBothSizeInputs() {
    let scale = window?.backingScaleFactor ?? 2.0
    let pixelW = Int(selectionRect.width * scale)
    let pixelH = Int(selectionRect.height * scale)

    let widthFrame = widthLabelRect
    let heightFrame = heightLabelRect

    let widthField = NSTextField(frame: widthFrame)
    widthField.cell = OverlayInlineNumericTextFieldCell(textCell: "")
    widthField.stringValue = "\(pixelW)"
    widthField.font = Self.sizeLabelFont
    widthField.alignment = .center
    widthField.isBezeled = false
    (widthField.cell as? NSTextFieldCell)?.drawsBackground = false
    widthField.wantsLayer = true
    widthField.layer?.backgroundColor = NSColor.clear.cgColor
    widthField.layer?.cornerRadius = 4
    widthField.layer?.borderWidth = 0
    widthField.layer?.borderColor = nil
    widthField.textColor = .white
    widthField.focusRingType = .none
    widthField.delegate = self
    widthField.tag = 901  // Width field tag

    let heightField = NSTextField(frame: heightFrame)
    heightField.cell = OverlayInlineNumericTextFieldCell(textCell: "")
    heightField.stringValue = "\(pixelH)"
    heightField.font = Self.sizeLabelFont
    heightField.alignment = .center
    heightField.isBezeled = false
    (heightField.cell as? NSTextFieldCell)?.drawsBackground = false
    heightField.wantsLayer = true
    heightField.layer?.backgroundColor = NSColor.clear.cgColor
    heightField.layer?.cornerRadius = 4
    heightField.layer?.borderWidth = 0
    heightField.layer?.borderColor = nil
    heightField.textColor = .white
    heightField.focusRingType = .none
    heightField.delegate = self
    heightField.tag = 902  // Height field tag

    addSubview(widthField)
    addSubview(heightField)
    widthInputField = widthField
    heightInputField = heightField

    // ⚠️ 关键问题：makeFirstResponder 在 mouseDown 期间调用会被 AppKit 重置
    // 之前尝试用 DispatchQueue.main.async 延迟，但 field editor 仍无法正常接收键盘事件
    window?.makeFirstResponder(widthField)
    widthField.selectText(nil)
    applyInlineNumericFieldFocusChrome(focused: widthField)
    needsDisplay = true
}

private func showWidthInput() {
    showBothSizeInputs()
}

private func showHeightInput() {
    showBothSizeInputs()
}
```

---

## 4. commitSizeInputIfNeeded / applySizeInputs

```swift
private func commitSizeInputIfNeeded() {
    if let widthField = widthInputField, let heightField = heightInputField {
        applySizeInputs(widthField: widthField, heightField: heightField)
        widthField.removeFromSuperview()
        heightField.removeFromSuperview()
        widthInputField = nil
        heightInputField = nil
        window?.makeFirstResponder(self)
        needsDisplay = true
    }
    if let field = sizeInputField {
        field.removeFromSuperview()
        sizeInputField = nil
        needsDisplay = true
    }
}

private func applySizeInputs(widthField: NSTextField, heightField: NSTextField) {
    let scale = window?.backingScaleFactor ?? 2.0
    let widthInput = widthField.stringValue.trimmingCharacters(in: .whitespaces)
    let heightInput = heightField.stringValue.trimmingCharacters(in: .whitespaces)
    var newW = selectionRect.width
    var newH = selectionRect.height

    if let w = Int(widthInput), w > 0 {
        newW = CGFloat(w) / scale
        if aspectRatioLock != .none {
            let ratio = aspectRatioLock.ratio
            newH = newW / ratio
        }
    }
    if let h = Int(heightInput), h > 0 {
        if aspectRatioLock == .none {
            newH = CGFloat(h) / scale
        }
    }

    let centerX = selectionRect.midX
    let centerY = selectionRect.midY
    selectionRect = NSRect(x: centerX - newW / 2, y: centerY - newH / 2, width: newW, height: newH)
}
```

---

## 5. updateWidthFromInput / updateHeightFromInput（实时联动更新）

```swift
// Real-time update when editing width
private func updateWidthFromInput(_ field: NSTextField) {
    let input = field.stringValue.trimmingCharacters(in: .whitespaces)
    guard let value = Int(input), value > 0 else { return }

    let scale = window?.backingScaleFactor ?? 2.0
    let newW = CGFloat(value) / scale
    var newH = selectionRect.height

    if aspectRatioLock != .none {
        let ratio = aspectRatioLock.ratio
        newH = newW / ratio
    }

    let centerX = selectionRect.midX
    let centerY = selectionRect.midY
    selectionRect = NSRect(x: centerX - newW / 2, y: centerY - newH / 2, width: newW, height: newH)

    if let heightField = heightInputField {
        let pixelH = Int(newH * scale)
        heightField.stringValue = "\(pixelH)"
    }
    needsDisplay = true
}

// Real-time update when editing height
private func updateHeightFromInput(_ field: NSTextField) {
    let input = field.stringValue.trimmingCharacters(in: .whitespaces)
    guard let value = Int(input), value > 0 else { return }

    let scale = window?.backingScaleFactor ?? 2.0
    let newH = CGFloat(value) / scale
    var newW = selectionRect.width

    if aspectRatioLock != .none {
        let ratio = aspectRatioLock.ratio
        newW = newH * ratio
    }

    let centerX = selectionRect.midX
    let centerY = selectionRect.midY
    selectionRect = NSRect(x: centerX - newW / 2, y: centerY - newH / 2, width: newW, height: newH)

    if let widthField = widthInputField {
        let pixelW = Int(newW * scale)
        widthField.stringValue = "\(pixelW)"
    }
    needsDisplay = true
}
```

---

## 6. mouseDown 中点击宽高标签 → 弹出输入框

```swift
// 在 case .selected: 分支内，zoom label click 之前
if widthLabelRect.contains(point) && widthInputField == nil && heightInputField == nil {
    showWidthInput()
    return
}
if heightLabelRect.contains(point) && widthInputField == nil && heightInputField == nil {
    showHeightInput()
    return
}
if let field = sizeInputField, field.frame.contains(point) {
    return  // let the text field handle it
}
if let field = widthInputField, field.frame.contains(point) {
    return  // let the text field handle it
}
if let field = heightInputField, field.frame.contains(point) {
    return  // let the text field handle it
}
```

mouseDown 顶部需要保护这些字段不被提前 commit：
```swift
let clickedInsideInlineField: Bool = {
    let inlineFields = [widthInputField, heightInputField, zoomInputField, sizeInputField]
    return inlineFields.compactMap { $0 }.contains { $0.frame.contains(point) }
}()
if !clickedInsideInlineField {
    commitSizeInputIfNeeded()
    commitZoomInputIfNeeded()
}
```

---

## 7. NSTextFieldDelegate — doCommandBy（tag 888/901/902）

```swift
if control.tag == 888 {
    if commandSelector == #selector(NSResponder.insertNewline(_:)) {
        commitSizeInputIfNeeded()
        return true
    }
    if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
        sizeInputField?.removeFromSuperview()
        sizeInputField = nil
        window?.makeFirstResponder(self)
        needsDisplay = true
        return true
    }
}
if control.tag == 901 || control.tag == 902 {
    if commandSelector == #selector(NSResponder.insertNewline(_:)) {
        commitSizeInputIfNeeded()
        return true
    }
    if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
        widthInputField?.removeFromSuperview()
        heightInputField?.removeFromSuperview()
        widthInputField = nil
        heightInputField = nil
        window?.makeFirstResponder(self)
        needsDisplay = true
        return true
    }
    // Tab key: switch between width and height fields
    if commandSelector == #selector(NSResponder.insertTab(_:)) {
        if control.tag == 901, let heightField = heightInputField {
            window?.makeFirstResponder(heightField)
            heightField.selectText(nil)
            return true
        } else if control.tag == 902, let widthField = widthInputField {
            window?.makeFirstResponder(widthField)
            widthField.selectText(nil)
            return true
        }
    }
}
```

---

## 8. controlTextDidChange（实时联动触发）

```swift
func controlTextDidChange(_ obj: Notification) {
    guard let control = obj.object as? NSTextField else { return }
    if control.tag == 901, let field = widthInputField {
        updateWidthFromInput(field)
    } else if control.tag == 902, let field = heightInputField {
        updateHeightFromInput(field)
    }
}
```

---

## 9. applyInlineNumericFieldFocusChrome（需要包含宽高字段）

```swift
private func applyInlineNumericFieldFocusChrome(focused: NSTextField?) {
    let tagged: [NSTextField?] = [
        widthInputField, heightInputField, zoomInputField, sizeInputField,
    ]
    for field in tagged.compactMap({ $0 }) {
        guard [888, 889, 901, 902].contains(field.tag) else { continue }
        if focused === field {
            field.layer?.borderColor = NSColor.white.cgColor
            field.layer?.borderWidth = 2
        } else {
            field.layer?.borderWidth = 0
            field.layer?.borderColor = nil
        }
    }
}
```

---

## 10. OverlayWindowController.swift — fieldEditor tag 集合

```swift
// OverlayWindow 类中
private static let overlayInlineNumericFieldTags: Set<Int> = [888, 889, 901, 902]
```

---

## ⚠️ 重新实现时需要解决的核心问题

1. **field editor 焦点问题**：在 `mouseDown` 中调用 `window?.makeFirstResponder(textField)` 会被 AppKit 内部事件处理重置。尝试过 `DispatchQueue.main.async` 延迟但仍不可靠。
2. **键盘事件路由**：即使 field editor 没有成为 first responder，`keyDown` 仍被 OverlayView 接收。需要在 `keyDown` 顶部拦截并转发给 field editor。
3. **快捷键冲突**：数字键 1-6 被宽高比锁定拦截，Return 被 quickSave 拦截，Backspace 被删除标注拦截。所有这些分支都需要排除 inline field 编辑状态。
4. **mouseDown 提前 commit**：`mouseDown` 顶部的 `commitSizeInputIfNeeded()` 会在用户点击输入框时销毁字段。

**建议方案**：考虑使用独立的 NSPanel/popover 代替内联 NSTextField，避免 OverlayView 的复杂事件处理链。
