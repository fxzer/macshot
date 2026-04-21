#!/bin/bash
# 为 macshot 创建自签名代码签名证书
# 运行一次即可，之后 Xcode 会自动使用这个证书

set -e

CERT_NAME="Macshot Development"
CERT_EMAIL="macshot@fxzer.local"

echo "🔐 创建 macshot 开发证书..."
echo "========================================"

# 检查是否已存在
if security find-certificate -c "$CERT_NAME" ~/Library/Keychains/login.keychain-db 2>/dev/null; then
    echo "✅ 证书已存在: $CERT_NAME"
    echo ""
    echo "请在 Xcode 中配置："
    echo "1. 打开 macshot.xcodeproj"
    echo "2. 选择项目 → Signing & Capabilities"
    echo "3. Team 选择你的证书 (应该显示为 '$CERT_NAME')"
    exit 0
fi

# 创建证书请求配置
cat > /tmp/macshot_cert.cnf << 'CNF'
[req]
distinguished_name = req_distinguished_name
x509_extensions = code_signing_ext
prompt = no

[req_distinguished_name]
CN = Macshot Development
OU = Development
O = fxzer
emailAddress = macshot@fxzer.local

[code_signing_ext]
basicConstraints = CA:FALSE
keyUsage = digitalSignature
extendedKeyUsage = codeSigning
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
CNF

# 生成私钥和自签名证书 (10年有效期)
openssl req -x509 -newkey rsa:2048 \
    -keyout /tmp/macshot_key.pem \
    -out /tmp/macshot_cert.pem \
    -days 3650 \
    -nodes \
    -config /tmp/macshot_cert.cnf 2>/dev/null

# 转换为 PKCS12 格式以便导入钥匙串
openssl pkcs12 -export \
    -out /tmp/macshot_cert.p12 \
    -inkey /tmp/macshot_key.pem \
    -in /tmp/macshot_cert.pem \
    -passout pass:temp123 2>/dev/null

# 导入到登录钥匙串
security import /tmp/macshot_cert.p12 \
    -k ~/Library/Keychains/login.keychain-db \
    -P temp123 \
    -T /usr/bin/codesign \
    -T /Applications/Xcode.app

# 设置信任为代码签名
security add-trusted-cert \
    -d \
    -r trustRoot \
    -k ~/Library/Keychains/login.keychain-db \
    -p codeSign \
    /tmp/macshot_cert.pem 2>/dev/null || true

# 清理临时文件
rm -f /tmp/macshot_cert.* /tmp/macshot_key.pem /tmp/macshot_cert.cnf

echo "✅ 证书创建完成: $CERT_NAME"
echo ""
echo "下一步："
echo "1. 打开 Xcode → macshot 项目 → Signing & Capabilities"
echo "2. Team 下拉菜单中选择 '$CERT_NAME'"
echo "3. 重新构建应用"
echo ""
echo "之后每次构建都会使用这个证书，CDHash 保持稳定，权限不会丢失！"
