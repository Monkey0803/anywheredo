#!/bin/bash
# v1.1 验收清单：把「已实现」变成能一眼看懂的证据。
#
#   ./scripts/smoke_check.sh
#
# 分两部分：
#   A. 静态检查（不需要你操作）：版本、架构、签名 requirement、本地化资源
#   B. 行为检查（读诊断日志）：授权是否生效、三个交互是否真的被触发过
# B 部分没出现对应日志行时只提示「还没试」，不当成失败。
set -uo pipefail

APP="${APP:-/Applications/AnywhereDo.app}"
LOG="$HOME/Library/Application Support/AnywhereDo/diagnostics.log"
pass=0; pending=0; fail=0

ok()   { echo "  ✅ $1"; pass=$((pass+1)); }
todo() { echo "  ⏳ $1"; pending=$((pending+1)); }
bad()  { echo "  ❌ $1"; fail=$((fail+1)); }

echo "════ A. 静态检查（${APP}）════"
if [ ! -d "$APP" ]; then
  bad "找不到 $APP"
else
  VERSION=$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist" 2>/dev/null)
  [ "$VERSION" = "1.1.0" ] && ok "版本号 $VERSION" || bad "版本号是 ${VERSION}（期望 1.1.0）"

  ARCH=$(lipo -info "$APP/Contents/MacOS/AnywhereDo" 2>/dev/null)
  case "$ARCH" in
    *x86_64*arm64*|*arm64*x86_64*) ok "通用二进制（x86_64 + arm64）" ;;
    *) bad "架构不对：$ARCH" ;;
  esac

  REQ=$(codesign -d -r- "$APP" 2>&1 | tail -1)
  case "$REQ" in
    *cdhash*) bad "requirement 含 cdhash，升级后要重新授权：$REQ" ;;
    *certificate*) ok "requirement 基于固定证书（升级不再要求重新授权）" ;;
    *) bad "requirement 异常：$REQ" ;;
  esac

  codesign --verify --strict "$APP" 2>/dev/null && ok "签名校验通过" || bad "签名校验失败"
  [ -d "$APP/Contents/Resources/AnywhereDo_AnywhereDoCore.bundle" ] \
    && ok "本地化资源已打包（中英切换的前提）" || bad "缺本地化资源 bundle"

  "$APP/Contents/MacOS/AnywhereDo" --version >/dev/null 2>&1 \
    && ok "二进制可执行" || bad "二进制无法执行"
fi

echo
echo "════ B. 行为检查（读诊断日志）════"
if [ ! -f "$LOG" ]; then
  todo "还没有诊断日志：先启动一次 App"
else
  # 只认「最后一次启动」之后的记录，否则会把上一次会话的旧日志当成本次证据。
  TAIL=$(awk '/===== 启动 =====/{buf=""} {buf=buf $0 ORS} END{printf "%s", buf}' "$LOG")
  [ -n "$TAIL" ] || TAIL=$(tail -200 "$LOG")
  echo "  （本次启动之后的日志 $(echo "$TAIL" | grep -c . ) 行）"

  if echo "$TAIL" | grep -q "鼠标监听已安装"; then
    ok "辅助功能授权已生效（日志：划词：鼠标监听已安装）"
  elif echo "$TAIL" | grep -q "权限=未授予"; then
    todo "辅助功能仍未授予：系统设置 → 隐私与安全性 → 辅助功能，移除旧条目再添加一次"
  else
    todo "日志里没看到授权结果"
  fi

  if echo "$TAIL" | grep -q "悬停/点击小图标，展开卡片"; then
    ok "悬停小图标 → 展开整卡（日志：划词：悬停/点击小图标，展开卡片）"
  else
    todo "悬停展开还没触发过：划词后把鼠标移到小图标上"
  fi

  if echo "$TAIL" | grep -q "鼠标已在图标上（轮询判定）"; then
    ok "轮询兜底生效（日志：划词：鼠标已在图标上（轮询判定），展开卡片）"
  else
    todo "轮询兜底还没触发过：划词结束后把鼠标停在原位别动，图标正好在鼠标下时会自动展开"
  fi

  if echo "$TAIL" | grep -q "修饰键直达，执行"; then
    ok "修饰键直达（日志：划词：修饰键直达，执行「…」）"
  else
    todo "修饰键直达还没触发过：按住 ⌥ 再划词"
  fi

  if echo "$TAIL" | grep -q "检测到划词"; then
    ok "划词识别链路在工作"
  else
    todo "日志里没有划词记录"
  fi
fi

echo
echo "════ 汇总：通过 $pass 项，待验 $pending 项，失败 $fail 项 ════"
[ "$fail" -eq 0 ] || exit 1
