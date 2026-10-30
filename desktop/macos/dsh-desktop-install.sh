#!/bin/bash
# dsh-desktop-install.sh — 构建补丁版并「换位安装」到 /Applications，最终只保留一个 app。
#
# ───────────────────────────── 为什么需要「换位」而不是「就地改」 ─────────────────────────────
# macOS 13+ 的「App 管理」保护会给 /Applications 下的第三方 app 打上
# com.apple.provenance / com.apple.macl 扩展属性，结果是：
#
#   ✗ 不能写 bundle 内部（连 root、连 xattr -d 都被拒，EPERM）
#   ✓ 但可以把整个 .app 移进移出
#
# 所以本脚本的做法是：
#   1. 在可写位置（~/Applications）用 dsh-desktop-patch.sh 造出补丁版
#   2. 把 /Applications 里现有的 app 整个挪到 backups/ 当回滚点
#   3. 把补丁版整个挪进 /Applications，占回官方路径
#
# 这样只有一个 app、名字和图标都是官方的，双击就能开，不会再出现
# 「双击补丁版却打开了官方版」的问题（两者 CFBundleIdentifier 都是 com.deepseek.dsh，
#  macOS 按 bundle id 认 app，`open` 会直接激活已在跑的那个）。
#
# ───────────────────────────────── 用法 ─────────────────────────────────
#   bash desktop/macos/dsh-desktop-install.sh            # 构建 + 换位安装
#   bash desktop/macos/dsh-desktop-install.sh --no-build # 跳过构建，直接换位（补丁版已存在时）
#   bash desktop/macos/dsh-desktop-install.sh --rollback # 从最近一次备份回滚官方版
#
# ───────────────────────────────── 注意 ─────────────────────────────────
#   * 运行前请**完全退出** DeepSeek Harness（单实例锁 + 正在运行的 asar 无法被替换）
#   * 换位后 app 的签名是 ad-hoc 的，macOS 可能要求重新授权
#     辅助功能 / 屏幕录制 / 完全磁盘访问（签名变了，TCC 记录会失效）
#   * 官方 nightly 自动更新仍会覆盖 app.asar 并清空补丁，届时重跑本脚本即可

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
say() { printf "%b\n" "$*"; }

HERE="$(cd "$(dirname "$0")" && pwd)"

OFFICIAL="/Applications/DeepSeek Harness.app"
STAGING="$HOME/Applications/DeepSeek Harness Patched.app"
BACKUP_DIR="$HOME/Documents/dsh_data/backups"

ASAR_REL="Contents/Resources/app.asar"

MARKER="editLastPrompt"

NODE="$HOME/.local/node-v24/bin/node"
[ -x "$NODE" ] || NODE="$(command -v node || true)"
[ -n "$NODE" ] || { say "${RED}需要 node${NC}"; exit 1; }

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
fi

marker_count() {
  local asar="$1"
  [ -f "$asar" ] || { echo 0; return; }
  grep -c -- "$MARKER" "$asar" 2>/dev/null || echo 0
}

app_running() {
  pgrep -f "MacOS/DeepSeek Harness$" >/dev/null 2>&1
}

# ── 回滚 ──
if [ "${1:-}" = "--rollback" ]; then
  latest="$(ls -dt "$BACKUP_DIR"/DeepSeek\ Harness.app.original-*.app 2>/dev/null | head -1 || true)"
  [ -n "$latest" ] || { say "${RED}找不到回滚点（$BACKUP_DIR/DeepSeek Harness.app.original-*.app）${NC}"; exit 1; }
  say "${YELLOW}回滚到: $latest${NC}"
  app_running && { say "${RED}请先完全退出 DeepSeek Harness${NC}"; exit 1; }
  ts="$(date +%Y%m%d-%H%M%S)"
  mv "$OFFICIAL" "$BACKUP_DIR/DeepSeek Harness.app.patched-$ts.app"
  mv "$latest" "$OFFICIAL"
  say "${GREEN}已回滚。${NC}当前标记数: $(marker_count "$OFFICIAL/$ASAR_REL")（0 = 官方原版）"
  exit 0
fi

# ── 前置检查 ──
if app_running; then
  say "${RED}DeepSeek Harness 正在运行，请先完全退出（⌘Q），否则无法替换${NC}"
  exit 1
fi
[ -d "$OFFICIAL" ] || { say "${RED}官方 app 不存在: $OFFICIAL${NC}"; exit 1; }

# ── 构建 ──
if [ "${1:-}" != "--no-build" ]; then
  say "${YELLOW}== 构建补丁版（调用 dsh-desktop-patch.sh）==${NC}"
  PATH="$HOME/.local/node-v24/bin:$PATH" bash "$HERE/dsh-desktop-patch.sh" "$OFFICIAL" "$STAGING"
else
  say "${YELLOW}== 跳过构建（--no-build）==${NC}"
fi

[ -d "$STAGING" ] || { say "${RED}补丁版不存在: $STAGING${NC}"; exit 1; }
n="$(marker_count "$STAGING/$ASAR_REL")"
[ "$n" -ge 1 ] || { say "${RED}补丁版里 $MARKER 标记为 0，拒绝安装${NC}"; exit 1; }
say "  补丁版标记数: $n"

# ── 换位 ──
mkdir -p "$BACKUP_DIR"
ts="$(date +%Y%m%d-%H%M%S)"
BAK="$BACKUP_DIR/DeepSeek Harness.app.original-$ts.app"

say "${YELLOW}== 换位安装 ==${NC}"
say "  1) 现有 app → $BAK"
mv "$OFFICIAL" "$BAK"

say "  2) 补丁版 → $OFFICIAL"
if ! mv "$STAGING" "$OFFICIAL"; then
  say "${RED}移入失败，回滚${NC}"
  mv "$BAK" "$OFFICIAL"
  exit 1
fi

# ── 校验 ──
say "${YELLOW}== 校验 ==${NC}"
codesign --verify --verbose=2 "$OFFICIAL" 2>&1 | tail -2
final="$(marker_count "$OFFICIAL/$ASAR_REL")"
say "  $MARKER 标记数: $final"
if [ "$final" -ge 1 ]; then
  say ""
  say "${GREEN}完成。现在只有一个 app，已带补丁。${NC}"
  say "  启动: open \"$OFFICIAL\""
  say "  验证: 输入框按 ↑ 撤回上一条；最后一条用户消息上出现编辑入口"
  say "  回滚: bash $0 --rollback"
else
  say "${RED}安装后标记为 0，回滚${NC}"
  mv "$OFFICIAL" "$STAGING"
  mv "$BAK" "$OFFICIAL"
  exit 1
fi
