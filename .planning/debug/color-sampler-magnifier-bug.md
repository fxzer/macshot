---
status: awaiting_human_verify
trigger: "当用户在第一次截图时使用了取色工具，第二次截图进入标注态时，取色工具保持激活状态，但放大镜没有显示出来"
created: 2026-04-11T00:00:00Z
updated: 2026-04-11T00:00:00Z
---

## Current Focus

hypothesis: ROOT CAUSE CONFIRMED - 当从 selecting 态转换到 selected 态时，放大镜被无条件隐藏（6处），但没有检查 currentTool 是否为 .colorSampler。由于 currentTool 会被持久化，第二次截图时工具仍然是 .colorSampler，但放大镜不会显示。
test: 已验证 - 代码中有 6 处 state = .selected 后调用 hideColorSamplerMagnifier()，但都没有检查 currentTool
expecting: 应该在 hideColorSamplerMagnifier() 后添加检查：如果 currentTool == .colorSampler，则调用 showColorSamplerMagnifier()
next_action: 实现修复 - 在所有 state 转换到 .selected 的地方添加条件检查

## Symptoms

expected: 第二次截图进入标注态（selected）时，如果取色工具处于激活状态，放大镜应该显示
actual: 第二次截图进入标注态时，取色工具保持激活状态，但放大镜没有显示
errors: 无错误信息
reproduction:
1. 第一次截图，选择取色工具（放大镜显示）
2. 完成标注或取消
3. 第二次截图，进入标注态
4. 观察放大镜是否显示
started: 新发现的 bug

## Eliminated

## Evidence

- timestamp: 2026-04-11T00:00:00Z
  checked: state 转换逻辑（.selecting -> .selected）
  found: 在所有 state = .selected 的赋值处，都调用了 hideColorSamplerMagnifier()
  implication: 进入 selected 态时会隐藏放大镜

- timestamp: 2026-04-11T00:00:00Z
  checked: 放大镜显示的触发条件
  found:
    - line 101: screenshotImage didSet 中，如果 state == .idle 且 screenshotImage != nil，显示放大镜
    - line 5076: 进入 selecting 态时显示放大镜
    - line 6743: currentTool == .colorSampler 且 state == .selected 时显示放大镜
  implication: 放大镜显示有三个触发点，但 state 转换到 .selected 时没有检查 currentTool

- timestamp: 2026-04-11T00:00:00Z
  checked: currentTool 的持久化
  found: currentTool 通过 OverlayView.lastUsedTool 持久化（static var），在应用会话中共享
  implication: 第二次截图时，currentTool 会恢复为上次的工具（.colorSampler）

- timestamp: 2026-04-11T00:00:00Z
  checked: 从 selecting 到 selected 的转换流程
  found:
    - line 5703, 5727, 5738: mouseUp 中 state = .selected，然后 hideColorSamplerMagnifier()
    - 没有在转换后检查 currentTool == .colorSampler 并重新显示放大镜的逻辑
  implication: 这是 bug 的根本原因

## Resolution

root_cause: 当 state 从 .selecting 转换到 .selected 时，代码在 6 个位置都无条件调用 hideColorSamplerMagnifier()：
1. line 5706: 鼠标拖拽选择区域后
2. line 5730: 窗口吸附后
3. line 5741: 全屏点击后
4. line 5667: F 键全屏捕获
5. line 5282: applySelection() 被调用时
6. line 5295: applyFullScreenSelection() 被调用时

但没有任何代码在这些转换后检查 currentTool == .colorSampler 并重新显示放大镜。

由于 currentTool 通过 OverlayView.lastUsedTool 持久化（static var），在应用会话中共享。第二次截图时：
1. currentTool 恢复为 .colorSampler
2. state 从 .idle -> .selecting -> .selected
3. 在 .selecting -> .selected 转换时，放大镜被隐藏
4. 没有代码重新显示放大镜

只有当用户主动切换工具时（line 6743: handleToolbarAction 中的检查），才会显示放大镜。

fix: 在所有 state 转换到 .selected 后调用 hideColorSamplerMagnifier() 的地方（共6处），添加条件检查：
```swift
// Hide color sampler magnifier when entering selected state
hideColorSamplerMagnifier()
// Re-show magnifier if color sampler is the active tool
if currentTool == .colorSampler {
    showColorSamplerMagnifier()
}
```

修改的6个位置：
1. line 5706: 鼠标拖拽选择区域后
2. line 5730: 窗口吸附后
3. line 5741: 全屏点击后
4. line 5667: F 键全屏捕获
5. line 5282: applySelection() 被调用时
6. line 5295: applyFullScreenSelection() 被调用时

verification: 需要测试以下场景：
1. 第一次截图，选择取色工具，完成选择 -> 放大镜应显示
2. 第二次截图，完成选择 -> 放大镜应自动显示
3. 取色工具激活时，切换到其他工具 -> 放大镜应隐藏
4. 从其他工具切换回取色工具 -> 放大镜应显示

files_changed: ["macshot/UI/Overlay/OverlayView.swift"]
