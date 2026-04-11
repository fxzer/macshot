#!/bin/bash

# macshot 宽高比锁定功能 - 一键构建脚本
# 自动清理旧版本 → 清除系统权限 → 构建 → 安装 → 启动

set -e

# sudo 密码（必须从环境变量 SUDO_PASSWORD 读取）
if [ -z "$SUDO_PASSWORD" ]; then
    echo "❌ 错误：请设置 SUDO_PASSWORD 环境变量"
    echo "   在 fish 中配置：编辑 ~/.config/fish/conf.d/_secrets.fish"
    echo "   添加：set -gx SUDO_PASSWORD \"你的密码\""
    echo "   然后运行: source ~/.config/fish/conf.d/_secrets.fish"
    exit 1
fi

echo "🚀 macshot 一键构建脚本"
echo "========================================"

# 1. 停止旧版本
echo "📍 步骤 1/4: 停止旧版本..."
killall macshot-dev 2>/dev/null || true
killall macshot 2>/dev/null || true
sleep 1
echo "   ✅ 已停止"

# 2. 清理旧版本和系统权限
echo "📍 步骤 2/4: 清理旧版本和系统权限..."
rm -rf /Applications/macshot-dev.app
rm -rf /Users/fxj/n/macshot/macshot-dev.app
rm -rf ~/Desktop/macshot-backup-* 2>/dev/null || true

# 清除系统权限（屏幕录制、辅助功能等）
echo "   🔑 清除系统权限（屏幕录制、辅助功能等）..."
if tccutil reset All com.sw33tlie.macshot.macshot 2>/dev/null; then
    echo "   ✅ 系统权限已清除"
else
    echo "   ⚠️  权限清除失败（可能需要手动在系统设置中移除）"
fi

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
echo "祝测试愉快！🎊"
