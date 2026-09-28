#!/bin/bash
# 生成一张**固定的**自签名代码签名证书（维护者只需跑一次）。
#
#   ./scripts/make_signing_cert.sh [输出目录]
#
# 为什么需要它：
#   ad-hoc 签名的 designated requirement 是 `cdhash H"..."`，代码一变就变，
#   而 macOS 的 TCC（辅助功能授权）就是按这个 requirement 认人的——
#   于是每次升级用户都得重新授权一次。
#   换成固定证书后 requirement 变成 `identifier "..." and certificate root = H"..."`，
#   跨版本编译都一致，用户授权一次就一直有效。
#
# 产出（默认写到桌面下的 anywheredo-signing/）：
#   anywheredo-signing.p12   证书 + 私钥：请备份进密码管理器，并放进 CI secret
#   anywheredo-signing.txt   导入用的密码、证书 SHA-1、CN
set -euo pipefail

OUT="${1:-$HOME/Desktop/anywheredo-signing}"
CN="${SIGNING_CN:-AnywhereDo Signing}"
DAYS="${SIGNING_DAYS:-3650}"
PASSWORD="${SIGNING_P12_PASSWORD:-$(openssl rand -base64 24 | tr -d '/+=' | cut -c1-24)}"

mkdir -p "$OUT"
cd "$OUT"

if [ -f anywheredo-signing.p12 ]; then
  echo "已存在 $OUT/anywheredo-signing.p12 —— 不覆盖。" >&2
  echo "（证书一旦更换，所有用户的授权都会失效，所以这里只生成一次。）" >&2
  exit 1
fi

echo "==> 生成私钥与自签名证书（codeSigning 用途，$DAYS 天）"
openssl req -x509 -newkey rsa:2048 -sha256 -days "$DAYS" -nodes \
  -keyout anywheredo-signing.key.pem \
  -out anywheredo-signing.cert.pem \
  -subj "/CN=$CN/O=AnywhereDo" \
  -addext "basicConstraints=critical,CA:FALSE" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" >/dev/null 2>&1

echo "==> 打包成 .p12"
openssl pkcs12 -export \
  -out anywheredo-signing.p12 \
  -inkey anywheredo-signing.key.pem \
  -in anywheredo-signing.cert.pem \
  -passout "pass:$PASSWORD" \
  -name "$CN" >/dev/null 2>&1

SHA1="$(openssl x509 -in anywheredo-signing.cert.pem -noout -fingerprint -sha1 | cut -d= -f2 | tr -d ':')"

cat > anywheredo-signing.txt <<EOF
AnywhereDo 代码签名证书（自签名）
生成时间：$(date '+%Y-%m-%d %H:%M:%S')

  CN（SIGNING_IDENTITY） : $CN
  p12 密码               : $PASSWORD
  证书 SHA-1（小写）      : $SHA1
  有效期                 : $DAYS 天

TCC 会把这个 SHA-1 写进 designated requirement：
  identifier "dev.anywheredo.app" and certificate root = H"$SHA1"

请把这个 p12 与密码备份进密码管理器（丢了就要重新生成，而重新生成
会让所有已授权用户的授权失效）。放进 CI 时用：

  gh secret set SIGNING_P12_BASE64 --body "\$(base64 -i anywheredo-signing.p12 | tr -d '\n')"
  gh secret set SIGNING_P12_PASSWORD --body "$PASSWORD"

本地签名（不需要把证书装进登录钥匙串）：

  ./scripts/import_signing_cert.sh anywheredo-signing.p12 "$PASSWORD"
  SIGNING_IDENTITY="$CN" SIGNING_KEYCHAIN="\$HOME/Library/Keychains/anywheredo-signing.keychain-db" \\
    ./scripts/build_app.sh
EOF

rm -f anywheredo-signing.key.pem

echo
echo "完成，产出在：$OUT"
echo "  anywheredo-signing.p12   （备份它）"
echo "  anywheredo-signing.cert.pem（只有公钥，可以公开）"
echo "  anywheredo-signing.txt   （密码与 SHA-1，备份它）"
echo "  CN = $CN"
echo "  证书根哈希 = H\"$SHA1\""
