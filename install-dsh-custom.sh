#!/bin/bash
# =============================================================================
# install-dsh-custom.sh -- DSH custom patch one-click installer
#   (enhances apply-dsh-patches.sh with version diagnosis + built-in detection)
#
# Compared to apply-dsh-patches.sh, it:
#   1. Reads local version + queries npm latest, gives version diagnosis
#   2. For each patch, checks whether the official build already contains the
#      feature (greps a marker in the target file) -- if so, skips that patch
#      to avoid duplication/conflict
#   3. backup (first time) + dry-run + apply + verify, all with colored logs
#  4. Usage: bash install-dsh-custom.sh [-y]    (-y skips interactive confirm; this branch is pinned to 0.2.0-rc.1, no version argument)
#
# Supports BOTH installation layouts:
#   A. global npm install  (default): finds DSH in global node_modules
#        target: <dsh>/node_modules/@deepseek-ai/<rel>
#   B. source / monorepo    (DSH_SOURCE set): DSH built from source (pnpm + tsdown)
#        target: <DSH_SOURCE>/packages/<source_rel>
#        To use, set DSH_SOURCE to your deepseek-harness source root, e.g.
#        export DSH_SOURCE=/path/to/deepseek-harness
#
# Adapted versions: 0.2.0-rc.1 (default on this branch) / 0.1.7-rc.2 / 0.1.2-rc.1 / 0.1.1-rc.2 / 0.1.0-rc.8 / 0.1.0-rc.7 (see versions.md)
# =============================================================================
set -u

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC} $*"; }
info() { echo -e "${CYAN}[i]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[x]${NC} $*"; }

# 本仓库（version/0.2.0-rc.1 分支）固定适配的 DSH 版本：0.2.0-rc.1。
# 其他 DSH 版本用户：请 checkout 对应版本分支/tag（见 README「多版本支持」）。
TARGET_VERSION="0.2.0-rc.1"

ASK=1
for arg in "$@"; do
  case "$arg" in
    -y) ASK=0 ;;
    *)
      err "Unknown argument: $arg"
      echo "  Usage: bash install-dsh-custom.sh [-y]"
      echo "  （本分支固定适配 DSH 0.2.0-rc.1；其他版本请 checkout 对应分支/tag）"
      exit 1
      ;;
  esac
done

# Entries: rel | patch | marker | source_rel
#   rel         = path relative to the npm install plugin root (node_modules/@deepseek-ai/<rel>)
#   patch       = path to the .patch file inside this repo
#   marker      = feature marker used for "official already built-in" detection (empty = skip)
#   source_rel  = path relative to <source>/packages, used in source/monorepo layout
# 0.2.0-rc.1：**补丁集零改动** —— 官方这次没碰我们 9 个补丁的任何一个锚点区，
# 实测 `patch -F 0`（零模糊）9/9 干净套用、实套 + node --check 9/9 通过。
# 官方在 agent-loop 里新增的 ToolCallRecovery（修「工具调度异常后对话无法继续」）
# 与本补丁的 `__stack` 诊断 + `user/message` 去重**不是同一件事**，故保留。
# 0.1.7-rc.2：归档相关补丁**全部退役** —— 官方已原生提供完整链路
# （archiveSession / unarchiveSession + 侧边栏三态筛选 + 行内「取消归档」+
#  搜索恢复 + 归档提示的 undo），我们不再重复实现，避免多此一举。
# 更早退役的 client-connection 同因。当前补丁集只保留官方仍缺的能力。
# rc.1 (0.1.2-rc.1) 是架构重构版：host-apiproxy/client-runtime 已移除，
# 编辑重发改由 dsh-api-session-controller + dsh-client-ui-chat 承载；
# 注意 0.1.2 新增 dsh-api-remotes：浏览器端 remote.session 方法表 = 其
# lib/client.js 内嵌的各包 typert 模型冻结副本（ModuleLoader bundle），
# 给 @Remote 增删方法必须同步补它，否则浏览器端永远 not a function。
FILES=(
  "dsh-api-session-controller/lib/index.js|patches/api-session-controller/dsh-api-session-controller-lib-index.js.patch|async editLastPrompt|api/session-controller/lib/index.js"
  "dsh-api-session-controller/lib/client.js|patches/api-session-controller/dsh-api-session-controller-lib-client.js.patch|async editLastPrompt|api/session-controller/lib/client.js"
  "dsh-api-session-controller/lib/typert.host.js|patches/api-session-controller/dsh-api-session-controller-lib-typert-host.js.patch|editLastPrompt|api/session-controller/lib/typert.host.js"
  "dsh-api-session-controller/lib/typert.remote-client.js|patches/api-session-controller/dsh-api-session-controller-lib-typert-remote-client.js.patch|editLastPrompt|api/session-controller/lib/typert.remote-client.js"
  "dsh-api-remotes/lib/client.js|patches/api-remotes/dsh-api-remotes-lib-client.js.patch|editLastPrompt|api/remotes/lib/client.js"
  "dsh-agent-loop/lib/index.js|patches/agent-loop/dsh-agent-loop-lib-index.js.patch|tailEvent?.type === \"user/message\"|core/agent-loop/lib/index.js"
  "dsh-compaction-basic/lib/index.js|patches/compaction-basic/dsh-compaction-basic-lib-index.js.patch|compactionBackoffDelay|core/compaction-basic/lib/index.js"
  "dsh-client-ui-conversation/lib/client.js|patches/client-ui-conversation/dsh-client-ui-conversation-lib-client.js.patch|recallHistory|client/ui-conversation/lib/client.js"
  "dsh-client-ui-chat/lib/client.js|patches/client-ui-chat/dsh-client-ui-chat-lib-client.js.patch|message.editPrompt|client/ui-chat/lib/client.js"
)


SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo -e "${CYAN}============================================================${NC}"
echo -e "${CYAN}   DSH custom enhancements: one-click installer (${TARGET_VERSION})${NC}"
echo -e "${CYAN}============================================================${NC}"
echo ""

# ---------- 1. locate DSH (npm layout) or source root (monorepo layout) ----------
LAYOUT="npm"
DSH_DIR=""
SOURCE_ROOT=""

if [ -n "${DSH_SOURCE:-}" ]; then
  # source / monorepo layout requested via environment variable
  SOURCE_ROOT="$(cd "$DSH_SOURCE" 2>/dev/null && pwd || echo "")"
  if [ -z "$SOURCE_ROOT" ] || [ ! -d "$SOURCE_ROOT/packages" ]; then
    err "DSH_SOURCE=$DSH_SOURCE is not a valid DSH source root (no 'packages/' dir)."
    exit 1
  fi
  LAYOUT="source"
  info "Using source/monorepo layout (DSH_SOURCE=$SOURCE_ROOT)"
else
  info "Locating DSH global install dir (npm root -g first, cross-platform)..."
  # 方法 A：npm root -g（最可靠——任何平台返回正确全局目录）
  GLOBAL_ROOT=$(npm root -g 2>/dev/null || echo "")
  DSH_DIR=""
  if [ -n "$GLOBAL_ROOT" ] && [ -d "$GLOBAL_ROOT/@deepseek-ai/dsh" ]; then
    DSH_DIR="$GLOBAL_ROOT/@deepseek-ai/dsh"
  fi
  # 方法 B：require.resolve 兜底（[\\/] 兼容 Windows 反斜杠路径）
  if [ -z "$DSH_DIR" ]; then
    DSH_DIR=$(node -e "try{console.log(require.resolve('@deepseek-ai/dsh/package.json').replace(/[\\\\/]package\.json$/,''))}catch(e){console.log('')}" 2>/dev/null)
  fi
  # 方法 C：常见全局目录扫描兜底（含 Windows %APPDATA%/%LOCALAPPDATA%）
  # ⚠️ 本脚本是 set -u：$APPDATA / $LOCALAPPDATA 在 macOS / Linux 上**未定义**，
  # 直接引用会让脚本以「unbound variable」中止（用户看到的是 shell 报错，
  # 而不是下面那句友好提示）。故一律用 ${VAR:-} 先判空。
  # 同时不用数组，改为逐目录探测 + 命中即 break，POSIX 安全。
  # （更正 2026-09-29：此前注释写的理由是「bash 3.2 下 ${#arr[@]} 空数组会报未绑定」，
  #  实测**说反了** —— /bin/bash 3.2.57 + set -u 下 ${#arr[@]} 是安全的（输出 0）；
  #  真正会报 unbound variable 的是**展开**空数组，即 "${arr[@]}" / ${arr[@]}。
  #  代码没问题，是理由写错了，故此处只保留「不用数组」的结论。）
  if [ -z "$DSH_DIR" ]; then
    for _base in /usr/local/lib/node_modules "$HOME/.local/lib/node_modules" \
                 "${APPDATA:-/nonexistent}/npm/node_modules" \
                 "${LOCALAPPDATA:-/nonexistent}/npm/node_modules"; do
      if [ -d "$_base" ]; then
        DSH_DIR=$(find "$_base" -maxdepth 4 -name "dsh" -path "*/@deepseek-ai/*" -type d 2>/dev/null | head -1)
        if [ -n "$DSH_DIR" ]; then break; fi
      fi
    done
  fi
  if [ -z "$DSH_DIR" ]; then
    err "Cannot find DSH global install dir."
    echo "  If you installed DSH from source (monorepo), set DSH_SOURCE to the source root:"
    echo "    export DSH_SOURCE=/path/to/deepseek-harness   # then rerun"
    echo "  Otherwise install @deepseek-ai/dsh globally first: npm install -g @deepseek-ai/dsh"
    echo "  Windows 用户：npm root -g 应输出您的全局 node_modules 路径；若在上面找不到，请检查 %APPDATA%\\npm"
    exit 1
  fi
  ok "Found DSH: $DSH_DIR"
fi

# Compute the real target path for one entry under the active layout.
# args: rel source_rel
target_for() {
  local rel="$1" srel="$2"
  if [ "$LAYOUT" = "source" ]; then
    echo "$SOURCE_ROOT/packages/$srel"
  else
    echo "$DSH_DIR/node_modules/@deepseek-ai/$rel"
  fi
}

# ---------- 2. version diagnosis ----------
if [ "$LAYOUT" = "npm" ]; then
  VERSION=$(node -e "console.log(require('$DSH_DIR/package.json').version)" 2>/dev/null)
  echo -e "    local version: ${YELLOW}${VERSION:-unknown}${NC}"
  # 两个频道都要看：RC 常常只发在 next 上，而 `npm view <pkg> version` 只返回 latest。
  # 只看 latest 会把「官方 next 比本地新」误报成「官方有更新版本 0.1.7-rc.2」，方向完全反了。
  LATEST=$(npm view @deepseek-ai/dsh dist-tags.latest 2>/dev/null || echo "")
  NEXT=$(npm view @deepseek-ai/dsh dist-tags.next 2>/dev/null || echo "")
  if [ -n "$LATEST" ] || [ -n "$NEXT" ]; then
    echo -e "    npm latest:    ${YELLOW}${LATEST:-（无）}${NC}"
    echo -e "    npm next:      ${YELLOW}${NEXT:-（无）}${NC}"
  else
    warn "Cannot query npm dist-tags (network/npm source). Continuing."
  fi
  if [ "$VERSION" != "$TARGET_VERSION" ]; then
    err "Version mismatch: patches target $TARGET_VERSION, current is $VERSION"
    echo ""
    echo "  Choose one:"
    echo "    a) Old-version user: check out the matching release of THIS repo, then rerun:"
    echo "       git checkout v$VERSION && bash install-dsh-custom.sh -y"
    echo "    b) Upgrade to the target version:"
    echo "       npm install -g @deepseek-ai/dsh@$TARGET_VERSION"
    echo "    c) If official upgraded beyond this repo, re-adapt per ADAPTING.md first."
    exit 1
  fi
  if [ -n "$NEXT" ] && [ "$NEXT" = "$TARGET_VERSION" ] && [ "$LATEST" != "$TARGET_VERSION" ]; then
    info "This build tracks the official \"next\" channel (latest is $LATEST)."
    info "Plain \"npm i -g @deepseek-ai/dsh\" installs $LATEST, not $TARGET_VERSION."
  fi
else
  echo -e "    source layout: skip npm version check"
  warn "Please make sure your source tree corresponds to the codebase for $TARGET_VERSION"
  warn "(patches apply to the built lib/ artifacts under packages/*)."
fi
echo ""

# ---------- 3. built-in detection ----------
APPLY=()     # to apply: rel|patch|source_rel
SKIPPED=()   # skipped because built-in: rel|marker
echo -e "${CYAN}--- built-in detection ---${NC}"
for entry in "${FILES[@]}"; do
  rel="${entry%%|*}"; rest="${entry#*|}"
  patch="${rest%%|*}"; rest="${rest#*|}"
  marker="${rest%%|*}"; srel="${rest#*|}"
  full="$(target_for "$rel" "$srel")"
  if [ ! -f "$full" ]; then
    warn "Target missing, skip: $rel  ($full)"
    continue
  fi
  if [ -n "$marker" ] && grep -qF "$marker" "$full" 2>/dev/null; then
    warn "Already contains marker \"$marker\" -> skip: $rel"
    SKIPPED+=("$rel|$marker")
  else
    APPLY+=("$rel|$patch|$srel")
  fi
done

[ ${#SKIPPED[@]} -gt 0 ] && echo ""
[ ${#APPLY[@]} -eq 0 ] && { info "All features already present (built-in or applied). Nothing to do."; exit 0; }

echo ""
echo -e "${CYAN}--- patches to apply (${#APPLY[@]}) ---${NC}"
for e in "${APPLY[@]}"; do info "will apply: ${e%%|*}"; done
echo ""

if [ "$ASK" = "1" ]; then
  read -r -p "Proceed to apply the patches above? [y/N] " ans
  case "$ans" in y|Y|yes|YES) ;; *) echo "Cancelled."; exit 1 ;; esac
fi

# ---------- 4. backup + dry-run + apply + verify ----------
OK=0; FAIL=0
for entry in "${APPLY[@]}"; do
  rel="${entry%%|*}"; rest="${entry#*|}"
  patch="${rest%%|*}"; srel="${rest#*|}"
  full_path="$(target_for "$rel" "$srel")"
  patch_file="$SCRIPT_DIR/$patch"

  if [ ! -f "$patch_file" ]; then
    err "Patch file missing: $patch_file"; FAIL=$((FAIL+1)); continue
  fi

  # backup (first time)
  if [ ! -f "$full_path.bak" ]; then
    cp "$full_path" "$full_path.bak" && ok "backed up: $rel.bak"
  fi

  # if already applied -> skip
  # 注意 -F 0：patch 默认 fuzz=2，会容忍上下文行不匹配（＝可能在错误的锚点上"成功"）。
  # 零模糊才能真正证明锚点未被上游改动（见 ADAPTING.md 铁律 3）。
  # 本脚本是推荐入口，必须与 apply-dsh-patches.sh 保持同一严格度。
  #
  # ⚠️⚠️ 顺序不能反：**反向 dry-run 必须放第一位**（理由详见 apply-dsh-patches.sh 同处注释）。
  # 纯插入型补丁套用后正向 dry-run 仍会成功，`patch -N` 挡不住，会重复套用。
  # 本脚本另有一层「功能标记」预筛（上面 built-in detection），通常到不了这里；
  # 但标记判据只覆盖「标记字符串在不在」，一旦标记缺失而补丁其实已套用，
  # 就会落到这里 —— 所以这里同样必须反向优先。
  if patch --dry-run -N -F 0 -p1 --reverse "$full_path" < "$patch_file" >/dev/null 2>&1; then
    info "already in patched state, skip: $rel"; OK=$((OK+1))
  elif patch --dry-run -N -F 0 -p1 "$full_path" < "$patch_file" >/dev/null 2>&1; then
    if patch -N -F 0 -p1 "$full_path" < "$patch_file" >/dev/null 2>&1; then
      ok "applied: $rel"; OK=$((OK+1))
    else
      err "apply failed: $rel (try: cp '$full_path.bak' '$full_path'; then rerun)"; FAIL=$((FAIL+1))
    fi
  else
    err "patch cannot apply (official may have changed the code): $rel"; FAIL=$((FAIL+1))
  fi
done

echo ""
echo -e "${CYAN}============================================================${NC}"
if [ "$FAIL" = "0" ]; then
  echo -e "${GREEN}  Done: applied/confirmed $OK patch(es), no failure.${NC}"
else
  echo -e "${RED}  Done: success $OK, failed $FAIL.${NC}"
fi
echo -e "${CYAN}============================================================${NC}"
echo ""
echo -e "Next steps:"
echo -e "  1. Restart DSH:"
case "$(uname -s 2>/dev/null)" in
  MINGW*|MSYS*|CYGWIN*)
    echo -e "     ${YELLOW}taskkill //F //IM node.exe${NC}   # 然后重新运行 dsh web"
    echo -e "     （taskkill 会结束所有 node 进程；请先关闭其他 node 程序）"
    ;;
  *)
    echo -e "     npm layout:    ${YELLOW}pkill -f 'dsh web'; dsh web${NC}"
    echo -e "     source layout: restart your dev server / rebuild as you normally do"
    ;;
esac
case "$(uname -s 2>/dev/null)" in
  Darwin) echo -e "  2. Hard-refresh the browser page (Cmd+Shift+R) to use the new features." ;;
  MINGW*|MSYS*|CYGWIN*) echo -e "  2. Hard-refresh the browser page (Ctrl+Shift+R) to use the new features." ;;
  *) echo -e "  2. Hard-refresh the browser page (Ctrl+Shift+R) to use the new features." ;;
esac
if [ "$FAIL" -gt 0 ]; then
  echo ""
  echo -e "${RED}Some patches failed. Re-adapt per ADAPTING.md, or restore first:${NC}"
  # 恢复清单从 FILES 动态生成 —— 避免与补丁集脱节（历史上曾硬编码已退役的 client-connection）
  NPM_LIST=""; SRC_LIST=""
  for entry in "${FILES[@]}"; do
    IFS='|' read -r rel _patch _marker srel <<< "$entry"
    NPM_LIST="$NPM_LIST $rel"
    SRC_LIST="$SRC_LIST $srel"
  done
  echo "    推荐：直接跑 ${YELLOW}node tools/dsh-patch.mjs --restore${NC}（跨平台，无需 cp/patch）"
  echo "    手工恢复（npm layout，路径分隔符随平台）："
  echo "      for e in$NPM_LIST; do cp \"\$DSH_DIR/node_modules/@deepseek-ai/\$e.bak\" \"\$DSH_DIR/node_modules/@deepseek-ai/\$e\"; done"
  echo "    手工恢复（source layout，DSH_SOURCE 已设置）："
  echo "      for e in$SRC_LIST; do cp \"\$DSH_SOURCE/packages/\$e.bak\" \"\$DSH_SOURCE/packages/\$e\"; done"
fi
echo ""
