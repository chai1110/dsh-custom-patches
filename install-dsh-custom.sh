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
#  4. Usage: bash install-dsh-custom.sh [-y] [版本号]    (-y skips interactive confirm; 版本号可选，老版本用户指定用，缺省为最新 0.1.2-rc.1)
#
# Supports BOTH installation layouts:
#   A. global npm install  (default): finds DSH in global node_modules
#        target: <dsh>/node_modules/@deepseek-ai/<rel>
#   B. source / monorepo    (DSH_SOURCE set): DSH built from source (pnpm + tsdown)
#        target: <DSH_SOURCE>/packages/<source_rel>
#        To use, set DSH_SOURCE to your deepseek-harness source root, e.g.
#        export DSH_SOURCE=/path/to/deepseek-harness
#
# Adapted versions: 0.1.2-rc.1 (default) / 0.1.1-rc.2 / 0.1.0-rc.8 / 0.1.0-rc.7 (see versions.md)
# =============================================================================
set -u

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC} $*"; }
info() { echo -e "${CYAN}[i]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[x]${NC} $*"; }

# 本仓库（main / tag v0.1.2-rc.1）固定适配的 DSH 版本：0.1.2-rc.1。
# 其他 DSH 版本用户：请 checkout 对应版本 tag（见 README「多版本支持」）。
TARGET_VERSION="0.1.2-rc.1"

ASK=1
for arg in "$@"; do
  case "$arg" in
    -y) ASK=0 ;;
    *)
      err "Unknown argument: $arg"
      echo "  Usage: bash install-dsh-custom.sh [-y]"
      echo "  （main 固定适配 DSH 0.1.2-rc.1；其他版本请 checkout 对应 tag）"
      exit 1
      ;;
  esac
done

# Entries: rel | patch | marker | source_rel
#   rel         = path relative to the npm install plugin root (node_modules/@deepseek-ai/<rel>)
#   patch       = path to the .patch file inside this repo
#   marker      = feature marker used for "official already built-in" detection (empty = skip)
#   source_rel  = path relative to <source>/packages, used in source/monorepo layout
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
  "dsh-client-connection/lib/client.js|patches/client-connection/dsh-client-connection-lib-client.js.patch|unarchiveSession|client/connection/lib/client.js"
  "dsh-workspace/lib/index.js|patches/workspace/dsh-workspace-lib-index.js.patch|unarchiveSession|core/workspace/lib/index.js"
  "dsh-compaction-basic/lib/index.js|patches/compaction-basic/dsh-compaction-basic-lib-index.js.patch|compactionBackoffDelay|core/compaction-basic/lib/index.js"
  "dsh-client-ui-conversation/lib/client.js|patches/client-ui-conversation/dsh-client-ui-conversation-lib-client.js.patch|recallHistory|client/ui-conversation/lib/client.js"
  "dsh-client-ui-chat/lib/client.js|patches/client-ui-chat/dsh-client-ui-chat-lib-client.js.patch|message.editPrompt|client/ui-chat/lib/client.js"
  "dsh-client-ui-workspace/lib/client.js|patches/client-ui-workspace/dsh-client-ui-workspace-lib-client.js.patch|archived-sessions|client/ui-workspace/lib/client.js"
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
  if [ -z "$DSH_DIR" ]; then
    DSH_DIR=$(find /usr/local/lib/node_modules "$HOME/.local/lib/node_modules" \
      "$LOCALAPPDATA"/*/node_modules "$APPDATA"/*/node_modules \
      -name "dsh" -path "*/@deepseek-ai/*" -type d 2>/dev/null | head -1)
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
  LATEST=$(npm view @deepseek-ai/dsh version 2>/dev/null || echo "")
  if [ -n "$LATEST" ]; then
    echo -e "    npm latest:    ${YELLOW}$LATEST${NC}"
  else
    warn "Cannot query npm latest (network/npm source). Continuing."
  fi
  if [ "$VERSION" != "$TARGET_VERSION" ]; then
    err "Version mismatch: patches target $TARGET_VERSION, current is $VERSION"
    echo ""
    echo "  Choose one:"
    echo "    a) Old-version user: rerun with your version as argument, e.g."
    echo "       bash install-dsh-custom.sh -y $VERSION"
    echo "    b) Upgrade to the target version:"
    echo "       npm install -g @deepseek-ai/dsh@$TARGET_VERSION"
    echo "    c) If official upgraded beyond this repo, re-adapt per ADAPTING.md first."
    exit 1
  fi
  if [ -n "$LATEST" ] && [ "$LATEST" != "$TARGET_VERSION" ]; then
    warn "Official has newer version $LATEST (patches target $TARGET_VERSION)."
    warn "Patches may still apply; if official now bundles these features, check versions.md."
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
  if patch --dry-run -N -p1 "$full_path" < "$patch_file" >/dev/null 2>&1; then
    if patch -N -p1 "$full_path" < "$patch_file" >/dev/null 2>&1; then
      ok "applied: $rel"; OK=$((OK+1))
    else
      err "apply failed: $rel (try: cp '$full_path.bak' '$full_path'; then rerun)"; FAIL=$((FAIL+1))
    fi
  elif patch --dry-run -N -p1 --reverse "$full_path" < "$patch_file" >/dev/null 2>&1; then
    info "already in patched state, skip: $rel"; OK=$((OK+1))
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
echo -e "     npm layout:    ${YELLOW}kill $(pgrep -f 'dsh web') 2>/dev/null; dsh web${NC}"
echo -e "     source layout: restart your dev server / rebuild as you normally do"
echo -e "  2. Hard-refresh the browser page (Cmd+Shift+R) to use the new features."
if [ "$FAIL" -gt 0 ]; then
  echo ""
  echo -e "${RED}Some patches failed. Re-adapt per ADAPTING.md, or restore first:${NC}"
  if [ "$TARGET_VERSION" = "0.1.2-rc.1" ]; then
    echo "    npm layout:"
    echo "      for e in dsh-api-session-controller/lib/index.js dsh-api-session-controller/lib/client.js dsh-api-session-controller/lib/typert.host.js dsh-api-session-controller/lib/typert.remote-client.js dsh-api-remotes/lib/client.js dsh-agent-loop/lib/index.js dsh-client-connection/lib/client.js dsh-workspace/lib/index.js dsh-compaction-basic/lib/index.js dsh-client-ui-conversation/lib/client.js dsh-client-ui-chat/lib/client.js dsh-client-ui-workspace/lib/client.js; do cp \"\$DSH_DIR/node_modules/@deepseek-ai/\$e.bak\" \"\$DSH_DIR/node_modules/@deepseek-ai/\$e\"; done"
    echo "    source layout (DSH_SOURCE set):"
    echo "      for e in api/session-controller/lib/index.js api/session-controller/lib/client.js api/session-controller/lib/typert.host.js api/session-controller/lib/typert.remote-client.js api/remotes/lib/client.js core/agent-loop/lib/index.js client/connection/lib/client.js core/workspace/lib/index.js core/compaction-basic/lib/index.js client/ui-conversation/lib/client.js client/ui-chat/lib/client.js client/ui-workspace/lib/client.js; do cp \"\$DSH_SOURCE/packages/\$e.bak\" \"\$DSH_SOURCE/packages/\$e\"; done"
  else
    echo "    npm layout:"
    echo "      for e in dsh-host-apiproxy/lib/index.js dsh-agent-loop/lib/index.js dsh-client-connection/lib/client.js dsh-client-runtime/lib/client.js dsh-client-ui-conversation/lib/client.js; do cp \"\$DSH_DIR/node_modules/@deepseek-ai/\$e.bak\" \"\$DSH_DIR/node_modules/@deepseek-ai/\$e\"; done"
    echo "    source layout (DSH_SOURCE set):"
    echo "      for e in host/apiproxy/lib/index.js core/agent-loop/lib/index.js client/connection/lib/client.js client/runtime/lib/client.js client/ui-conversation/lib/client.js; do cp \"\$DSH_SOURCE/packages/\$e.bak\" \"\$DSH_SOURCE/packages/\$e\"; done"
  fi
fi
echo ""
