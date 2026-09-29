#!/bin/bash
# check-update.sh — 检查 DSH 官方是否有新版本，并评估本补丁集是否需要重新适配
#
# 用法: bash check-update.sh   （本分支固定适配 DSH 0.2.0-rc.2）
# 说明:
#   1. 读取本地已装 DSH 版本
#   2. 查询 npm 官方的 latest 与 next 两个频道
#   3. 判断补丁集是否仍对得上，并给出下一动作指引
#
# ⚠️ 为什么要同时看两个频道：官方的大版本候选版（如 0.2.0-rc.1）常常**只发在 next 上**，
#    此时 `npm view @deepseek-ai/dsh version`（= latest）会返回**更旧**的版本。
#    只看 latest 会得出「官方版本比补丁适配版本旧」的荒谬结论，并建议用户"升级"到旧版。

set -e

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; DIM='\033[2m'; NC='\033[0m'

# 本仓库（version/0.2.0-rc.1 分支）固定适配的 DSH 版本
TARGET="0.2.0-rc.1"

# 1. 本地已装版本（通过全局 npm root 找到 DSH）
LOCAL=""
GLOBAL_ROOT=$(npm root -g 2>/dev/null || echo "")
DSH_PKG=""
for cand in "$GLOBAL_ROOT/@deepseek-ai/dsh/package.json" "$HOME/.local/lib/node_modules/@deepseek-ai/dsh/package.json"; do
  if [ -f "$cand" ]; then DSH_PKG="$cand"; break; fi
done
if [ -n "$DSH_PKG" ]; then
  LOCAL=$(node -e "console.log(require('$DSH_PKG').version)" 2>/dev/null)
fi
[ -z "$LOCAL" ] && LOCAL="(未找到本地 DSH)"
echo -e "${GREEN}本地已装 DSH：${NC}${LOCAL}"

# 2. 官方版本 —— 两个频道都要看（见文件头说明）
LATEST=$(npm view @deepseek-ai/dsh dist-tags.latest 2>/dev/null || echo "")
NEXT=$(npm view @deepseek-ai/dsh dist-tags.next 2>/dev/null || echo "")
if [ -z "$LATEST" ] && [ -z "$NEXT" ]; then
  echo -e "${RED}❌ 无法查询 npm 上的 @deepseek-ai/dsh 版本（网络或 npm 源问题）${NC}"
  exit 1
fi
echo -e "${YELLOW}官方 latest：${NC}${LATEST:-（无）}"
echo -e "${YELLOW}官方 next  ：${NC}${NEXT:-（无）}"

# 3. 判断
echo ""
if [ "$TARGET" = "$LATEST" ]; then
  echo -e "${GREEN}✅ 补丁集适配版本 = 官方 latest，无需额外处理。${NC}"
  echo -e "   适配版本：${YELLOW}${TARGET}${NC}"
elif [ -n "$NEXT" ] && [ "$TARGET" = "$NEXT" ]; then
  echo -e "${GREEN}✅ 补丁集适配版本 = 官方 next（${NEXT}），符合预期。${NC}"
  echo -e "   官方 latest 仍是 ${LATEST} —— 本仓库跟随 next 频道，两者不一致是正常的。"
  echo -e "   ⚠️ 注意：${YELLOW}npm install -g @deepseek-ai/dsh${NC} 默认装到 ${LATEST}；"
  echo -e "      要用本补丁集请显式装：${YELLOW}npm install -g @deepseek-ai/dsh@${TARGET}${NC}"
elif [ "$LOCAL" = "$LATEST" ] || { [ -n "$NEXT" ] && [ "$LOCAL" = "$NEXT" ]; }; then
  echo -e "${GREEN}✅ 本地已装 ${LOCAL}，与官方发布一致。${NC}"
  echo -e "   本补丁集适配版本：${YELLOW}${TARGET}${NC} —— 若与本地不符，请 checkout 对应 tag"
else
  # 取两频道中较新的一个作为「官方最新」
  NEWEST=$(printf '%s\n%s\n' "$LATEST" "$NEXT" | grep -v '^$' | sort -V | tail -1)
  echo -e "${RED}⚠️  官方已发布 ${NEWEST}，本补丁集适配版本是 ${TARGET} —— 需要处理：${NC}"
  echo ""
  echo "  1) 在本地升级官方到 ${NEWEST}："
  echo "     npm install -g @deepseek-ai/dsh@${NEWEST}"
  echo ""
  echo "  2) 检查官方是否已内置我们的功能（命中即说明该项可以退役）："
  echo "     grep -rl 'editLastPrompt' /path/to/@deepseek-ai/*/lib/"
  echo "     grep -rl 'recallHistory' /path/to/@deepseek-ai/*/lib/"
  echo ""
  echo "  3) 运行一键安装脚本尝试直接套补丁（含内置检测，若官方没大改则直接成功）："
  echo "     bash install-dsh-custom.sh -y"
  echo ""
  echo "  4) 若失败，按 ADAPTING.md 重新适配，并更新 versions.md"
fi
echo ""

# ── 4. 桌面版（Electron）补丁状态 ────────────────────────────────────────────
# 为什么单独一段：桌面版把运行时封在签名过的 app.asar 里，补丁打在一个**独立的副本**上
# （默认 ~/Applications/DeepSeek Harness Patched.app），而官方 app 走 nightly 自动更新。
# 官方一更新，副本就静默落后了 —— 这一段就是用来发现这件事的。
#
# 判据：桌面补丁脚本会在副本里写一份「来源指纹」（.dsh-desktop-patch.json，
# 记录克隆时官方 asar 的 sha256）。把它和**当前**官方 asar 的 sha256 一比即可。
echo -e "${YELLOW}── 桌面版（Electron）──────────────────────────────${NC}"
# 路径可用环境变量覆盖（便于多副本并存 / 自测）
SRC_APP="${DSH_DESKTOP_SRC_APP:-/Applications/DeepSeek Harness.app}"
DST_APP="${DSH_DESKTOP_DST_APP:-$HOME/Applications/DeepSeek Harness Patched.app}"
SRC_ASAR="$SRC_APP/Contents/Resources/app.asar"
DST_ASAR="$DST_APP/Contents/Resources/app.asar"
FP="$DST_APP/Contents/Resources/.dsh-desktop-patch.json"
MARKERS="$(dirname "$0")/tools/patch-markers.tsv"
ASAR_TOOL="$(dirname "$0")/desktop/dsh-desktop-asar.mjs"

sha256_of() {
  node -e 'const c=require("crypto"),f=require("fs");const h=c.createHash("sha256");const s=f.createReadStream(process.argv[1]);s.on("data",d=>h.update(d));s.on("end",()=>console.log(h.digest("hex")))' "$1" 2>/dev/null || echo ""
}

if [ ! -f "$SRC_ASAR" ]; then
  echo -e "  ${YELLOW}未安装桌面版（$SRC_APP 不存在），跳过${NC}"
elif [ ! -f "$DST_ASAR" ]; then
  echo -e "  ${YELLOW}尚未打补丁${NC} —— 需要时执行：${YELLOW}bash desktop/macos/dsh-desktop-patch.sh${NC}"
  echo -e "  ${DIM}（官方桌面版已安装，但 ~/Applications 下没有打过补丁的副本）${NC}"
else
  NOW_SRC=$(sha256_of "$SRC_ASAR")
  if [ -f "$FP" ]; then
    WAS_SRC=$(node -e 'try{console.log(require(process.argv[1]).sourceAsarSha256||"")}catch(e){console.log("")}' "$FP" 2>/dev/null || echo "")
    PATCHED_AT=$(node -e 'try{console.log(require(process.argv[1]).patchedAt||"")}catch(e){console.log("")}' "$FP" 2>/dev/null || echo "")
    echo -e "  补丁版: ${DST_APP}"
    echo -e "  打补丁时间: ${PATCHED_AT:-（未知）}"
    if [ -n "$WAS_SRC" ] && [ "$WAS_SRC" = "$NOW_SRC" ]; then
      echo -e "  ${GREEN}✅ 官方桌面版未变动，补丁版仍然对得上${NC}"
    else
      echo -e "  ${RED}⚠️  官方桌面版已更新（asar 内容变了），补丁版已落后${NC}"
      echo -e "     打补丁时的官方 asar: ${DIM}${WAS_SRC:-未知}${NC}"
      echo -e "     当前官方 asar      : ${DIM}${NOW_SRC}${NC}"
      echo -e "     ${YELLOW}处理：重跑 bash desktop/macos/dsh-desktop-patch.sh${NC}"
      echo -e "     ${DIM}（若补丁不再零 fuzz 应用，需先按 ADAPTING.md 重新适配 patches/）${NC}"
    fi
  else
    echo -e "  ${YELLOW}补丁版存在，但没有来源指纹（可能由旧版脚本产出）${NC}"
    echo -e "     建议重跑一次：${YELLOW}bash desktop/macos/dsh-desktop-patch.sh${NC}"
  fi

  # 逐项核对功能标记 —— 证明补丁「真的生效」，而不只是文件被换过
  if [ -f "$MARKERS" ] && [ -f "$ASAR_TOOL" ]; then
    miss=0; total=0
    while IFS=$'\t' read -r rel marker; do
      case "$rel" in ''|\#*) continue ;; esac
      [ -n "${marker:-}" ] || continue
      total=$((total+1))
      n=$(node "$ASAR_TOOL" cat "$DST_ASAR" "dsh/node_modules/@deepseek-ai/$rel" 2>/dev/null | grep -cF -- "$marker" 2>/dev/null || true)
      [ "${n:-0}" -ge 1 ] 2>/dev/null || { miss=$((miss+1)); echo -e "  ${RED}✗${NC} 标记未命中: $rel （$marker）"; }
    done < "$MARKERS"
    if [ "$miss" -eq 0 ]; then
      echo -e "  ${GREEN}✅ 补丁版功能标记 ${total}/${total} 全部命中${NC}"
    else
      echo -e "  ${RED}⚠️  补丁版有 $miss/$total 个标记未命中 —— 补丁可能已被官方更新覆盖${NC}"
      echo -e "     处理：${YELLOW}bash desktop/macos/dsh-desktop-patch.sh${NC}"
    fi
  fi
fi
echo ""
