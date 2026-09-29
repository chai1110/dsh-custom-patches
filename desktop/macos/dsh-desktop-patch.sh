#!/bin/bash
# dsh-desktop-patch.sh — 把本仓库的 9 个补丁打进 macOS 版 Electron 桌面应用
#                       （DeepSeek Harness.app），产出一个「打过补丁的副本」。
#
# ───────────────────────────── 为什么需要这个脚本 ─────────────────────────────
# 桌面版把 dsh 运行时封在**签名过的 app.asar** 里（`Contents/Resources/app.asar` 内的 `dsh/`）。
# 其安装锚点硬指向 asar 内部，不受 profile 目录或任何环境变量影响 ——
# `collectProfileScopePackages` 会把安装包名列为 reserved，profile 级包永远无法覆盖核心包。
# 所以「撤回/编辑上一条消息」这类需要同时改 host 侧
# （dsh-api-session-controller、dsh-agent-loop、dsh-compaction-basic）的功能，
# 只能改 asar 本体。详见 ../README.md「为什么只能改 app.asar」。
#
# ─────────────────────────────── 本脚本做什么 ───────────────────────────────
#   1. 用 APFS 写时复制克隆官方 app（不占额外磁盘、原版完全不动）
#   2. 从克隆的 asar 里抽出 9 个目标文件
#   3. 用仓库里 patches/ 下的 9 个 .patch 打补丁（-N -F 0 -p1，零 fuzz）
#   4. 外科式改写 asar：只替换这 9 个条目，其余条目逐字节不变
#   5. 逐条目校验改写结果 + 功能标记核对
#   6. ad-hoc 重签名（保留 hardened runtime 与原 entitlements）+ 去 quarantine
#
# ───────────────────────────────── 用法 ─────────────────────────────────
#   bash desktop/macos/dsh-desktop-patch.sh [源app] [目标app]
#   默认：源 /Applications/DeepSeek Harness.app
#         目标 ~/Applications/DeepSeek Harness Patched.app
#
# ───────────────────────────────── 注意 ─────────────────────────────────
#   * 桌面版走 nightly 自动更新（app-update.yml → download.deepseek.com/dsh-desk/...），
#     官方包每次更新后需对本脚本重新执行一次。`bash check-update.sh` 会检测这件事。
#   * 补丁是「按版本适配」的：官方升到新版本后，若 patch 不再零 fuzz 应用，
#     需先按 ADAPTING.md 更新 patches/。
#   * 打完补丁的副本与官方版**共用同一个 user-data 目录**，二者不能同时运行
#     （单实例锁 + 固定端口 19387）。
#
#   * Windows 版是独立模块（见 ../windows/README.md）。本脚本把「平台相关」的部分
#     集中隔离在下面那一段，若两平台最终确认一致，合并时只需替换那一段。

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
say() { printf "%b\n" "$*"; }

# ══════════════════ 平台相关：Windows 版若复用本脚本，只需改这一段 ══════════════════
PLATFORM="macos"

# app 包内 app.asar 的相对路径（Windows 通常是 resources/app.asar）
ASAR_REL="Contents/Resources/app.asar"

# asar 内 @deepseek-ai 各包的父目录
INNER_PREFIX="dsh/node_modules/@deepseek-ai"

# 克隆：macOS 用 APFS 写时复制（cp -c，秒级、不占额外磁盘）；非 APFS 自动退回全量拷贝
clone_app() { cp -c -R "$1" "$2" 2>/dev/null || cp -R "$1" "$2"; }

# 重签名：macOS 改动 asar 后必须重签（ad-hoc 即可，因为 Electron 的
# EnableEmbeddedAsarIntegrityValidation 保险丝 = 0，不需要更新 Info.plist）；
# Windows 无需对应步骤 —— Electron 不校验 Authenticode。
sign_app() {
  # ⚠️ 必须分两句：`local a="$1" b="$a/..."` 在同一句里引用刚声明的局部变量，
  # 在 `set -u` 下会报 "b: unbound variable"（bash 会把本句所有名字先声明为未赋值）。
  local app="$1" work="$2"
  local ent="$work/entitlements.plist"
  codesign -d --entitlements :- "$app" > "$ent" 2>/dev/null || true
  if [ -s "$ent" ]; then
    codesign --force --sign - --options runtime --entitlements "$ent" "$app"
  else
    say "  ${YELLOW}未取到 entitlements，按无 entitlements 重签${NC}"
    codesign --force --sign - --options runtime "$app"
  fi
  xattr -dr com.apple.quarantine "$app" 2>/dev/null || true
  codesign --verify --verbose=2 "$app" 2>&1 | tail -2
}
# ══════════════════════════════════════════════════════════════════════════════

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
fi

SRC_APP="${1:-/Applications/DeepSeek Harness.app}"
DST_APP="${2:-$HOME/Applications/DeepSeek Harness Patched.app}"

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
TOOL="$REPO/desktop/dsh-desktop-asar.mjs"

command -v node >/dev/null || { say "${RED}需要 node${NC}"; exit 1; }
command -v patch >/dev/null || { say "${RED}需要 patch 命令${NC}"; exit 1; }
[ -d "$SRC_APP" ] || { say "${RED}源 app 不存在: $SRC_APP${NC}"; exit 1; }
[ -f "$TOOL" ]    || { say "${RED}缺少 $TOOL${NC}"; exit 1; }

# 安全闸：绝不把补丁打进官方 app 本身，也绝不让源=目标
SRC_REAL="$(cd "$SRC_APP" && pwd -P)"
case "$DST_APP" in
  /Applications/*) say "${RED}拒绝把目标设在 /Applications 下（官方 app 必须保持原样）${NC}"; exit 1 ;;
esac
if [ -e "$DST_APP" ] && [ "$(cd "$DST_APP" && pwd -P)" = "$SRC_REAL" ]; then
  say "${RED}源与目标为同一个 app，拒绝执行${NC}"; exit 1
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/dsh-desktop-patch.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# ── 补丁与目标文件映射（相对 @deepseek-ai 插件目录），必须与 apply-dsh-patches.sh 一致 ──
# 「功能标记」不在本表里，统一从 tools/patch-markers.tsv 读取（单一数据源，
# patch-all.sh / check-update.sh 读的是同一份，避免三处各写一套标记而漂移）。
FILES=(
  "dsh-api-session-controller/lib/index.js|patches/api-session-controller/dsh-api-session-controller-lib-index.js.patch"
  "dsh-api-session-controller/lib/client.js|patches/api-session-controller/dsh-api-session-controller-lib-client.js.patch"
  "dsh-api-session-controller/lib/typert.host.js|patches/api-session-controller/dsh-api-session-controller-lib-typert-host.js.patch"
  "dsh-api-session-controller/lib/typert.remote-client.js|patches/api-session-controller/dsh-api-session-controller-lib-typert-remote-client.js.patch"
  "dsh-api-remotes/lib/client.js|patches/api-remotes/dsh-api-remotes-lib-client.js.patch"
  "dsh-agent-loop/lib/index.js|patches/agent-loop/dsh-agent-loop-lib-index.js.patch"
  "dsh-compaction-basic/lib/index.js|patches/compaction-basic/dsh-compaction-basic-lib-index.js.patch"
  "dsh-client-ui-conversation/lib/client.js|patches/client-ui-conversation/dsh-client-ui-conversation-lib-client.js.patch"
  "dsh-client-ui-chat/lib/client.js|patches/client-ui-chat/dsh-client-ui-chat-lib-client.js.patch"
)

MARKERS_FILE="$REPO/tools/patch-markers.tsv"
[ -f "$MARKERS_FILE" ] || { say "${RED}缺少 $MARKERS_FILE${NC}"; exit 1; }
marker_for() { awk -F'\t' -v r="$1" '!/^#/ && $1==r {print $2; exit}' "$MARKERS_FILE"; }

say "${YELLOW}== 1/6 克隆官方 app（APFS 写时复制，原版不动）==${NC}"
if [ -d "$DST_APP" ]; then
  say "  目标已存在，先移除: $DST_APP"
  rm -rf "$DST_APP"
fi
mkdir -p "$(dirname "$DST_APP")"
clone_app "$SRC_APP" "$DST_APP"

ASAR="$DST_APP/$ASAR_REL"
[ -f "$ASAR" ] || { say "${RED}找不到 $ASAR（app 布局可能已变，请更新本脚本的 ASAR_REL）${NC}"; exit 1; }

say "${YELLOW}== 2/6 从桌面版 asar 抽出目标文件 ==${NC}"
mkdir -p "$WORK/pristine" "$WORK/patched"
for entry in "${FILES[@]}"; do
  rel="${entry%%|*}"
  mkdir -p "$WORK/pristine/$(dirname "$rel")" "$WORK/patched/$(dirname "$rel")"
  node "$TOOL" cat "$ASAR" "$INNER_PREFIX/$rel" > "$WORK/pristine/$rel"
  cp "$WORK/pristine/$rel" "$WORK/patched/$rel"
done
say "  抽出 ${#FILES[@]} 个文件"

say "${YELLOW}== 3/6 应用补丁（-N -F 0 -p1）==${NC}"
cd "$WORK/patched"
applied=0
for entry in "${FILES[@]}"; do
  rel="${entry%%|*}"; rest="${entry#*|}"; pat="${rest%%|*}"
  if patch -N -F 0 -p1 --no-backup-if-mismatch < "$REPO/$pat" > "$WORK/patch.log" 2>&1; then
    say "  ${GREEN}OK${NC}   $rel"
    applied=$((applied+1))
  else
    say "  ${RED}FAIL${NC} $rel"
    sed -n '1,10p' "$WORK/patch.log"
    say "${RED}补丁未能零 fuzz 应用——桌面版版本可能已变，请先按 ADAPTING.md 更新 patches/${NC}"
    exit 1
  fi
done
if find "$WORK/patched" -name '*.rej' | grep -q .; then
  say "${RED}出现 .rej 文件，中止${NC}"; exit 1
fi
say "  成功应用 $applied / ${#FILES[@]}，无 .rej"

say "${YELLOW}== 4/6 外科式改写 asar ==${NC}"
: > "$WORK/relpaths.txt"
for entry in "${FILES[@]}"; do printf '%s\n' "${entry%%|*}" >> "$WORK/relpaths.txt"; done
node -e '
const fs = require("fs");
const [work, prefix] = process.argv.slice(1);
const rels = fs.readFileSync(work + "/relpaths.txt", "utf8").split("\n").filter(Boolean);
const map = {};
for (const rel of rels) map[prefix + "/" + rel] = work + "/patched/" + rel;
fs.writeFileSync(work + "/map.json", JSON.stringify(map, null, 2));
console.log("  map.json 条目数: " + rels.length);
' "$WORK" "$INNER_PREFIX"

# 临时文件用非 .asar 后缀：某些环境（含自动化沙箱）会拒绝「新建 .asar 文件」，
# 用 .new 后缀写入、最后 mv 覆盖已存在的 app.asar，可绕开该限制。
NEW_ASAR="$DST_APP/$(dirname "$ASAR_REL")/.app.asar.new"
node "$TOOL" rewrite "$ASAR" "$NEW_ASAR" "$WORK/map.json"

say "${YELLOW}== 5/6 逐条目校验 + 功能标记核对 ==${NC}"
node "$TOOL" verify "$ASAR" "$NEW_ASAR" "$WORK/map.json"

marker_fail=0
for entry in "${FILES[@]}"; do
  rel="${entry%%|*}"
  marker="$(marker_for "$rel")"
  if [ -z "$marker" ]; then
    printf "  ${RED}✗${NC} %-58s 在 %s 中找不到标记\n" "$rel" "tools/patch-markers.tsv"
    marker_fail=$((marker_fail+1)); continue
  fi
  n=$(node "$TOOL" cat "$NEW_ASAR" "$INNER_PREFIX/$rel" | grep -cF -- "$marker" || true)
  if [ "$n" -ge 1 ]; then
    printf "  ${GREEN}✓${NC} %-58s %s ×%s\n" "$rel" "$marker" "$n"
  else
    printf "  ${RED}✗${NC} %-58s %s 未命中\n" "$rel" "$marker"
    marker_fail=$((marker_fail+1))
  fi
done
if [ "$marker_fail" -ne 0 ]; then
  say "${RED}有 $marker_fail 个功能标记未命中，放弃写入（目标 app 未改动）${NC}"
  exit 1
fi

mv "$NEW_ASAR" "$ASAR"

# ── 记录「来源指纹」——供 check-update.sh 判断官方桌面版是否已更新 ──
# ⚠️ 必须在重签名**之前**写入：往已签名的 app 里加文件会让签名失效。
# 桌面版走 nightly 自动更新，官方 app 一更新，本副本就落后了；
# 有了这份指纹，check-update.sh 一比 sha256 就知道要不要重跑本脚本。
FINGERPRINT="$DST_APP/$(dirname "$ASAR_REL")/.dsh-desktop-patch.json"
sha() { node -e 'const c=require("crypto"),f=require("fs");const h=c.createHash("sha256");const s=f.createReadStream(process.argv[1]);s.on("data",d=>h.update(d));s.on("end",()=>console.log(h.digest("hex")))' "$1"; }
SRC_ASAR="$SRC_APP/$ASAR_REL"
{
  printf '{\n'
  printf '  "patchedAt": "%s",\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '  "platform": "%s",\n' "$PLATFORM"
  printf '  "sourceApp": "%s",\n' "$SRC_APP"
  printf '  "sourceAsarSha256": "%s",\n' "$(sha "$SRC_ASAR")"
  printf '  "sourceAsarSize": %s,\n' "$(stat -f%z "$SRC_ASAR" 2>/dev/null || stat -c%s "$SRC_ASAR")"
  printf '  "patchedAsarSha256": "%s",\n' "$(sha "$ASAR")"
  printf '  "patchedAsarSize": %s,\n' "$(stat -f%z "$ASAR" 2>/dev/null || stat -c%s "$ASAR")"
  printf '  "targets": [\n'
  first=1
  for entry in "${FILES[@]}"; do
    rel="${entry%%|*}"
    [ "$first" -eq 1 ] || printf ',\n'
    printf '    "%s"' "$rel"
    first=0
  done
  printf '\n  ]\n'
  printf '}\n'
} > "$FINGERPRINT"
say "  已记录来源指纹: $FINGERPRINT"

say "${YELLOW}== 6/6 重签名 + 去 quarantine ==${NC}"
sign_app "$DST_APP" "$WORK"

say ""
say "${GREEN}完成。${NC}"
say "  打过补丁的桌面版: $DST_APP"
say "  官方原版保持不动: $SRC_APP"
say ""
say "  启动: open \"$DST_APP\""
say "  验证: 打开会话，输入框里按 ↑ 可撤回上一条已发送消息；最后一条用户消息上出现编辑入口。"
say "  注意: 与官方版共用同一个 user-data 目录，二者不能同时运行（单实例锁 + 固定端口 19387）。"
