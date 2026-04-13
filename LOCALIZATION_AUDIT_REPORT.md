# macshot 国际化检查报告

生成时间: 2026-04-13
最后更新: 2026-04-13 (已修复)

## 概述

项目支持 41 种语言，但各语言的本地化完整性存在较大差异。

### 键数量统计

| 语言 | 键数量 | 完整度 |
|------|--------|--------|
| 英文 (en) | 508 | 基准 ✅ |
| 简体中文 (zh-Hans) | 509 | 100% ✅ |
| 法语 (fr) | 431 | 85% |
| 其他语言 | 429 | 85% |

---

## ✅ 已修复的问题

### 1. 中文版本（已修复）

已添加 3 个缺失的键：

| 键 | 翻译 |
|---|------|
| `  (Tab to toggle)` | `  (Tab 切换)` |
| `Color Sampler` | `取色器` |
| `Window snap: ` | `窗口吸附：` |

### 2. 英文版本（已修复）

已添加 21 个缺失的键：

| 键 | 状态 |
|---|------|
| `Annotation` | ✅ |
| `Application` | ✅ |
| `Auto-Redact` | ✅ |
| `Background color` | ✅ |
| `Click window` | ✅ |
| `Download` | ✅ |
| `Drag to select` | ✅ |
| `Drawing` | ✅ |
| `Effects` | ✅ |
| `Fullscreen` | ✅ |
| `Global Keyboard Shortcuts` | ✅ |
| `Hidden tools are removed from the toolbar.` | ✅ |
| `In-App Shortcuts` | ✅ |
| `Invert` | ✅ |
| `Language packs` | ✅ |
| `Other` | ✅ |
| `Play sound on copy` | ✅ |
| `Ratio:` | ✅ |
| `Shapes` | ✅ |
| `Tab to toggle` | ✅ |
| `Window snap:` | ✅ |

---

## 仍需处理的问题

### 其他语言严重不完整（缺少约60-80个键）

所有非中英文语言都缺少约 60-80 个键，包括：

- 新增的设置选项键
- 录制相关功能键
- 上传配置相关键
- 工具分类键

**缺少的主要键：**
- `Aspect ratio lock cleared`
- `Aspect ratio locked: `
- `Capture Options`
- `Check Now`
- `Check for Updates Now`
- `Max height: 0 = unlimited`
- `Pin to screen`
- `SM.MS token`
- `Updates`
- `Upload provider`
- `imgbb Configuration`
- `Open screenshot editor`
- `Show quick access overlay`
- `Copy file to clipboard`
- `Upload and copy link`
- `S3 / R2 / MinIO`
- 等约 50+ 个键

**建议：** 优先更新主要语言（日语、韩语、德语、法语、西班牙语）

---

### 3. 其他语言严重不完整（缺少约60个键）

所有非中文语言都缺少约 60 个键，包括：

- 新增的设置选项键
- 录制相关功能键
- 上传配置相关键

**缺少的主要键：**
- `Aspect ratio lock cleared`
- `Aspect ratio locked: `
- `Capture Options`
- `Check Now`
- `Check for Updates Now`
- `Max height: 0 = unlimited`
- `Pin to screen`
- `SM.MS token`
- `Updates`
- `Upload provider`
- `imgbb Configuration`
- `Open screenshot editor`
- `Show quick access overlay`
- `Copy file to clipboard`
- `Upload and copy link`
- `S3 / R2 / MinIO`
- 等约 45+ 个键

---

## 建议

### 长期改进

1. **建立同步机制**
   - 考虑使用脚本自动检测缺失的键
   - 添加 CI 检查确保所有语言文件包含相同的键

2. **更新其他语言**
   - 优先更新主要语言（日语、韩语、德语、法语、西班牙语）
   - 使用翻译工具批量翻译缺失的键

3. **代码审查流程**
   - 添加新功能时，确保所有语言文件同步更新
   - 在 PR 检查清单中添加本地化完整性检查

---

## 修复日志

**2026-04-13**
- ✅ 修复中文版本：添加 3 个缺失的键
- ✅ 修复英文版本：添加 21 个缺失的键
- 📝 创建检查报告
