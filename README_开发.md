# macshot 宽高比锁定功能 - 开发指南

## 🚀 快速构建

### 一键构建（推荐）

每次修改代码后，运行以下命令：

```bash
bash build.sh
```

这个脚本会自动：
1. ✅ 停止旧版本
2. ✅ 清理所有旧的应用文件
3. ✅ 构建新版本
4. ✅ 安装到 /Applications
5. ✅ 启动应用

### 手动构建

```bash
# 1. 停止旧版本
killall macshot-dev 2>/dev/null

# 2. 清理旧版本
rm -rf /Applications/macshot-dev.app
rm -rf /Users/fxj/n/macshot/macshot-dev.app

# 3. 构建
xcodebuild -scheme macshot -configuration Debug build

# 4. 安装
cp -R "/Users/fxj/Library/Developer/Xcode/DerivedData/macshot-daqnumwucnkubxhcwqiflmrfkyxk/Build/Products/Debug/macshot.app" "/Users/fxj/n/macshot/macshot-dev.app"
cp -R /Users/fxj/n/macshot/macshot-dev.app /Applications/

# 5. 启动
open /Applications/macshot-dev.app
```

## 🎯 测试功能

### 宽高比锁定功能

1. **触发截图**：按 `Cmd+Shift+X`
2. **查看提示**：屏幕中央显示两行提示
3. **锁定比例**：
   - 按 `1` → 1:1 正方形
   - 按 `3` → 3:4 竖屏（小红书）
   - 按 `6` → 6:9 竖屏
4. **框选验证**：拖拽鼠标，验证比例是否正确
5. **调整大小**：松开鼠标后，拖动句柄调整
6. **反转比例**：按 `R` 键反转
7. **取消锁定**：按 `0` 键或再次按同一数字键

### 关键验证点

- [ ] idle 状态是否显示宽高比锁定说明
- [ ] 按数字键是否显示锁定提示
- [ ] 框选时是否保持锁定比例
- [ ] 松开鼠标后，调整大小时是否仍保持比例
- [ ] 左上角是否固定，只向右下扩展
- [ ] 是否不再抖动
- [ ] 取消锁定时是否显示正确提示

## 🔧 代码结构

### 主要修改文件

- `macshot/UI/Overlay/OverlayView.swift`
  - 添加 `AspectRatioLock` 枚举
  - 添加宽高比锁定相关属性
  - 修改选择区域计算逻辑
  - 添加键盘事件处理
  - 修改调整大小逻辑
  - 添加 UI 提示绘制

### 关键方法

| 方法 | 功能 |
|------|------|
| `toggleAspectRatioLock()` | 切换比例锁定状态 |
| `showAspectRatioHint()` | 显示提示 |
| `resizeSelection()` | 调整选择区域大小（包含比例约束）|

## 📝 开发注意事项

### 坐标系

- **AppKit 坐标系**：原点在左下角，y轴向上
- **NSRect.origin**：矩形的左下角
- **固定左上角**：`origin.x` 固定，`origin.y + height` 固定

### 权限问题

- 开发阶段使用 **adhoc 签名**
- 每次重新编译会丢失权限（这是正常的）
- 正式发布时使用开发者证书签名就不会有这个问题

## 🗑️ 卸载

```bash
bash uninstall.sh
```

或手动卸载：

```bash
killall macshot-dev
rm -rf /Applications/macshot-dev.app
```

## 📧 问题反馈

如遇问题，请提供：
1. 重现步骤
2. 期望行为 vs 实际行为
3. 截图或录屏
4. 系统版本：`sw_vers`
