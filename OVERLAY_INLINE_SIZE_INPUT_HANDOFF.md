# 截图区「宽×高」内联输入 — 交互问题交接文档

本文档供后续实现者修复 **焦点 / 光标 / 快捷键** 问题；**样式**（透明 field editor、圆角 pill、`OverlayInlineNumericTextFieldCell` 等）用户侧已认为基本解决。

---

## 背景（已做过的 UI 改动）

为解决「宽×高」编辑态白底、抖动、圆角等问题，当前实现大致是：

- **`macshot/UI/Overlay/OverlayWindowController.swift`**：`OverlayWindow.fieldEditor(_:for:)` 对 tag `888` / `889` / `901` / `902` 的 field editor 使用 **透明背景**（`drawsBackground = false`），让底下 `draw(_:)` 画的圆角 pill 露出来。
- **`macshot/UI/Overlay/OverlayView.swift`**：`drawSizeLabel()` 在存在 `widthInputField` / `heightInputField` 时仍画 **圆角底 +「×」**，只跳过静态数字；`drawZoomLabel()` 在存在 `zoomInputField` 时仍画 zoom 的底、不画文字；`NSTextField` 的 layer 背景为透明。
- **`macshot/UI/Overlay/OverlayInlineNumericTextFieldCell.swift`**：自定义 cell，用于竖直居中等与静态绘制对齐。

---

## 现象（用户原话归纳）

1. 点击尺寸输入后 **无法正常输入**，鼠标仍是 **十字星**（像选区/画布工具光标）。
2. **按回车无法失焦**（无法结束编辑 / 无法按预期提交）。
3. **再按回车也没有触发「结束 selecting」** 等期望行为（与选区状态机有关，需和产品预期对齐）。

---

## 根因分析 1：十字星光标（几乎确定）

光标在 `OverlayView.updateCursorForPoint(_:)` 里 **命令式** 设置（约 1182–1324 行）。

- 在 `state == .selected` 时，若 `isPointOnChrome(point)` 为 true，会用 **箭头**（约 1213–1216 行）。
- `isPointOnChrome` 里对尺寸标签的逻辑（约 1377–1382 行）：

```swift
if (widthLabelRect.contains(point) || heightLabelRect.contains(point))
    && widthInputField == nil && heightInputField == nil { return true }
if zoomLabelRect.contains(point) && zoomLabelOpacity > 0 && zoomInputField == nil {
    return true
}
```

**一旦有内联输入框**（`widthInputField` / `heightInputField` 非 nil），上述条件为 **false**：鼠标仍在同一几何区域上，但 **不再算作 chrome**。后续会走到「选区内 closedHand」或 **工具默认光标**（约 1319–1322 行：`default: NSCursor.crosshair.set()`），于是出现 **十字星**。

**结论**：编辑态必须把「鼠标在 `widthInputField` / `heightInputField` / `zoomInputField` 的 frame 上」视为 chrome（箭头或 I-beam），或在 `updateCursorForPoint` 里 **优先** 分支处理这些子控件区域，**不要** 落到默认 `crosshair`。

---

## 根因分析 2：无法输入数字（高概率：按键被 OverlayView 吃掉）

若 **第一响应者不是** field editor / `NSTextField`，而是 **`OverlayView` 自己**，则 `keyDown` 会进 `OverlayView.keyDown(with:)`（约 7599 行起）。

其中有两段会 **拦截数字和回车**（与 `textEditView == nil` 有关，**没有** 排除 `widthInputField` / `heightInputField` / `zoomInputField`）：

### 1）回车 / Return（keyCode 36）（约 7681–7684 行）

```swift
case 36:  // Return/Enter — quick capture (respects quickCaptureMode setting)
    if textEditView == nil, state == .selected {
        overlayDelegate?.overlayViewDidRequestQuickSave()
    }
```

只要 `textEditView == nil` 且 `state == .selected`，**回车会走「快速保存」**，不会交给单行 `NSTextField` 的提交逻辑。

### 2）数字键 1–6（及 0、R）宽高比锁定（约 7718–7758 行）

在 `state == .idle || .selecting || .selected` 时，`charactersIgnoringModifiers` 为 `1`…`6` 等会 **`toggleAspectRatioLock` 并 `return`**，数字 **不会** 传到 `super.keyDown`，也就进不了内联输入框。

**结论**：所有「仅应在主画布有焦点」的快捷键分支，应增加与 **`textEditView` 对称** 的条件：例如当 `widthInputField != nil || heightInputField != nil || zoomInputField != nil`（或 `window?.firstResponder` 是这些控件的 field editor）时 **不要** 处理 aspect lock / quick save / 单键工具等；应交给 first responder 或显式转发。

---

## 根因分析 3：「回车不失焦」与「再按回车不关 selecting」

需区分两种失败模式：

### A. 第一响应者其实一直是 `OverlayView`

- 回车走上面 **case 36 → quickSave**，用户感知为「没失焦 / 没结束编辑」。
- 若此时 `state == .selecting`，case 36 的内层 `state == .selected` 不成立，可能落入 `default` → `super.keyDown`，行为又与用户预期不一致。

### B. 第一响应者确实是 field editor，但 `control(_:textView:doCommandBy:)` 未生效

- 委托在 `OverlayView` 的 `NSTextFieldDelegate` 扩展（约 8495–8556 行），`insertNewline` 会 `commitSizeInputIfNeeded()` / `commitZoomInputIfNeeded()`。
- 若 AppKit **没有** 把 `doCommandBy` 派给 delegate，需要查 **field editor 的 delegate**、是否应补充 `NSTextViewDelegate` 等。

**建议**：在 `showBothSizeInputs` / `makeFirstResponder` 之后用断点或日志确认：`window?.firstResponder` 是 `NSTextView`（field editor）还是 `OverlayView`；并对一次 **回车** 打日志看走的是 `control:doCommandBy:` 还是 `keyDown` case 36。

---

## 根因分析 4：`mouseDown` 开头的 commit（次要，需场景确认）

`mouseDown` 在 `switch state` 之前（约 5050–5054 行）会调用：

```swift
commitSizeInputIfNeeded()
commitZoomInputIfNeeded()
```

- `commitSizeInputIfNeeded()`：只要宽高两个 field 都在，就会 **提交并移除**（约 2454–2467 行）。
- `commitZoomInputIfNeeded()`：**只要** 存在 `zoomInputField` 就会解析并 **移除**（约 2608–2625 行），语义接近「无条件提交并关掉」。

**若某条路径上 `OverlayView` 先于子视图收到 `mouseDown`**（例如 hit-test、透明层、坐标），会在处理点击逻辑前就 **关掉编辑**。应确认：点击 pill 内区域时，`hitTest` 是否稳定返回 `NSTextField`（`hitTest` 约 1341–1359 行只特殊处理了 toolbar strip，其余 `super.hitTest`）。

---

## 相关文件清单（按优先级）

| 文件 | 关注点 |
|------|--------|
| `macshot/UI/Overlay/OverlayView.swift` | `updateCursorForPoint`、`isPointOnChrome`、`keyDown` case 36 与数字键分支、`mouseDown` 顶部 commit、`NSTextFieldDelegate` |
| `macshot/UI/Overlay/OverlayWindowController.swift` | `fieldEditor` 透明（一般不动，除非要改 IME/背景） |
| `macshot/UI/Overlay/OverlayInlineNumericTextFieldCell.swift` | 仅影响绘制/编辑 rect，一般不导致焦点问题 |

---

## 建议修复方向（实现 checklist）

1. **光标**：在 `isPointOnChrome` 或 `updateCursorForPoint` 开头，若点落在 `widthInputField` / `heightInputField` / `zoomInputField` 的 frame（注意 convert 到同一坐标系），返回 **arrow** 或对文本区用 **IBeam**；避免再落到 `default: crosshair`。
2. **键盘**：所有与 `textEditView == nil` 并列的快捷键，增加「内联尺寸/zoom 正在编辑」的排除条件；**case 36** 在正在编辑宽高/zoom 时 **不得** 调用 `overlayViewDidRequestQuickSave`，且不得吞掉应由 field 处理的事件。
3. **数字键**：宽高比 `1`–`6` 在「内联数字框为第一响应者」时必须 **禁用**。
4. **验证**：日志 `firstResponder` + `keyDown` / `control:doCommandBy:` 谁收到回车；多显示器下测 `mouseMoved`（约 960 行）是否仍把光标设成 crosshair。

---

## 用户表述 ↔ 代码原因对照

| 用户描述 | 最可能代码原因 |
|----------|----------------|
| 点击后没法输入、十字星 | `isPointOnChrome` 编辑态不把标签区当 chrome → `crosshair`；且/或 `keyDown` 吃掉数字键 |
| 回车不失焦 | `keyDown` case 36 在 `textEditView == nil` 时触发 quickSave，或 firstResponder 根本不是 field |
| 再按回车不关 selecting | `state` / Return 分支与 quickSave、aspect lock 混用；需明确 selecting 下 Enter 的产品行为并单独分支 |

---

*文档生成自对话交接说明；实现后若行为变更请同步更新本文档或删除过时段落。*
