# 提交标题（50字符以内）
Refactor: Extract coordinators and split OverlayView into focused modules

# 提交正文

## 概述
大范围重构：将 AppDelegate 拆分为多个专职 Coordinator，将 OverlayView (8500+ 行) 拆分为 40+ 个单一职责的扩展文件，修复多项 bug 和性能问题。

## 架构改进

### Coordinator 模式引入
- **FocusCoordinator**: 管理应用焦点状态和 previousApp 跟踪
- **CaptureFlowCoordinator**: 处理截图流程（延迟倒计时、屏幕选择、覆盖层显示）
- **RecordingFlowCoordinator**: 管理屏幕录制流程和 UI 状态
- **ScreenshotOutputCoordinator**: 处理截图后操作（缩略图、Pin、上传、保存）
- **ScrollCaptureFlowCoordinator**: 管理滚动捕获会话
- **OverlaySessionCoordinator**: 协调多屏幕选择同步
- **StatusBarController**: 管理菜单栏图标和菜单
- **AppLaunchCoordinator**: 处理应用启动和热键注册
- **AppRouteHandler**: 处理外部 URL 和文件打开
- **HistoryMenuController**: 管理历史记录菜单

### OverlayView 模块化
将 `OverlayView.swift` (8544 行) 拆分为：
- **状态管理**: `+InteractionState.swift`, `+ToolState.swift`, `+AppearanceState.swift`, `+PreviewState.swift`, `+RenderState.swift`, `+CaptureSessionState.swift`
- **交互处理**: `+MouseDown.swift`, `+MouseDragged.swift`, `+MouseCompletion.swift`, `+Keyboard.swift`
- **选择系统**: `+SelectionDrag.swift`, `+SelectionResize.swift`, `+SelectionFeedback.swift`, `+SelectionMemory.swift`, `+SelectionAccessors.swift`
- **标注系统**: `+AnnotationControls.swift`, `+AnnotationInteraction.swift`, `+AnnotationProperties.swift`, `+AnnotationOutlineGlow.swift`
- **工具栏**: `+ToolbarLayout.swift`, `+ToolbarState.swift`, `+ToolbarActions.swift`, `+ToolOptions.swift`
- **渲染**: `+DrawPipeline.swift`, `+RenderCache.swift`, `+OutputRendering.swift`, `+BeautifyDrawing.swift`
- **预览**: `+CursorPreview.swift`, `+LoupePreview.swift`, `+Cursor.swift`
- **辅助功能**: `+SnapGuides.swift`, `+AutoMeasure.swift`, `+AspectRatio.swift`, `+ColorSampler.swift`, `+Clipboard.swift`, `+Hint.swift`
- **生命周期**: `+Lifecycle.swift`, `+ViewRouting.swift`, `+Types.swift`, `+CanvasProtocols.swift`
- **特定模式**: `+ScrollCaptureMode.swift`, `+ImageTransforms.swift`

## Bug 修复

### 1. FocusCoordinator 竞态条件
- **问题**: `returnFocusIfNeeded` 使用 `DispatchQueue.main.async` 但读取旧的状态值
- **修复**: 改为闭包参数，确保每次调用都获取最新状态

### 2. HistoryMenuController 菜单验证
- **问题**: `menuNeedsUpdate` 没有验证菜单来源
- **修复**: 添加 `managedMenu` 弱引用和恒等检查

### 3. OverlayView 观察者泄漏
- **问题**: `removeObserver(self)` 移除所有观察者，影响其他代码
- **修复**: 只移除特定观察者引用

### 4. RecordingFlowCoordinator Timer 清理
- **问题**: countdown esc monitor 在某些错误路径上泄漏
- **修复**: 统一清理逻辑到 `resetRecordingCountdownState()`

## 性能优化

### 屏幕变化缓存失效
- 监听 `NSWindow.didChangeScreenNotification` 和 `NSWindow.didChangeBackingPropertiesNotification`
- 窗口移动到不同显示器或 Retina 缩放变化时自动清除渲染缓存
- 防止缓存图像失真或拉伸

### 标记工具渲染
- 添加 `PerfMonitor` 用于性能测量
- 优化标记工具的缓存追加逻辑

## 代码质量改进

- 统一注释语言为英文
- 移除冗余代码（空代码块、重复逻辑）
- 改进类型安全（使用特定观察者引用而非 `self`）
- 添加性能日志（`[PERF]` 标记）

## Breaking Changes

无公开 API 变化。内部重构不影响现有功能。

## 测试建议

- [ ] 多屏幕截图和选择同步
- [ ] 窗口在不同显示器间移动
- [ ] 录制流程的开始/停止/暂停
- [ ] 滚动捕获会话
- [ ] 焦点返回（特别是录制进行中时）
- [ ] 菜单栏历史记录菜单
- [ ] 标注工具的滚动调整

## 相关 Issue

Closes #[issue-number]
