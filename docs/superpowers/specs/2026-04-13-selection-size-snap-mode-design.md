# Selection Size Snap Mode Design

Date: 2026-04-13
Project: macshot
Status: Approved pending written spec review

## Summary

目前 macshot 已经支持“锁定比例时的尺寸吸附”，并且吸附反馈已经稳定。下一步是在不破坏现有手感的前提下，把这项能力扩展成一个可配置的三档模式：

- `关闭`
- `仅比例锁定`
- `所有选区`

默认值保持为 `仅比例锁定`。这样可以保留当前最稳的体验，同时给需要自由框选吸附的用户一个明确开关。

## Goals

- 让用户可以决定尺寸吸附是否参与自由框选
- 保持当前“比例锁定时吸附”的体验不被默认关闭
- 让设置项语义清楚，不需要用户猜测“开启后究竟影响哪些情况”
- 保持吸附反馈规则统一：命中哪一边，就只高亮哪一边、只显示那一条提示线

## Non-Goals

- 不新增第二套吸附阈值或步长设置
- 不为自由框选单独做另一组视觉样式
- 不把功能扩展到标注、文本框、裁剪框、跨屏远端选区
- 不修改现有比例锁定快捷键体系

## Why Three Modes

自由框选和比例锁定选区的使用心态不同：

- 比例锁定通常是在追求精确尺寸，吸附价值很高
- 自由框选很多时候是快速截一个区域，过强吸附可能打断手感

如果只做一个简单开关，用户要么全开，要么全关，中间没有缓冲地带。三档模式能覆盖三类真实需求：

- 完全不要吸附的人
- 只想在精确场景里吸附的人
- 希望所有选区都能吸附的人

## User-Facing Behavior

### Mode 1: Disabled

- 关闭所有主选区尺寸吸附
- 比例锁定仍然负责约束比例，但不再吸到 `50 / 100 / 整百`
- 尺寸数字不高亮
- 不显示尺寸吸附提示线

### Mode 2: Locked Aspect Ratio Only

- 这是默认值
- 只有在比例锁定激活时，尺寸吸附才生效
- 适用场景：
  - 初次框选时的比例锁定拖拽
  - 已有选区的比例锁定缩放
- 自由框选保持现在的自然手感，不参与尺寸吸附

### Mode 3: All Selections

- 比例锁定选区继续使用现有尺寸吸附
- 自由框选也启用尺寸吸附
- 适用场景：
  - 初次自由框选
  - 已有自由选区的缩放
  - `Shift` 正方形约束也视为主选区尺寸变化的一部分，参与吸附
- 不适用于移动选区，只适用于改变选区尺寸

## Settings Placement

设置项放在现有 `Capture` 页签的 `Capture Options` 区域，和以下能力放在一起：

- 记住选区
- 对齐辅助线
- 鼠标指针截图

推荐文案：

- 标题：`Selection size snapping`
- 选项：
  - `Off`
  - `Locked aspect ratio only`
  - `All selections`

原因：

- 这是截图阶段的行为，不是外观设置
- 它和现有 `Show snap alignment guides` 在同一心智区域
- 用户能在一个区域里同时理解“是否吸附”和“是否显示辅助线”

## Interaction Rules

### Shared Rules

无论是哪一档，只要尺寸吸附生效，以下规则都保持一致：

- 短边小于 `400px` 时按 `50px` 吸附
- 短边大于等于 `400px` 时按 `100px` 吸附
- 阈值保持 `10px`
- 命中哪一边，就只高亮哪一个尺寸数字
- 命中哪一边，就只显示那一条临时提示线
- 只有宽和高同时都是有效吸附值时，才两边都高亮、两条线都显示

### Freeform Initial Selection

仅在 `All Selections` 模式下启用。

行为规则：

- 宽和高分别独立判断是否接近有效吸附目标
- 允许只吸宽、不吸高
- 允许只吸高、不吸宽
- 允许宽高同时吸附
- 保留现有拖拽方向逻辑，选区仍然从原始起点向当前方向生长

### Freeform Resize

仅在 `All Selections` 模式下启用。

行为规则：

- 拖动左右边手柄时，只判断宽度吸附
- 拖动上下边手柄时，只判断高度吸附
- 拖动四角手柄时，宽和高独立判断
- 固定边和固定角仍然保持稳定，不能因为吸附出现“跳锚点”

### Locked Aspect Ratio Selection

在 `Locked Aspect Ratio Only` 和 `All Selections` 两档都启用。

行为保持当前版本：

- 吸附由当前主驱动维度触发
- 另一边只通过比例推导，不自动算作命中
- 只有推导后的另一边本身也正好落在有效吸附值上，才允许双高亮

## Data Model

新增一个持久化模式值，例如：

- key: `selectionSizeSnapMode`
- value:
  - `0` = disabled
  - `1` = lockedAspectRatioOnly
  - `2` = allSelections

默认值为 `1`

推荐原因：

- 和现有 `@AppStorage` 用法一致
- Int 枚举容易和 `Picker` 绑定
- 未来如果要增加第四档，不需要迁移布尔值结构

## Rendering and Feedback

当前已经存在这些能力：

- 宽高分离高亮
- 宽高分离提示线
- 吸附结束后自动清状态

本次不改变视觉语言，只改变“何时允许进入这套反馈”。

换句话说：

- `Off`：反馈完全不触发
- `Locked aspect ratio only`：仅比例锁定路径触发
- `All selections`：比例锁定和自由框选路径都触发

## Implementation Outline

### Settings Layer

- 在 `CaptureSettingsView` 增加新的三档 `Picker`
- 使用 `@AppStorage("selectionSizeSnapMode")`
- 保留 `snapGuidesEnabled` 原有开关，不与模式值合并

### Overlay Decision Layer

在 `OverlayView` 增加一个轻量判断入口，例如：

- 当前模式是否允许比例锁定吸附
- 当前模式是否允许自由框选吸附

这样可以在以下路径里统一判断：

- 初次框选
- 选区缩放

### Geometry Layer

现有比例锁定吸附 helper 继续复用。

新增自由框选时，吸附计算可以沿用相同的步长与阈值规则，但要改为：

- 宽高独立吸附
- 不涉及比例回推

这样可以避免把自由框选和比例锁定写成两套完全不同的系统。

## Edge Cases

### Existing Selections Created Under Another Mode

- 用户切换模式后，不需要重建已有选区
- 从切换后的下一次拖拽开始，按新模式判断

### Shift Square Constraint

- 在 `All Selections` 模式下，`Shift` 正方形也参与尺寸吸附
- 仍然保持正方形约束，不允许吸附后破坏 `1:1`

### Alignment Guides Switch

- 如果 `Show snap alignment guides` 关闭，尺寸吸附仍可继续工作
- 只是临时提示线不画出来
- 尺寸数字高亮仍然保留

原因：

- “是否吸附” 和 “是否显示辅助线” 应该是两件事
- 用户可能想要吸附，但不想看到线

## Testing Plan

### Manual Verification

1. 模式设为 `Off`，确认比例锁定和自由框选都不吸附。
2. 模式设为 `Locked aspect ratio only`，确认只有比例锁定场景吸附。
3. 模式设为 `All selections`，确认自由框选和比例锁定都吸附。
4. 在 `All selections` 下拖四角，确认宽高可以独立吸附。
5. 造出 `800 / 1333` 这类场景，确认只亮宽度、只出竖线。
6. 关闭 `Show snap alignment guides`，确认仍然吸附，但不显示提示线。
7. 用 `Shift` 创建正方形，确认在 `All selections` 模式下也能吸附且保持 `1:1`。

### Regression Checks

- 当前比例锁定吸附手感不变
- 当前提示线和数字高亮规则不回退
- 移动选区时不触发尺寸吸附
- 标注和裁剪相关逻辑不受影响

## Recommendation

按三档模式实现：

- 默认 `Locked aspect ratio only`
- 让高级用户可切到 `All selections`
- 让不喜欢吸附的人可切到 `Off`

这是最小风险、也最符合真实使用差异的方案。
