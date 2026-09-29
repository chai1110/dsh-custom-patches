#!/bin/bash
# check-update.sh — 检查 DSH 官方是否有新版本，并评估本补丁集是否需要重新适配
#
# 用法: bash check-update.sh   （本分支固定适配 DSH 0.2.0-rc.1）
# 说明:
#   1. 读取本地已装 DSH 版本
#   2. 查询 npm 官方的 latest 与 next 两个频道
#   3. 判断补丁集是否仍对得上，并给出下一动作指引
#
# ⚠️ 为什么要同时看两个频道：官方的大版本候选版（如 0.2.0-rc.1）常常**只发在 next 上**，
#    此时 `npm view @deepseek-ai/dsh version`（= latest）会返回**更旧**的版本。
#    只看 latest 会得出「官方版本比补丁适配版本旧」的荒谬结论，并建议用户"升级"到旧版。

set -e

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'

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
