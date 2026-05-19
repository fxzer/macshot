#!/bin/bash

# macshot 一键构建：停止 → 清理工作副本 → 可选重置权限 → 构建 → 原地更新安装并启动
#
# 速度说明：默认只做增量 build（复用 DerivedData）。若每次全量重编，请加 --clean。
# xcodebuild 与 Xcode 同一套工具链；干净构建慢是正常现象，改几行 Swift 再增量会快很多。

set -e
set -o pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DERIVED_DATA="$ROOT_DIR/DerivedData"
PROJECT_FILE="$ROOT_DIR/macshot.xcodeproj/project.pbxproj"
APP_NAME="MacShot-dev.app"
APP_INSTALL_PATH="/Applications/$APP_NAME"
APP_WORKTREE_PATH="$ROOT_DIR/$APP_NAME"
ENTITLEMENTS_PATH="$ROOT_DIR/macshot/Resources/macshot.entitlements"
SIGNING_SUPPORT_DIR="$HOME/Library/Application Support/macshot"
SIGNING_KEYCHAIN="$HOME/Library/Keychains/macshot-dev-signing.keychain-db"
SIGNING_PASSWORD_FILE="$SIGNING_SUPPORT_DIR/dev-signing-keychain-password"
SIGNING_CERT_CN="macshot Local Code Signing"

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

ensure_local_codesign_identity() {
    mkdir -p "$SIGNING_SUPPORT_DIR"
    chmod 700 "$SIGNING_SUPPORT_DIR"

    ensure_signing_password_file

    if [ ! -f "$SIGNING_KEYCHAIN" ]; then
        security create-keychain -p "$SIGNING_KEYCHAIN_PASSWORD" "$SIGNING_KEYCHAIN"
    fi

    if ! unlock_local_signing_keychain; then
        echo "   ⚠️  本地签名钥匙串密码不匹配，正在重建项目专用钥匙串..."
        security delete-keychain "$SIGNING_KEYCHAIN" >/dev/null 2>&1 || rm -f "$SIGNING_KEYCHAIN"
        rm -f "$SIGNING_PASSWORD_FILE"
        ensure_signing_password_file
        security create-keychain -p "$SIGNING_KEYCHAIN_PASSWORD" "$SIGNING_KEYCHAIN"
        unlock_local_signing_keychain
    fi

    set_local_signing_keychain_search_list
    security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$SIGNING_KEYCHAIN_PASSWORD" "$SIGNING_KEYCHAIN" >/dev/null 2>&1 || true

    if security find-identity -v -p codesigning "$SIGNING_KEYCHAIN" 2>/dev/null | grep -Fq "$SIGNING_CERT_CN"; then
        return
    fi

    echo "📍 步骤 4a/5: 创建本机自签名代码签名证书..."
    local tmpdir
    tmpdir="$(mktemp -d)"
    trap 'rm -rf "$tmpdir"' RETURN

    cat > "$tmpdir/openssl.cnf" <<'EOF'
[req]
distinguished_name = dn
x509_extensions = v3_req
prompt = no
[dn]
CN = macshot Local Code Signing
O = Local Dev
[v3_req]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = codeSigning
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
EOF

    local p12_password
    p12_password="macshot-local-codesign"

    /opt/homebrew/bin/openssl req -new -newkey rsa:2048 -nodes -x509 -days 3650 \
        -config "$tmpdir/openssl.cnf" \
        -keyout "$tmpdir/key.pem" \
        -out "$tmpdir/cert.pem"

    /opt/homebrew/bin/openssl pkcs12 -export \
        -inkey "$tmpdir/key.pem" \
        -in "$tmpdir/cert.pem" \
        -out "$tmpdir/cert.p12" \
        -passout pass:"$p12_password"

    security import "$tmpdir/cert.p12" \
        -k "$SIGNING_KEYCHAIN" \
        -P "$p12_password" \
        -f pkcs12 \
        -T /usr/bin/codesign \
        -T /usr/bin/security

    security add-trusted-cert -d -r trustRoot -p codeSign -k "$SIGNING_KEYCHAIN" "$tmpdir/cert.pem"
    security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$SIGNING_KEYCHAIN_PASSWORD" "$SIGNING_KEYCHAIN"

    if security find-identity -v -p codesigning "$SIGNING_KEYCHAIN" 2>/dev/null | grep -Fq "$SIGNING_CERT_CN"; then
        echo "   ✅ 本机自签名证书已创建"
    else
        echo "   ❌ 自签名代码签名证书创建失败"
        exit 1
    fi
}

ensure_signing_password_file() {
    if [ ! -f "$SIGNING_PASSWORD_FILE" ]; then
        /opt/homebrew/bin/openssl rand -base64 24 > "$SIGNING_PASSWORD_FILE"
        chmod 600 "$SIGNING_PASSWORD_FILE"
    fi

    SIGNING_KEYCHAIN_PASSWORD="$(cat "$SIGNING_PASSWORD_FILE")"
    export SIGNING_KEYCHAIN_PASSWORD
}

unlock_local_signing_keychain() {
    security set-keychain-settings -lut 21600 "$SIGNING_KEYCHAIN"
    security unlock-keychain -p "$SIGNING_KEYCHAIN_PASSWORD" "$SIGNING_KEYCHAIN" >/dev/null 2>&1
}

set_local_signing_keychain_search_list() {
    local keychain
    local current_keychains=()
    local next_keychains=("$SIGNING_KEYCHAIN")

    while IFS= read -r keychain; do
        keychain="${keychain//\"/}"
        [ -z "$keychain" ] && continue
        current_keychains+=("$keychain")
    done < <(security list-keychains -d user 2>/dev/null)

    for keychain in "${current_keychains[@]}"; do
        [ "$keychain" = "$SIGNING_KEYCHAIN" ] && continue
        if ! printf '%s\n' "${next_keychains[@]}" | grep -Fxq "$keychain"; then
            next_keychains+=("$keychain")
        fi
    done

    security list-keychains -d user -s "${next_keychains[@]}"
}

sign_app_bundle() {
    local app_path="$1"
    unlock_local_signing_keychain
    security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$SIGNING_KEYCHAIN_PASSWORD" "$SIGNING_KEYCHAIN" >/dev/null 2>&1 || true

    /usr/bin/codesign --force --deep --sign "$SIGNING_CERT_CN" \
        --keychain "$SIGNING_KEYCHAIN" \
        --entitlements "$ENTITLEMENTS_PATH" \
        --timestamp=none \
        "$app_path"

    /usr/bin/codesign --verify --deep --strict "$app_path"
    echo "   ✅ 已使用固定本机证书签名"
}

sync_app_bundle() {
    local source_app="$1"
    local target_app="$2"

    mkdir -p "$target_app"
    rsync -a --delete "$source_app/" "$target_app/"
}

DO_CLEAN=0
DO_RESET_PERMISSIONS=0  # 默认不重置权限，避免每次打包都要重新授权
for arg in "$@"; do
    case "$arg" in
        --clean) DO_CLEAN=1 ;;
        --reset-permissions) DO_RESET_PERMISSIONS=1 ;;
        -h|--help)
            echo "用法: $(basename "$0") [--clean] [--reset-permissions]"
            echo "  默认: 增量构建（快）；若缺少 Sparkle.xcframework 会自动清理 SPM 工件并重解析"
            echo "  --clean: clean build（等价于全量重编，慢，怀疑缓存坏了再用）"
            echo "  --reset-permissions: 重置应用权限（需要重新授权屏幕录制等）"
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
killall MacShot-dev 2>/dev/null || true
killall MacShot 2>/dev/null || true
killall MacShot-dev 2>/dev/null || true
killall MacShot 2>/dev/null || true
killall macshot-dev 2>/dev/null || true
killall macshot 2>/dev/null || true
sleep 0.3
echo "   ✅ 已停止"

# 2. 清理工作副本残留
echo "📍 步骤 2/5: 清理工作副本残留..."
rm -rf "$APP_WORKTREE_PATH"
rm -rf ~/Desktop/macshot-backup-* 2>/dev/null || true
echo "   ✅ 已清理"

# 3. 清理旧权限系统（仅在 --reset-permissions 时执行）
if [ "$DO_RESET_PERMISSIONS" -eq 1 ]; then
    echo "📍 步骤 3/5: 清理旧权限系统..."
    echo "   Bundle ID: $BUNDLE_ID"
    reset_tcc_service "All" "$BUNDLE_ID"
    reset_tcc_service "ScreenCapture" "$BUNDLE_ID"
    reset_tcc_service "Microphone" "$BUNDLE_ID"
    reset_tcc_service "Camera" "$BUNDLE_ID"
else
    echo "📍 步骤 3/5: 跳过权限清理（保留已有授权）"
fi

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
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    "${BUILD_ACTIONS[@]}" 2>&1 | grep -E "(BUILD SUCCEEDED|BUILD FAILED|error:)" | tail -5
echo "   ⏱ 编译耗时: ${SECONDS} 秒"
echo "   ✅ 构建完成"

# 5. 安装并启动
echo "📍 步骤 5/5: 安装并启动..."
ensure_local_codesign_identity
sync_app_bundle "$DERIVED_DATA/Build/Products/Debug/MacShot.app" "$APP_WORKTREE_PATH"
sync_app_bundle "$APP_WORKTREE_PATH" "$APP_INSTALL_PATH"
sign_app_bundle "$APP_INSTALL_PATH"
open "$APP_INSTALL_PATH"
echo "   ✅ 已安装并启动"

echo ""
echo "✅ 全部完成！构建时间: $(date +%H:%M)"
echo "祝测试愉快！🎊"
