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

# 本仓库 main 分支固定适配的 DSH 版本（README「多版本支持」：其他版本 checkout 对应 tag）
TARGET="0.2.0-rc.2"

# 1. 本地已装版本
#
# ⚠️ 不能只用 `npm root -g`：它只反映**当前 PATH 上那个 npm**。DSH 常被装在自建目录
#    （如 ~/.local/node-v24/lib/node_modules/），而工具/CI/沙箱环境里的 `npm root -g`
#    往往指向**另一个** node → 明明装了却报「未找到本地 DSH」，把最关键的「本机版本」
#    变成空白。下面四条依次尝试，与 patch-all.sh 保持同一套探测。
find_cli_dir() {
  local d="" g="" cand="" exe="" real=""

  # 0) 调用方已探测过（patch-all.sh 会 export DSH_DIR 供子脚本复用）
  if [ -n "${DSH_DIR:-}" ] && [ -d "$DSH_DIR" ]; then printf '%s' "$DSH_DIR"; return 0; fi

  # 1) 当前 PATH 上那个 npm 的全局根
  g=$(npm root -g 2>/dev/null || echo "")
  if [ -n "$g" ] && [ -d "$g/@deepseek-ai/dsh" ]; then d="$g/@deepseek-ai/dsh"; fi

  # 2) 让 node 自己解析（尊重 node_modules 逐级查找）
  if [ -z "$d" ]; then
    d=$(node -e "try{console.log(require.resolve('@deepseek-ai/dsh/package.json').replace(/[\\\\/]package\.json\$/,''))}catch(e){console.log('')}" 2>/dev/null || echo "")
  fi

  # 3) ⭐ 最可靠：顺着用户**实际在用**的 `dsh` 可执行文件反推
  if [ -z "$d" ]; then
    exe=$(command -v dsh 2>/dev/null || echo "")
    if [ -n "$exe" ]; then
      # macOS 自带 readlink 没有 -f，用 node 解析符号链接
      real=$(node -e "try{console.log(require('fs').realpathSync(process.argv[1]))}catch(e){console.log('')}" "$exe" 2>/dev/null || echo "")
      case "$real" in
        */@deepseek-ai/dsh/lib/bin.js) d="${real%/lib/bin.js}" ;;
        */@deepseek-ai/dsh/*)          d="${real%%/@deepseek-ai/dsh/*}/@deepseek-ai/dsh" ;;
      esac
    fi
  fi

  # 4) 兜底：扫常见安装位置
  if [ -z "$d" ]; then
    for cand in /usr/local/lib/node_modules \
                "$HOME/.local/lib/node_modules" \
                "$HOME"/.local/*/lib/node_modules \
                "$HOME"/.nvm/versions/node/*/lib/node_modules \
                "$HOME"/.volta/tools/image/node/*/lib/node_modules \
                "${APPDATA:-/nonexistent}/npm/node_modules" \
                "${LOCALAPPDATA:-/nonexistent}/npm/node_modules"; do
      [ -d "$cand/@deepseek-ai/dsh" ] || continue
      d="$cand/@deepseek-ai/dsh"; break
    done
  fi

  printf '%s' "$d"
}

LOCAL=""
CLI_DIR="$(find_cli_dir || true)"
if [ -n "$CLI_DIR" ] && [ -f "$CLI_DIR/package.json" ]; then
  # 用 argv 传路径：Windows 下 npm root 返回反斜杠路径，
  # 直接拼进 require('...') 会被 JS 吞掉转义导致抛错；且必须 `|| true`，
  # 否则命令替换返回非 0 会让 set -e 直接终止整个脚本（此前 Windows 上静默失败）。
  LOCAL=$(node -e "console.log(require(process.argv[1]).version)" "$CLI_DIR/package.json" 2>/dev/null || echo "")
fi
if [ -z "$LOCAL" ]; then LOCAL="(未找到本地 DSH)"; fi
if [ "$LOCAL" = "(未找到本地 DSH)" ]; then
  echo -e "${GREEN}本地已装 DSH：${NC}${LOCAL}"
  # 目录找到了却读不出版本，通常是 node 不在 PATH 上 —— 单独提示，别让人以为「没装」
  # echo -e 会把反斜杠路径里的 \n \U 当转义符 → 显示前统一成正斜杠
  [ -n "$CLI_DIR" ] && echo -e "  ${DIM}目录已定位但读不出版本（node 不可用？）：${CLI_DIR//\\//}${NC}"
else
  echo -e "${GREEN}本地已装 DSH：${NC}${LOCAL} ${DIM}${CLI_DIR//\\//}${NC}"
fi

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

# 分支 1/2 只比较了「补丁集 vs 官方频道」——本机停在旧版时那两支直接打绿灯，
# 看不出本机已经落后于仓库基线，所以这里单独再报一次。
case "$LOCAL" in
  "$TARGET"|"(未找到本地 DSH)") ;;
  *)
    echo -e "${YELLOW}⚠️  本机已装 ${LOCAL}，仓库基线是 ${TARGET}${NC}"
    echo -e "   跟进基线：${YELLOW}npm install -g @deepseek-ai/dsh@${TARGET}${NC}（补丁零改动可直接套）"
    echo -e "   或留在本机版本：${YELLOW}git checkout v${LOCAL}${NC}"
    ;;
esac
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

fp_field() { # $1=指纹文件 $2=字段名
  node -e 'try{console.log(require(process.argv[1])[process.argv[2]]||"")}catch(e){console.log("")}' "$1" "$2" 2>/dev/null || echo ""
}

# 逐项核对功能标记 —— 证明补丁「真的生效」，而不只是文件被换过。
# $1=asar 路径 $2=结果前缀（如「补丁版」）
verify_markers() {
  local asar="$1" label="$2"
  [ -f "$MARKERS" ] && [ -f "$ASAR_TOOL" ] || return 0
  local miss=0 total=0 rel marker n
  while IFS=$'\t' read -r rel marker; do
    # Windows 下 git 可能把 tsv 检出成 CRLF，行尾 \r 会粘在标记上导致 grep 永远不命中
    rel="${rel%$'\r'}"; marker="${marker%$'\r'}"
    case "$rel" in ''|\#*) continue ;; esac
    [ -n "${marker:-}" ] || continue
    total=$((total+1))
    n=$(node "$ASAR_TOOL" cat "$asar" "dsh/node_modules/@deepseek-ai/$rel" 2>/dev/null | grep -cF -- "$marker" 2>/dev/null || true)
    [ "${n:-0}" -ge 1 ] 2>/dev/null || { miss=$((miss+1)); echo -e "  ${RED}✗${NC} 标记未命中: $rel （$marker）"; }
  done < "$MARKERS"
  if [ "$miss" -eq 0 ] && [ "$total" -gt 0 ]; then
    echo -e "  ${GREEN}✅ ${label}功能标记 ${total}/${total} 全部命中${NC}"
  elif [ "$total" -gt 0 ]; then
    echo -e "  ${RED}⚠️  ${label}有 $miss/$total 个标记未命中 —— 补丁可能已被官方更新覆盖${NC}"
    echo -e "     处理：${YELLOW}node desktop/windows/apply-desktop-asar-patches.js${NC}（Windows）/ ${YELLOW}bash desktop/macos/dsh-desktop-patch.sh${NC}（macOS）"
  fi
}

# ── 平台分派 ────────────────────────────────────────────────────────────────
# Windows：**就地**打补丁（不复制副本），asar 在安装目录里，自动更新会直接覆盖它。
# macOS  ：双 app 模型（官方 app + ~/Applications 打过补丁的副本），见下方分支。
WIN_ASAR="${LOCALAPPDATA:-}/Programs/DeepSeek Harness/resources/app.asar"

if [ -n "${LOCALAPPDATA:-}" ] && [ -f "$WIN_ASAR" ]; then
  W_FP="$(dirname "$WIN_ASAR")/.dsh-desktop-patch.json"
  echo -e "  安装路径: ${DIM}${WIN_ASAR}${NC}"
  if [ -f "$W_FP" ]; then
    NOW_SELF=$(sha256_of "$WIN_ASAR")
    WAS_PATCHED=$(fp_field "$W_FP" patchedAsarSha256)
    PATCHED_AT=$(fp_field "$W_FP" patchedAt)
    echo -e "  打补丁时间: ${PATCHED_AT:-（未知）}"
    if [ -n "$WAS_PATCHED" ] && [ "$WAS_PATCHED" = "$NOW_SELF" ]; then
      echo -e "  ${GREEN}✅ 当前 asar 与打补丁时的产出逐字节一致（补丁未被覆盖）${NC}"
    else
      echo -e "  ${RED}⚠️  当前 asar 与打补丁时的产出不同 —— 很可能已被官方自动更新覆盖${NC}"
      echo -e "     打补丁时: ${DIM}${WAS_PATCHED:-未知}${NC}"
      echo -e "     当前      : ${DIM}${NOW_SELF}${NC}"
      echo -e "     ${YELLOW}处理：node desktop/windows/apply-desktop-asar-patches.js${NC}"
    fi
  else
    echo -e "  ${YELLOW}没有来源指纹（本次安装早于指纹功能）—— 以功能标记核对为准${NC}"
    echo -e "     重跑安装即可补写指纹：${YELLOW}node desktop/windows/apply-desktop-asar-patches.js${NC}"
  fi
  verify_markers "$WIN_ASAR" "补丁版"
elif [ ! -f "$SRC_ASAR" ]; then
  echo -e "  ${YELLOW}未安装桌面版（$SRC_APP 不存在），跳过${NC}"
elif [ ! -f "$DST_ASAR" ]; then
  echo -e "  ${YELLOW}尚未打补丁${NC} —— 需要时执行：${YELLOW}bash desktop/macos/dsh-desktop-patch.sh${NC}"
  echo -e "  ${DIM}（官方桌面版已安装，但 ~/Applications 下没有打过补丁的副本）${NC}"
else
  NOW_SRC=$(sha256_of "$SRC_ASAR")
  if [ -f "$FP" ]; then
    WAS_SRC=$(fp_field "$FP" sourceAsarSha256)
    PATCHED_AT=$(fp_field "$FP" patchedAt)
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

  verify_markers "$DST_ASAR" "补丁版"
fi
echo ""
