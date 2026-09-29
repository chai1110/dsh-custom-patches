#!/bin/bash
# patch-all.sh — 一次把本仓库的补丁打到「两面」，并对两面做功能标记交叉核对。
#
# ─────────────────────────── 为什么需要这个脚本 ───────────────────────────
# 本仓库的补丁要打到两个**完全不同的目标**上：
#
#   A. CLI 侧（浏览器 + VS Code 共用）
#      → 目标是 npm 全局包 `node_modules/@deepseek-ai/**`，普通 `patch` 即可。
#      → 由 apply-dsh-patches.sh 负责。
#
#   B. 桌面版（Electron）
#      → 目标是签名过的 `app.asar` 内部，必须做 asar 外科手术。
#      → 由 desktop/macos/dsh-desktop-patch.sh 负责。
#
# 两边用的是**同一套补丁文件**（patches/**），但目标不同、脚本不同。
# 以前要分别跑两个脚本、再人工确认「两边是不是都真的生效了」——
# 这个脚本把这件事收成一条命令，并自动输出交叉核对矩阵。
#
# ──────────────────────────────── 用法 ────────────────────────────────
#   bash patch-all.sh                       # 两面都打（默认）
#   bash patch-all.sh --check               # 只核对现状，不修改任何东西
#   bash patch-all.sh --cli-only            # 只打 CLI 侧
#   bash patch-all.sh --desktop-only        # 只打桌面侧
#   bash patch-all.sh --desktop-app "<路径>" # 指定要核对的桌面 app（默认补丁版）
#
# 退出码：0 = 两面标记全绿；1 = 有标记缺失（说明某面没打上或已被覆盖）。
#
# ⚠️ 只支持 macOS 桌面版。Windows 桌面版是独立模块，见 desktop/windows/README.md。

set -uo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; DIM='\033[2m'; NC='\033[0m'
say() { printf "%b\n" "$*"; }

REPO="$(cd "$(dirname "$0")" && pwd)"
MARKERS_FILE="$REPO/tools/patch-markers.tsv"
ASAR_TOOL="$REPO/desktop/dsh-desktop-asar.mjs"
DESKTOP_PATCH="$REPO/desktop/macos/dsh-desktop-patch.sh"
CLI_PATCH="$REPO/apply-dsh-patches.sh"

DO_CLI=1; DO_DESKTOP=1; CHECK_ONLY=0
DESKTOP_APP="$HOME/Applications/DeepSeek Harness Patched.app"

while [ $# -gt 0 ]; do
  case "$1" in
    --check)        CHECK_ONLY=1 ;;
    --cli-only)     DO_DESKTOP=0 ;;
    --desktop-only) DO_CLI=0 ;;
    --desktop-app)  shift; DESKTOP_APP="${1:-}" ;;
    -h|--help)      sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) say "${RED}未知参数: $1${NC}（用 --help 看用法）"; exit 2 ;;
  esac
  shift
done

[ -f "$MARKERS_FILE" ] || { say "${RED}缺少 $MARKERS_FILE${NC}"; exit 1; }

# ────────────────────── 1. 定位 CLI 侧 DSH 安装目录 ──────────────────────
# 四条路径依次尝试，覆盖常见安装方式（含 nvm / volta / 自建 node 目录）：
#   ① npm root -g           —— 最标准，但取决于 PATH 上的是哪个 npm
#   ② require.resolve       —— node 解析得到的那个
#   ③ 顺着 `dsh` 可执行文件反推 —— **最可靠**：用户实际在用的就是这一个
#   ④ 常见全局目录扫描       —— 兜底
# ⚠️ 踩过的坑：本机 DSH 装在 ~/.local/node-v24/lib/node_modules（自建 node 目录），
#    `npm root -g` 在工具环境里解析到另一个 node，结果探测不到。故 ③④ 必不可少。
find_cli_dir() {
  local d="" g="" cand="" exe="" real=""

  g=$(npm root -g 2>/dev/null || echo "")
  if [ -n "$g" ] && [ -d "$g/@deepseek-ai/dsh" ]; then d="$g/@deepseek-ai/dsh"; fi

  if [ -z "$d" ]; then
    d=$(node -e "try{console.log(require.resolve('@deepseek-ai/dsh/package.json').replace(/[\\\\/]package\.json\$/,''))}catch(e){console.log('')}" 2>/dev/null)
  fi

  if [ -z "$d" ]; then
    exe=$(command -v dsh 2>/dev/null || echo "")
    if [ -n "$exe" ]; then
      # macOS 自带 readlink 没有 -f，用 node 解析符号链接
      real=$(node -e "try{console.log(require('fs').realpathSync(process.argv[1]))}catch(e){console.log('')}" "$exe" 2>/dev/null)
      case "$real" in
        */@deepseek-ai/dsh/lib/bin.js) d="${real%/lib/bin.js}" ;;
        */@deepseek-ai/dsh/*)          d="${real%%/@deepseek-ai/dsh/*}/@deepseek-ai/dsh" ;;
      esac
    fi
  fi

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

CLI_DIR="$(find_cli_dir)"
CLI_PLUGIN_ROOT="${CLI_DIR:+$CLI_DIR/node_modules/@deepseek-ai}"
# 显式导出，让 apply-dsh-patches.sh 复用同一份探测结果（它自己探测会漏掉自建 node 目录）
[ -n "$CLI_DIR" ] && export DSH_DIR="$CLI_DIR"

# ─────────────────────────── 2. 施加补丁（可选） ───────────────────────────
if [ "$CHECK_ONLY" -eq 1 ]; then
  say "${DIM}（--check：只核对，不修改任何东西）${NC}"
else
  if [ "$DO_CLI" -eq 1 ]; then
    say ""
    say "${YELLOW}════════ A. CLI 侧（浏览器 + VS Code）════════${NC}"
    if [ -f "$CLI_PATCH" ]; then
      bash "$CLI_PATCH" || say "${RED}CLI 侧补丁脚本返回非 0${NC}"
    else
      say "${RED}缺少 $CLI_PATCH${NC}"
    fi
  fi

  if [ "$DO_DESKTOP" -eq 1 ]; then
    say ""
    say "${YELLOW}════════ B. 桌面版（Electron / app.asar）════════${NC}"
    if [ "$(uname -s)" != "Darwin" ]; then
      say "${YELLOW}非 macOS，跳过桌面版（Windows 见 desktop/windows/README.md）${NC}"
    elif [ -f "$DESKTOP_PATCH" ]; then
      bash "$DESKTOP_PATCH" || say "${RED}桌面版补丁脚本返回非 0${NC}"
    else
      say "${RED}缺少 $DESKTOP_PATCH${NC}"
    fi
  fi
fi

# ───────────────────── 3. 交叉核对：两面各算一遍标记 ─────────────────────
DESKTOP_ASAR="$DESKTOP_APP/Contents/Resources/app.asar"
have_cli=0; [ -n "$CLI_PLUGIN_ROOT" ] && [ -d "$CLI_PLUGIN_ROOT" ] && have_cli=1
have_desktop=0; [ -f "$DESKTOP_ASAR" ] && [ -f "$ASAR_TOOL" ] && have_desktop=1

count_cli() {
  [ "$have_cli" -eq 1 ] || { printf 'n/a'; return; }
  local f="$CLI_PLUGIN_ROOT/$1"
  [ -f "$f" ] || { printf 'missing'; return; }
  grep -cF -- "$2" "$f" 2>/dev/null || printf '0'
}
count_desktop() {
  [ "$have_desktop" -eq 1 ] || { printf 'n/a'; return; }
  local n
  n=$(node "$ASAR_TOOL" cat "$DESKTOP_ASAR" "dsh/node_modules/@deepseek-ai/$1" 2>/dev/null | grep -cF -- "$2" 2>/dev/null || printf '0')
  printf '%s' "$n"
}

say ""
say "${YELLOW}════════ C. 功能标记交叉核对 ════════${NC}"
say "  CLI 侧目标: ${CLI_PLUGIN_ROOT:-（未找到 DSH 安装）}"
say "  桌面版目标: ${DESKTOP_ASAR}"
say "  标记来源  : tools/patch-markers.tsv"
say ""
printf '  %-46s %-10s %-10s %s\n' "目标文件" "CLI 侧" "桌面版" "判定"
printf '  %s\n' "────────────────────────────────────────────────────────────────────────────"

fails=0; rows=0
while IFS=$'\t' read -r rel marker; do
  case "$rel" in ''|\#*) continue ;; esac
  [ -n "${marker:-}" ] || continue
  rows=$((rows+1))
  c=$(count_cli "$rel" "$marker")
  d=$(count_desktop "$rel" "$marker")

  # 判定：该面「有目标」时必须命中；该面「没目标」记 n/a，不计失败
  verdict=""
  if [ "$c" = "n/a" ] && [ "$d" = "n/a" ]; then verdict="${DIM}两面均未检测到目标${NC}"
  elif [ "$c" = "n/a" ]; then
    if [ "$d" -ge 1 ] 2>/dev/null; then verdict="${GREEN}桌面版 ✓（CLI 未检测）${NC}"; else verdict="${RED}桌面版 ✗${NC}"; fails=$((fails+1)); fi
  elif [ "$d" = "n/a" ]; then
    if [ "$c" -ge 1 ] 2>/dev/null; then verdict="${GREEN}CLI ✓（桌面未检测）${NC}"; else verdict="${RED}CLI ✗${NC}"; fails=$((fails+1)); fi
  else
    ok_c=0; ok_d=0
    [ "$c" -ge 1 ] 2>/dev/null && ok_c=1
    [ "$d" -ge 1 ] 2>/dev/null && ok_d=1
    if [ "$ok_c" -eq 1 ] && [ "$ok_d" -eq 1 ]; then verdict="${GREEN}✓ 两面一致${NC}"
    elif [ "$ok_c" -eq 1 ]; then verdict="${YELLOW}⚠ 仅 CLI 生效${NC}"; fails=$((fails+1))
    elif [ "$ok_d" -eq 1 ]; then verdict="${YELLOW}⚠ 仅桌面版生效${NC}"; fails=$((fails+1))
    else verdict="${RED}✗ 两面都未生效${NC}"; fails=$((fails+1))
    fi
  fi
  printf '  %-46s %-10s %-10s %b\n' "$rel" "$c" "$d" "$verdict"
done < "$MARKERS_FILE"

printf '  %s\n' "────────────────────────────────────────────────────────────────────────────"
say "  共 $rows 项，$fails 项异常"
say ""

if [ "$fails" -eq 0 ]; then
  say "${GREEN}✅ 全部通过。${NC}"
  if [ "$CHECK_ONLY" -eq 0 ]; then
    say "   下一步："
    say "     • CLI 侧（浏览器）：${YELLOW}pkill -f 'dsh web'; dsh web${NC} 然后硬刷新页面"
    say "     • 桌面版：${YELLOW}open \"$DESKTOP_APP\"${NC}（先退出官方版，二者共用 user-data + 端口 19387）"
  fi
  exit 0
else
  say "${RED}⚠️  有 $fails 项异常。${NC}"
  say "   常见原因与处理："
  say "     • 某面标记全缺 → 该面没打补丁，或官方升级把它覆盖了（桌面版走 nightly，需重跑）"
  say "     • 「仅 CLI 生效」 → 桌面版补丁被官方更新覆盖，重跑 desktop/macos/dsh-desktop-patch.sh"
  say "     • 标记整体失效（官方原版也开始出现）→ 官方已内置该功能，对应补丁可退役，更新 tools/patch-markers.tsv"
  say "     • 详见 ADAPTING.md 与 desktop/README.md"
  exit 1
fi
