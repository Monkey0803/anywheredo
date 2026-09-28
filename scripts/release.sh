#!/bin/bash
# 一条命令发版：构建 → 签名 → 校验 → 打包 → 建 Release → 更新 tap 的 cask。
#
#   ./scripts/release.sh              正式发版
#   ./scripts/release.sh --dry-run    只做到「校验产物」，不动 git、不发 Release
#
# 前置条件：
#   1. 版本号已改（唯一来源 Sources/AnywhereDoCore/Version.swift 的 marketing）
#   2. 工作区干净、在 main 分支、已与远端同步
#   3. 签名证书已导入（见 RELEASING.md），或环境里给了 SIGNING_IDENTITY
#   4. 已安装 gh 并登录（用于建 Release、推送 tap）
set -euo pipefail

DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1

cd "$(dirname "$0")/.."
REPO="Monkey0803/anywheredo"
TAP_REPO="Monkey0803/homebrew-tap"
TAP_CASK_PATH="Casks/anywheredo.rb"

VERSION="$(grep -oE 'marketing *= *"[^"]+"' Sources/AnywhereDoCore/Version.swift | head -1 | sed -E 's/.*"([^"]+)"/\1/')"
[ -n "$VERSION" ] || { echo "读不到版本号" >&2; exit 1; }
TAG="v$VERSION"
ZIP="/tmp/AnywhereDo-$VERSION-universal.zip"

echo "==> 目标：$TAG$([ $DRY_RUN = 1 ] && echo '（dry-run）')"

if [ "$DRY_RUN" = 0 ]; then
  echo "==> 检查工作区"
  [ -z "$(git status --porcelain)" ] || { echo "工作区不干净，先提交" >&2; exit 1; }
  [ "$(git rev-parse --abbrev-ref HEAD)" = "main" ] || { echo "请在 main 分支发版" >&2; exit 1; }
  git fetch --quiet origin
  [ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || { echo "本地与 origin/main 不一致" >&2; exit 1; }
  if git rev-parse "$TAG" >/dev/null 2>&1 || gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
    echo "$TAG 已存在，先把 Version.swift 的版本号往上加" >&2
    exit 1
  fi
fi

echo "==> 构建（通用二进制 + 证书签名）"
UNIVERSAL=1 ./scripts/build_app.sh

echo "==> 校验产物"
APP="build/AnywhereDo.app"
plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist" | grep -qx "$VERSION" \
  || { echo "包内版本号与 Version.swift 不一致" >&2; exit 1; }
lipo -info "$APP/Contents/MacOS/AnywhereDo" | tee /dev/stderr | grep -q "x86_64" \
  || { echo "缺少 x86_64 架构" >&2; exit 1; }
lipo -info "$APP/Contents/MacOS/AnywhereDo" | grep -q "arm64" || { echo "缺少 arm64 架构" >&2; exit 1; }
REQUIREMENT="$(codesign -d -r- "$APP" 2>&1 | tail -1)"
case "$REQUIREMENT" in
  *cdhash*) echo "❌ designated requirement 含 cdhash，用户升级后要重新授权：" >&2; echo "   $REQUIREMENT" >&2; exit 1 ;;
  *) echo "✅ 签名 requirement：$REQUIREMENT" ;;
esac
codesign --verify --strict "$APP"
[ -d "$APP/Contents/Resources/AnywhereDo_AnywhereDoCore.bundle" ] \
  || { echo "缺少本地化资源 bundle" >&2; exit 1; }

echo "==> 打包"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
SHA="$(shasum -a 256 "$ZIP" | awk '{print $1}')"
SIZE="$(du -h "$ZIP" | cut -f1)"
echo "    $ZIP  ($SIZE)"
echo "    sha256=$SHA"

if [ "$DRY_RUN" = 1 ]; then
  echo
  echo "==> dry-run 结束。正式发版时接下来会："
  echo "    1. 建 tag $TAG 与 Release，并上传 $ZIP"
  echo "    2. 把 $TAP_REPO 的 $TAP_CASK_PATH 改成 version \"$VERSION\" / sha256 \"$SHA\" 并推送"
  exit 0
fi

echo "==> 建 Release"
NOTES="$(mktemp)"
cat > "$NOTES" <<EOF
## 安装

\`\`\`bash
brew install --cask monkey0803/tap/anywheredo
\`\`\`

或从下方附件下载 \`AnywhereDo-$VERSION-universal.zip\`（通用二进制，Apple Silicon 与 Intel 都能跑），
解压后把 AnywhereDo.app 拖进 /Applications。

> AnywhereDo 未上架 App Store，也未做 Apple 公证（Notarization）。
> 首次打开若提示「无法验证开发者」，请**右键 → 打开**，或执行：
> \`xattr -dr com.apple.quarantine /Applications/AnywhereDo.app\`

## 校验

\`\`\`
sha256  $SHA
\`\`\`

## 本版内容

<!-- 在这里补上本版改动，发版后也可以在 GitHub 上编辑 -->
EOF
gh release create "$TAG" "$ZIP" --repo "$REPO" --title "AnywhereDo $VERSION" --notes-file "$NOTES"
rm -f "$NOTES"

echo "==> 更新 tap 的 cask"
TAP_DIR="$(mktemp -d)/tap"
gh repo clone "$TAP_REPO" "$TAP_DIR" -- --depth 1 >/dev/null 2>&1
CASK="$TAP_DIR/$TAP_CASK_PATH"
sed -i '' -E "s/^  version \".*\"/  version \"$VERSION\"/" "$CASK"
sed -i '' -E "s/^  sha256 \".*\"/  sha256 \"$SHA\"/" "$CASK"
grep -q "version \"$VERSION\"" "$CASK" || { echo "cask 版本没写进去" >&2; exit 1; }
grep -q "sha256 \"$SHA\"" "$CASK" || { echo "cask sha256 没写进去" >&2; exit 1; }
git -C "$TAP_DIR" diff --stat
git -C "$TAP_DIR" commit -qam "anywheredo $VERSION"
git -C "$TAP_DIR" push -q origin HEAD:main
rm -rf "$(dirname "$TAP_DIR")"

echo
echo "✅ 完成：$TAG 已发布，tap 已更新到 $VERSION"
echo "   验证：brew update && brew fetch --cask anywheredo"
