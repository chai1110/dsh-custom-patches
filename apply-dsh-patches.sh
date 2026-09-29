#!/bin/bash
# DSH 自定义补丁安装脚本（适配 @deepseek-ai/dsh 0.2.0-rc.1）
# 用法:
#   bash apply-dsh-patches.sh                # 本分支（version/0.2.0-rc.1）固定适配 DSH 0.2.0-rc.1
#
# 其他 DSH 版本用户：请 checkout 对应版本 tag（见 README「多版本支持」）。
# rc.6 及更早没有单独保存（本仓库自 rc.7 起发布），需升级官方后再用。

set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

# 本仓库（version/0.2.0-rc.1 分支）固定适配的 DSH 版本
TARGET_VERSION="0.2.0-rc.1"

# 补丁与目标文件映射（相对 @deepseek-ai 插件目录）
# 格式: "相对插件路径|补丁在仓库中的相对路径"
# rc.1 (0.1.2-rc.1) 是架构重构版：host-apiproxy/client-runtime 已移除，
# 编辑重发改由 dsh-api-session-controller + dsh-client-ui-chat 承载；
# 0.1.2 新增 dsh-api-remotes（浏览器端 remote.session 方法表 = 其 lib/client.js
# 内嵌的 typert 模型冻结副本），@Remote 增删方法必须同步补它。
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

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 1. 定位 DSH 安装目录（跨平台：macOS / Linux / Windows）
#    方法 0：外部显式指定 —— 若调用方（如 patch-all.sh）已设好 DSH_DIR，直接采用，跳过探测。
#            用途：本机 DSH 装在自建 node 目录（~/.local/node-v24/lib/node_modules）时，
#            `npm root -g` 可能解析到另一个 node 而探测失败，此时由调用方传入最可靠。
#    方法 A：npm root -g（最可靠——npm 全局根，任何平台都返回正确值）
#    方法 B：require.resolve 兜底（用 [\\/] 兼容 Windows 反斜杠路径）
#    方法 C：常见全局目录扫描兜底（含 Windows %APPDATA%/%LOCALAPPDATA%）
DSH_DIR="${DSH_DIR:-}"
if [ -n "$DSH_DIR" ] && [ -d "$DSH_DIR/node_modules/@deepseek-ai" ]; then
  echo -e "${GREEN}✅ 使用调用方指定的 DSH: $DSH_DIR${NC}"
else
  DSH_DIR=""
  GLOBAL_ROOT=$(npm root -g 2>/dev/null || echo "")
  if [ -n "$GLOBAL_ROOT" ] && [ -d "$GLOBAL_ROOT/@deepseek-ai/dsh" ]; then
    DSH_DIR="$GLOBAL_ROOT/@deepseek-ai/dsh"
  fi
  if [ -z "$DSH_DIR" ]; then
    DSH_DIR=$(node -e "try{console.log(require.resolve('@deepseek-ai/dsh/package.json').replace(/[\\\\/]package\.json$/,''))}catch(e){console.log('')}" 2>/dev/null)
  fi
  # 方法 C′：顺着 `dsh` 可执行文件反推（覆盖自建 node 目录 / nvm / volta）
  if [ -z "$DSH_DIR" ]; then
    _exe=$(command -v dsh 2>/dev/null || echo "")
    if [ -n "$_exe" ]; then
      _real=$(node -e "try{console.log(require('fs').realpathSync(process.argv[1]))}catch(e){console.log('')}" "$_exe" 2>/dev/null)
      case "$_real" in
        */@deepseek-ai/dsh/lib/bin.js) DSH_DIR="${_real%/lib/bin.js}" ;;
        */@deepseek-ai/dsh/*)          DSH_DIR="${_real%%/@deepseek-ai/dsh/*}/@deepseek-ai/dsh" ;;
      esac
    fi
  fi
  # ⚠️ $APPDATA / $LOCALAPPDATA 在 macOS / Linux 上未定义：旧写法 "$LOCALAPPDATA"/*/node_modules
  # 会展开成 /*/node_modules，让 find 去扫根目录下的每一层（慢且可能命中无关目录）。
  # 改为 ${VAR:-} 判空 + 逐目录探测，POSIX 安全，且不依赖数组。
  if [ -z "$DSH_DIR" ]; then
    for _base in /usr/local/lib/node_modules "$HOME/.local/lib/node_modules" \
                 "$HOME"/.local/*/lib/node_modules \
                 "$HOME"/.nvm/versions/node/*/lib/node_modules \
                 "${APPDATA:-/nonexistent}/npm/node_modules" \
                 "${LOCALAPPDATA:-/nonexistent}/npm/node_modules"; do
      if [ -d "$_base/@deepseek-ai/dsh" ]; then
        DSH_DIR="$_base/@deepseek-ai/dsh"
        break
      fi
    done
  fi
fi
if [ -z "$DSH_DIR" ]; then
  echo -e "${RED}❌ 未找到 DSH 安装目录，请先安装 @deepseek-ai/dsh@$TARGET_VERSION${NC}"
  echo -e "   （Windows 请确认 npm 全局目录：npm root -g 应输出您的全局 node_modules 路径）"
  exit 1
fi
echo -e "${GREEN}✅ 找到 DSH: $DSH_DIR${NC}"

# 2. 校验版本
VERSION=$(node -e "console.log(require('$DSH_DIR/package.json').version)" 2>/dev/null)
echo -e "   当前版本: ${YELLOW}$VERSION${NC}（补丁目标: ${YELLOW}$TARGET_VERSION${NC}）"
if [ "$VERSION" != "$TARGET_VERSION" ]; then
  echo -e "${RED}❌ 版本不匹配：本补丁集按 $TARGET_VERSION 适配，当前是 $VERSION${NC}"
  echo -e "   两种处理方式（任选其一）："
  echo -e "     a) 老版本用户：${YELLOW}git checkout v$VERSION${NC} 切到对应 tag 后重跑本脚本"
  echo -e "     b) 想用最新版：升级 ${YELLOW}npm install -g @deepseek-ai/dsh@$TARGET_VERSION${NC} 后重试"
  exit 1
fi

# 3. 检查补丁文件齐全
ALL_OK=true
for entry in "${FILES[@]}"; do
  patch_file="${entry#*|}"
  if [ -f "$SCRIPT_DIR/$patch_file" ]; then
    echo -e "  ${GREEN}✅ 找到补丁: $patch_file${NC}"
  else
    echo -e "  ${RED}❌ 缺失补丁: $patch_file${NC}"
    ALL_OK=false
  fi
done
[ "$ALL_OK" = false ] && { echo -e "\n${RED}请将补丁文件与脚本放在同一目录后重试。${NC}"; exit 1; }

# 4. 逐条备份并应用
echo ""
echo -e "${YELLOW}开始备份并应用补丁…${NC}"
PLUGIN_ROOT="$DSH_DIR/node_modules/@deepseek-ai"
for entry in "${FILES[@]}"; do
  rel_path="${entry%%|*}"; patch_file="${entry#*|}"
  full_path="$PLUGIN_ROOT/$rel_path"

  if [ ! -f "$full_path" ]; then
    echo -e "  ${YELLOW}⚠️  跳过（目标不存在）: $rel_path${NC}"
    continue
  fi

  # 备份（首次）
  if [ ! -f "$full_path.bak" ]; then
    cp "$full_path" "$full_path.bak"
    echo -e "  ${GREEN}✓${NC} 已备份: $rel_path.bak"
  fi

  # 应用
  # 注意 -F 0：patch 默认 fuzz=2，会容忍上下文行不匹配（＝可能在错误的锚点上"成功"）。
  # 零模糊才能真正证明锚点未被上游改动（见 ADAPTING.md 铁律 3）。
  #
  # ⚠️⚠️ 顺序不能反：**必须先做「反向 dry-run」判断是否已套用，正向 dry-run 只能放在 elif。**
  # 本补丁集里有**纯插入型**补丁（典型：api-session-controller/lib/client.js），
  # 它插入的那段代码不破坏自身的上下文行，所以套用之后**正向 dry-run 依然会成功**。
  # 而 `patch -N`（--forward）只抑制「正向失败」的补丁，对这种情况完全无效 ——
  # 结果就是同一个补丁被**套用两遍**。
  # 2026-09-29 实测事故：该文件被插入两遍，3674 行 → 3698 行，
  # `editLastPrompt` 从应有的 2 次变成 4 次（重复的函数定义）。
  # 反向 dry-run 在「未套用」时必然失败、在「已套用」时才成功，是唯一可靠的判据；
  # tools/dsh-patch.mjs 就是这么做的（isAlreadyApplied 先于 applyPatch）。
  if patch --dry-run -N -F 0 -p1 --reverse "$full_path" < "$SCRIPT_DIR/$patch_file" >/dev/null 2>&1; then
    echo -e "  ${YELLOW}ℹ️  已是打过补丁的状态，跳过: $rel_path${NC}"
  elif patch --dry-run -N -F 0 -p1 "$full_path" < "$SCRIPT_DIR/$patch_file" >/dev/null 2>&1; then
    patch -N -F 0 -p1 "$full_path" < "$SCRIPT_DIR/$patch_file" >/dev/null 2>&1
    echo -e "  ${GREEN}✅ 已应用: $rel_path${NC}"
  else
    echo -e "  ${RED}❌ 应用失败: $rel_path${NC}"
    echo -e "    可能是补丁已应用或文件已被改动。可尝试：cp '$full_path.bak' '$full_path' 后重跑。"
    echo -e "    跨平台推荐：node tools/dsh-patch.mjs --restore"
  fi
done

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  补丁应用完成（适配 ${TARGET_VERSION}）！${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "下一步:"
case "$(uname -s 2>/dev/null)" in
  MINGW*|MSYS*|CYGWIN*)
    echo -e "  1. ${YELLOW}重启 DSH: taskkill //F //IM node.exe${NC}，然后重新运行 ${YELLOW}dsh web${NC}"
    echo -e "  2. 硬刷新浏览器页面（${YELLOW}Ctrl+Shift+R${NC}）使用新功能"
    ;;
  Darwin)
    echo -e "  1. ${YELLOW}重启 DSH: pkill -f 'dsh web'; dsh web${NC}"
    echo -e "  2. 硬刷新浏览器页面（${YELLOW}Cmd+Shift+R${NC}）使用新功能"
    ;;
  *)
    echo -e "  1. ${YELLOW}重启 DSH: pkill -f 'dsh web'; dsh web${NC}"
    echo -e "  2. 硬刷新浏览器页面（${YELLOW}Ctrl+Shift+R${NC}）使用新功能"
    ;;
esac
echo ""
echo -e "如需恢复原版（仅当前设备）:"
echo -e "  ${YELLOW}node tools/dsh-patch.mjs --restore${NC}   # 跨平台，推荐"
# 恢复清单从 FILES 动态生成 —— 避免与补丁集脱节（历史上曾硬编码已退役的补丁）
RESTORE_LIST=""
for entry in "${FILES[@]}"; do RESTORE_LIST="$RESTORE_LIST ${entry%%|*}"; done
echo -e "  ${YELLOW}或手工: for e in${RESTORE_LIST}; do cp \"$PLUGIN_ROOT/\$e.bak\" \"$PLUGIN_ROOT/\$e\"; done${NC}"
