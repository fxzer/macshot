#!/bin/bash

# macshot 一键构建：停止 → 构建 → 安装 → 启动
# 自签名证书放登录钥匙串，权限稳定 + 永不弹密码框

set -e
set -o pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DERIVED_DATA="$ROOT_DIR/DerivedData"
PROJECT_FILE="$ROOT_DIR/macshot.xcodeproj/project.pbxproj"
APP_NAME="MacShot.app"
APP_INSTALL_PATH="/Applications/$APP_NAME"
APP_WORKTREE_PATH="$ROOT_DIR/$APP_NAME"
ENTITLEMENTS_PATH="$ROOT_DIR/macshot/Resources/macshot.entitlements"
SIGNING_CERT_CN="macshot Local Code Signing"
SIGNING_CERT_FILE="$HOME/Library/Application Support/macshot/signing-cert-sha.txt"
OPENSSL_BIN="${OPENSSL_BIN:-/opt/homebrew/bin/openssl}"

if [ ! -x "$OPENSSL_BIN" ]; then
    OPENSSL_BIN="$(command -v openssl || true)"
fi

detect_bundle_id() {
    local bundle_id
    bundle_id="$(grep -m 1 'PRODUCT_BUNDLE_IDENTIFIER =' "$PROJECT_FILE" | sed -E 's/.*PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);/\1/' | tr -d '[:space:]')"
    if [ -z "$bundle_id" ]; then
        bundle_id="com.fxzer.macshot.macshot"
    fi
    printf '%s\n' "$bundle_id"
}

get_signing_sha() {
    if [ -f "$SIGNING_CERT_FILE" ]; then
        cat "$SIGNING_CERT_FILE"
        return 0
    fi
    # 从所有身份中找匹配的 SHA
    local sha
    sha="$(security find-identity 2>/dev/null | grep "$SIGNING_CERT_CN" | head -1 | awk '{print $2}')"
    if [ -n "$sha" ] && [ ${#sha} -eq 40 ]; then
        mkdir -p "$(dirname "$SIGNING_CERT_FILE")"
        printf '%s\n' "$sha" > "$SIGNING_CERT_FILE"
        printf '%s\n' "$sha"
        return 0
    fi
    return 1
}

ensure_signing_cert() {
    if get_signing_sha >/dev/null 2>&1; then
        return 0
    fi

    echo "📍 首次运行：创建本机自签名证书..."
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

    local p12_password="macshot-local-codesign"

    if [ -z "$OPENSSL_BIN" ]; then
        echo "   ❌ 未找到 openssl"
        exit 1
    fi

    "$OPENSSL_BIN" req -new -newkey rsa:2048 -nodes -x509 -days 3650 \
        -config "$tmpdir/openssl.cnf" \
        -keyout "$tmpdir/key.pem" \
        -out "$tmpdir/cert.pem"

    "$OPENSSL_BIN" pkcs12 -export \
        -inkey "$tmpdir/key.pem" \
        -in "$tmpdir/cert.pem" \
        -out "$tmpdir/cert.p12" \
        -passout pass:"$p12_password"

    security import "$tmpdir/cert.p12" \
        -k "$HOME/Library/Keychains/login.keychain-db" \
        -P "$p12_password" \
        -f pkcs12 \
        -A \
        -T /usr/bin/codesign \
        -T /usr/bin/security

    if get_signing_sha >/dev/null 2>&1; then
        echo "   ✅ 自签名证书已创建"
    else
        echo "   ❌ 证书创建失败"
        exit 1
    fi
}

sign_app() {
    local app_path="$1"
    local sha
    sha="$(get_signing_sha)"
    /usr/bin/codesign --force --deep --sign "$sha" \
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
            echo "  自签名证书放登录钥匙串，权限稳定 + 永不弹密码"
            echo "  --clean: 全量重编"
            exit 0
            ;;
    esac
done

BUNDLE_ID="$(detect_bundle_id)"
JOBS="$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"

echo "🚀 macshot 一键构建"
echo "========================================"

ensure_signing_cert

# 1. 停止
echo "📍 步骤 1/4: 停止旧版本..."
killall MacShot 2>/dev/null || true
sleep 0.3
echo "   ✅ 已停止"

# 2. 清理
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
    xcodebuild -project "$ROOT_DIR/macshot.xcodeproj" -scheme macshot -derivedDataPath "$DERIVED_DATA" -resolvePackageDependencies -quiet
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
BUILD_LOG="$DERIVED_DATA/build.log"
mkdir -p "$DERIVED_DATA"

configure_xcodebuild_cmd() {
    XCODEBUILD_CMD=(
        xcodebuild
        -project "$ROOT_DIR/macshot.xcodeproj"
        -scheme macshot
        -configuration Debug
        -derivedDataPath "$DERIVED_DATA"
        -jobs "$JOBS"
        -skipPackageUpdates
        -showBuildTimingSummary
        CODE_SIGNING_ALLOWED=NO
        CODE_SIGNING_REQUIRED=NO
        "${BUILD_ACTIONS[@]}"
    )
}

run_xcodebuild() {
    local log_file="$1"
    set +e
    if command -v xcbeautify &>/dev/null; then
        "${XCODEBUILD_CMD[@]}" 2>&1 | tee "$log_file" | xcbeautify --quiet
        local status="${PIPESTATUS[0]}"
    else
        "${XCODEBUILD_CMD[@]}" 2>&1 | tee "$log_file" | tail -20
        local status="${PIPESTATUS[0]}"
    fi
    set -e
    return "$status"
}

configure_xcodebuild_cmd
run_xcodebuild "$BUILD_LOG"
BUILD_STATUS="$?"
if [ "$BUILD_STATUS" -ne 0 ] && [ "$DO_CLEAN" -eq 0 ] && /usr/bin/grep -q '\*\*\* DESERIALIZATION FAILURE \*\*\*' "$BUILD_LOG"; then
    echo "   ⚠️ Swift 增量缓存损坏，自动全量重编..."
    BUILD_ACTIONS=(clean build)
    configure_xcodebuild_cmd
    : > "$BUILD_LOG"
    run_xcodebuild "$BUILD_LOG"
    BUILD_STATUS="$?"
fi
echo "   ⏱ 编译耗时: ${SECONDS} 秒"
if [ "$BUILD_STATUS" -ne 0 ]; then
    echo "   ❌ 构建失败"
    echo "   📄 详细日志: $BUILD_LOG"
    exit 1
fi
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
