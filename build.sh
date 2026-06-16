#!/bin/bash

# macshot 一键构建：停止 → 构建 → 安装 → 启动
# ad-hoc 签名，不弹密码框，不碰钥匙串

set -e
set -o pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DERIVED_DATA="$ROOT_DIR/DerivedData"
PROJECT_FILE="$ROOT_DIR/macshot.xcodeproj/project.pbxproj"
APP_NAME="MacShot.app"
APP_INSTALL_PATH="/Applications/$APP_NAME"
APP_WORKTREE_PATH="$ROOT_DIR/$APP_NAME"
ENTITLEMENTS_PATH="$ROOT_DIR/macshot/Resources/macshot.entitlements"

detect_bundle_id() {
    local bundle_id
    bundle_id="$(grep -m 1 'PRODUCT_BUNDLE_IDENTIFIER =' "$PROJECT_FILE" | sed -E 's/.*PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);/\1/' | tr -d '[:space:]')"
    if [ -z "$bundle_id" ]; then
        bundle_id="com.fxzer.macshot.macshot"
    fi
    printf '%s\n' "$bundle_id"
}

sign_app() {
    local app_path="$1"
    /usr/bin/codesign --force --deep --sign - \
        --entitlements "$ENTITLEMENTS_PATH" \
        --timestamp=none \
        "$app_path"
    /usr/bin/codesign --verify --deep --strict "$app_path" 2>/dev/null || true
}

sync_app() {
    local source_app="$1"
    local target_app="$2"
    mkdir -p "$target_app"
    rsync -a --delete "$source_app/" "$target_app/"
}

DO_CLEAN=0
for arg in "$@"; do
    case "$arg" in
        --clean) DO_CLEAN=1 ;;
        -h|--help)
            echo "用法: $(basename "$0") [--clean]"
            echo "  ad-hoc 签名，不弹密码框"
            echo "  --clean: 全量重编"
            exit 0
            ;;
    esac
done

BUNDLE_ID="$(detect_bundle_id)"
JOBS="$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"

echo "🚀 macshot 一键构建（ad-hoc 签名）"
echo "========================================"

# 1. 停止旧版本
echo "📍 步骤 1/4: 停止旧版本..."
killall MacShot 2>/dev/null || true
sleep 0.3
echo "   ✅ 已停止"

# 2. 清理旧版本
echo "📍 步骤 2/4: 清理旧应用..."
rm -rf "$APP_WORKTREE_PATH"
echo "   ✅ 已清理"

# 3. 构建
SPARKLE_XCFW="$DERIVED_DATA/SourcePackages/artifacts/sparkle/Sparkle/Sparkle.xcframework"
if [ -d "$DERIVED_DATA/SourcePackages" ] && [ ! -d "$SPARKLE_XCFW" ]; then
    echo "📍 步骤 3a/4: Sparkle 产物缺失，正在重解析..."
    rm -rf "$DERIVED_DATA/SourcePackages/artifacts/sparkle"
    rm -rf "$DERIVED_DATA/SourcePackages/artifacts/extract/sparkle"
    rm -f "$DERIVED_DATA/SourcePackages/workspace-state.json"
    xcodebuild -project "$ROOT_DIR/macshot.xcodeproj" -scheme macshot -derivedDataPath "$DERIVED_DATA" -resolvePackageDependencies
    echo "   ✅ 依赖已重新解析"
fi

if [ "$DO_CLEAN" -eq 1 ]; then
    echo "📍 步骤 3/4: 构建（全量）..."
    BUILD_ACTIONS=(clean build)
else
    echo "📍 步骤 3/4: 构建（增量）..."
    BUILD_ACTIONS=(build)
fi

SECONDS=0
xcodebuild \
    -project "$ROOT_DIR/macshot.xcodeproj" \
    -scheme macshot \
    -configuration Debug \
    -derivedDataPath "$DERIVED_DATA" \
    -jobs "$JOBS" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    "${BUILD_ACTIONS[@]}" 2>&1 | grep -E "(BUILD SUCCEEDED|BUILD FAILED|error:)" | tail -5
echo "   ⏱ 编译耗时: ${SECONDS} 秒"
echo "   ✅ 构建完成"

# 4. 安装并启动
echo "📍 步骤 4/4: 安装并启动..."
sync_app "$DERIVED_DATA/Build/Products/Debug/MacShot.app" "$APP_WORKTREE_PATH"
sync_app "$APP_WORKTREE_PATH" "$APP_INSTALL_PATH"
sign_app "$APP_INSTALL_PATH"
open "$APP_INSTALL_PATH"
echo "   ✅ 已安装并启动"

echo ""
echo "✅ 全部完成！$(date +%H:%M)"
