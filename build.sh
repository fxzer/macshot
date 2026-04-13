#!/bin/bash

# macshot 一键构建：停止 → 清理旧安装 → 清理旧权限 → 构建 → 安装启动
#
# 速度说明：默认只做增量 build（复用 DerivedData）。若每次全量重编，请加 --clean。
# xcodebuild 与 Xcode 同一套工具链；干净构建慢是正常现象，改几行 Swift 再增量会快很多。

set -e
set -o pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DERIVED_DATA="$ROOT_DIR/DerivedData"
PROJECT_FILE="$ROOT_DIR/macshot.xcodeproj/project.pbxproj"

detect_bundle_id() {
    local bundle_id
    bundle_id="$(grep -m 1 'PRODUCT_BUNDLE_IDENTIFIER =' "$PROJECT_FILE" | sed -E 's/.*PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);/\1/' | tr -d '[:space:]')"
    if [ -z "$bundle_id" ]; then
        bundle_id="com.fxzer.macshot.macshot"
    fi
    printf '%s\n' "$bundle_id"
}

reset_tcc_service() {
    local service="$1"
    local bundle_id="$2"
    if tccutil reset "$service" "$bundle_id" >/dev/null 2>&1; then
        echo "   ✅ 已重置 $service"
    else
        echo "   ⚠️  无法重置 $service"
    fi
}

DO_CLEAN=0
for arg in "$@"; do
    case "$arg" in
        --clean) DO_CLEAN=1 ;;
        -h|--help)
            echo "用法: $(basename "$0") [--clean]"
            echo "  默认: 增量构建（快）；若缺少 Sparkle.xcframework 会自动清理 SPM 工件并重解析"
            echo "  --clean: clean build（等价于全量重编，慢，怀疑缓存坏了再用）"
            exit 0
            ;;
    esac
done

BUNDLE_ID="$(detect_bundle_id)"

# 并行编译任务数（默认用 CPU 核数；与 Xcode 里 “并行编译” 一致思路）
JOBS="$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"

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
echo "📍 步骤 1/5: 停止旧版本..."
killall macshot-dev 2>/dev/null || true
killall macshot 2>/dev/null || true
sleep 0.3
echo "   ✅ 已停止"

# 2. 清理旧安装与残留
echo "📍 步骤 2/5: 清理旧安装与残留..."
rm -rf /Applications/macshot-dev.app
rm -rf "$ROOT_DIR/macshot-dev.app"
rm -rf ~/Desktop/macshot-backup-* 2>/dev/null || true
echo "   ✅ 已清理"

# 3. 清理旧权限系统
echo "📍 步骤 3/5: 清理旧权限系统..."
echo "   Bundle ID: $BUNDLE_ID"
reset_tcc_service "All" "$BUNDLE_ID"
reset_tcc_service "ScreenCapture" "$BUNDLE_ID"
reset_tcc_service "Microphone" "$BUNDLE_ID"
reset_tcc_service "Camera" "$BUNDLE_ID"

# 4. 构建
# Sparkle 为 SPM binaryTarget：若 artifacts 目录残缺（常见报错：找不到 Sparkle.xcframework），
# 仅 resolve 往往不会重下；需删掉损坏的 sparkle 产物并去掉 workspace-state，再 resolve。
SPARKLE_XCFW="$DERIVED_DATA/SourcePackages/artifacts/sparkle/Sparkle/Sparkle.xcframework"
if [ -d "$DERIVED_DATA/SourcePackages" ] && [ ! -d "$SPARKLE_XCFW" ]; then
    echo "📍 步骤 3b/5: Swift Package（Sparkle）产物缺失或损坏，正在清理并重解析..."
    rm -rf "$DERIVED_DATA/SourcePackages/artifacts/sparkle"
    rm -rf "$DERIVED_DATA/SourcePackages/artifacts/extract/sparkle"
    rm -f "$DERIVED_DATA/SourcePackages/workspace-state.json"
    xcodebuild \
        -project "$ROOT_DIR/macshot.xcodeproj" \
        -scheme macshot \
        -derivedDataPath "$DERIVED_DATA" \
        -resolvePackageDependencies
    echo "   ✅ 依赖已重新解析"
fi

if [ "$DO_CLEAN" -eq 1 ]; then
    echo "📍 步骤 4/5: 构建新版本（全量：clean build，较慢）..."
    BUILD_ACTIONS=(clean build)
else
    echo "📍 步骤 4/5: 构建新版本（增量：复用 DerivedData，较快）..."
    BUILD_ACTIONS=(build)
fi
SECONDS=0
xcodebuild \
    -project "$ROOT_DIR/macshot.xcodeproj" \
    -scheme macshot \
    -configuration Debug \
    -derivedDataPath "$DERIVED_DATA" \
    -jobs "$JOBS" \
    "${BUILD_ACTIONS[@]}" 2>&1 | grep -E "(BUILD SUCCEEDED|BUILD FAILED|error:)" | tail -5
echo "   ⏱ 编译耗时: ${SECONDS} 秒"
echo "   ✅ 构建完成"

# 5. 安装并启动
echo "📍 步骤 5/5: 安装并启动..."
cp -R "$DERIVED_DATA/Build/Products/Debug/macshot.app" "$ROOT_DIR/macshot-dev.app"
cp -R "$ROOT_DIR/macshot-dev.app" /Applications/
open /Applications/macshot-dev.app
echo "   ✅ 已安装并启动"

echo ""
echo "✅ 全部完成！构建时间: $(date +%H:%M)"
echo "祝测试愉快！🎊"
