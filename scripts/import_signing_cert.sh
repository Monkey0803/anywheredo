#!/bin/bash
# 把签名证书导入一个**独立的**钥匙串，让 codesign 能用（本地或 CI 都走这条）。
#
#   ./scripts/import_signing_cert.sh <p12路径> <p12密码> [钥匙串路径]
#
# 默认钥匙串：~/Library/Keychains/anywheredo-signing.keychain-db
# 它不会动你的登录钥匙串，也不改系统钥匙串搜索列表——
# build_app.sh 会通过 SIGNING_KEYCHAIN 显式指过来。
set -euo pipefail

P12="${1:?用法: import_signing_cert.sh <p12路径> <p12密码> [钥匙串路径]}"
PASSWORD="${2:?缺少 p12 密码}"
KEYCHAIN="${3:-$HOME/Library/Keychains/anywheredo-signing.keychain-db}"
KEYCHAIN_PASSWORD="${SIGNING_KEYCHAIN_PASSWORD:-anywheredo}"

[ -f "$P12" ] || { echo "找不到 $P12" >&2; exit 1; }

if [ ! -f "$KEYCHAIN" ]; then
  echo "==> 新建独立钥匙串：$KEYCHAIN"
  security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
  security set-keychain-settings -lut 21600 "$KEYCHAIN"
fi

echo "==> 解锁钥匙串"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"

echo "==> 导入证书"
security import "$P12" -k "$KEYCHAIN" -P "$PASSWORD" -T /usr/bin/codesign -A

# 没有这一步，codesign 读私钥时 macOS 会弹窗要授权（CI 上会直接卡住）。
echo "==> 允许 codesign 无交互使用该私钥"
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null

echo
echo "完成。可用的签名身份："
security find-certificate -a -c "AnywhereDo" -Z "$KEYCHAIN" 2>/dev/null | awk '/SHA-1 hash/{print "  SHA-1: " $3}' || true
echo
echo "下一步："
echo "  SIGNING_IDENTITY=\"AnywhereDo Signing\" SIGNING_KEYCHAIN=\"$KEYCHAIN\" ./scripts/build_app.sh"
echo
echo "注意：自签名证书不会被系统「信任」，所以"
echo "  · codesign --verify 会通过（requirement 可满足）"
echo "  · Gatekeeper 依然会拒绝带隔离标记的下载包（和 ad-hoc 一样，用户右键打开即可）"
echo "  · 但 TCC 的辅助功能授权从此按「identifier + 证书」认人，升级不再失效"
