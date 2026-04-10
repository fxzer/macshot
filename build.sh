#!/bin/bash

# macshot 宽高比锁定功能 - 一键构建脚本
# 自动清理旧版本 → 构建 → 安装 → 启动

set -e

echo "🚀 macshot 一键构建脚本"
echo "========================================"

# 1. 停止旧版本
echo "📍 步骤 1/4: 停止旧版本..."
killall macshot-dev 2>/dev/null || true
killall macshot 2>/dev/null || true
sleep 1
echo "   ✅ 已停止"

# 2. 清理旧版本
echo "📍 步骤 2/4: 清理旧版本..."
rm -rf /Applications/macshot-dev.app
rm -rf /Users/fxj/n/macshot/macshot-dev.app
rm -rf ~/Desktop/macshot-backup-* 2>/dev/null || true
echo "   ✅ 已清理"

# 3. 构建新版本
echo "📍 步骤 3/4: 构建新版本..."
xcodebuild -scheme macshot -configuration Debug clean build 2>&1 | grep -E "(BUILD SUCCEEDED|BUILD FAILED|error:)" | tail -5
echo "   ✅ 构建完成"

# 4. 安装并启动
echo "📍 步骤 4/4: 安装并启动..."
cp -R "/Users/fxj/Library/Developer/Xcode/DerivedData/macshot-daqnumwucnkubxhcwqiflmrfkyxk/Build/Products/Debug/macshot.app" "/Users/fxj/n/macshot/macshot-dev.app"
cp -R /Users/fxj/n/macshot/macshot-dev.app /Applications/
open /Applications/macshot-dev.app
echo "   ✅ 已安装并启动"

echo ""
echo "✅ 构建完成！"
echo ""
echo "🎯 快速测试:"
echo "   1. 按 Cmd+Shift+X 触发截图"
echo "   2. 按 3 键锁定 3:4 比例"
echo "   3. 拖拽框选，验证比例"
echo "   4. 松开鼠标，拖动句柄调整，验证仍保持比例"
echo ""
echo "📋 测试要点:"
echo "   □ 左上角固定"
echo "   □ 只向右下扩展"
echo "   □ 保持锁定比例"
echo "   □ 不再抖动"
echo ""
echo "祝测试愉快！🎊"
