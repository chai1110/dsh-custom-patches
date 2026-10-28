# DSH 自定义增强补丁
> 📖 [English](README.en.md)


为 [DeepSeek Harness (DSH)](https://github.com/deepseek-ai/deepseek-harness) Web GUI 添加三个官方暂未提供的实用改进：
**① 输入框 ↑/↓ 键发送历史**、**② 编辑最后一条消息并重新生成** 与 **③ 压缩（上下文总结）失败自动重试**。

- 适配版本：见 [**Releases**](https://github.com/chai1110/dsh-custom-patches/releases) —— 每个版本对应一个 tag，老版本 checkout 对应 tag 即可
- 许可证：**MIT**（详见 [LICENSE](LICENSE)）
- 维护：chai1110（<chai011379@gmail.com>）

> **这是什么 / 不是什么**：这是一套**编译产物补丁**，不是官方插件，也不是源码 fork。
> 它通过 `diff`/`patch` 直接修补 DSH 已装好的 npm 包文件（`node_modules` 里的编译 JS），
> 给 DSH 加上官方还没有的三个功能。**任何 npm 重装 / 升级 DSH 都会覆盖这些补丁，需重新应用。**

---

## ✨ 功能简介

### 1. 输入框上下键历史（类似终端）
- 在输入框按 **↑** 调出上一条发送过的消息，继续按 ↑ 逐条往前翻；按 **↓** 往回翻
- 编辑输入文字时，历史浏览位置自动重置
- 兼容中文输入法（拼音选词时不会误触）、多行文本（光标在首/末行才触发）、连续相同内容去重

### 2. 编辑最后一条消息并重新生成
- 将鼠标移到**最后一条用户消息**上，会看到一个 **✏️ 编辑**按钮
- 点击后消息变成可编辑文本框（预填原文）
- 修改后点击 **"保存并重新生成"**：新文本替换原文，**丢弃它之后的所有 AI 回复/工具调用**，AI 用新内容重新生成
- 更早的消息只保留复制，不可编辑；要改更早的内容，请用该条消息的**「分叉」**另起一个会话
- **AI 正在生成时也允许编辑**：会先撤销当前回合（**保留排队中的输入**），再按新文本重新生成
- 点击 **取消** 恢复原样

**机制说明**：编辑通过 DSH 会话层的 **surface replace**（append-only 日志 + 阴影替换）实现——历史记录保留，但模型与界面只看替换后的新序列。

> ✅ **2026-09-29 修复**：此前「重新发送后，旧的那一轮还留在会话里」是本补丁自己的 bug ——
> shadow 计算读错了 surfaceOp 的键名（写了 `op.start` / `op.end`，真实键是 `op.startSeq` / `op.endSeq`），
> 导致 `shadowed` 集合恒空、被替换的旧事件从不被跳过。修复后重发即刻生效：
> **旧提问与它的 AI 回复立即从会话消失，只留下替换后的新一轮**，同一句话不再出现两遍。

### 3. 压缩（上下文总结）失败自动重试
- DSH 上下文快满时会自动「压缩」——让模型把历史总结成摘要。但**压缩那一次 LLM 调用不走官方的重试机制**（`dsh-llm-retry` 的重试只挂在正常对话请求的 `agent/request-error` 上，而压缩是直接调 `ctx.llm.stream()`），所以遇到 **429 / 限流会直接失败，整次压缩白做**
- 本补丁在压缩的总结调用外加了**重试循环**，复用该 provider 的 `retryPolicy`（`retryableCodes` / `maxRetries` / `initialDelayMs` / `maxDelayMs` / `jitterRatio`，即 `settings.yaml` 里已配的那份）
- 退避为**指数退避 + 随机抖动**，且**可被中止**——你按停止时不会卡在等待里
- 每次重试都会往会话写入 `llm/retry` / `llm/retry-started` 事件，在会话日志里能直接看到
- 一句话价值：**网络抖一下，不会让一次压缩白做**

> 这一项**没有 UI**，属于「无感」的可靠性改进——只在限流/网络错误时才生效，但用久了会感激它。

---

## ⚠️ 平台与前置要求（先看这里）

### 推荐：用 Node 安装器（全平台一致，无斜杠/工具依赖）

```bash
node tools/dsh-patch.mjs -y
```

`tools/dsh-patch.mjs` 是**零依赖的 Node 脚本**，Node 本来就是装 DSH 的硬前置，所以它不需要 `patch` / `cp` / `find` / `pgrep` 中的任何一个，
路径一律用 `path.join` 拼装 —— **Windows 的反斜杠问题从根上不存在**。它还比 shell 版多做两件事：

- **零模糊匹配**：`patch` 默认 fuzz=2，会容忍上下文行不匹配（＝可能在错误的锚点上「成功」）。本安装器要求每一行上下文都精确命中，上游改动了就**大声报错**而不是静默错补。
- **套用后 `node --check` 语法校验**：语法炸了就自动从 `.bak` 回滚。

| 平台 | 是否支持 | 说明 |
|---|---|---|
| **macOS** | ✅ 原生支持 | 自带的 `/bin/bash`（**仍是 3.2.57**）与 `patch` 即可，`pgrep` 也已内置。**两个 shell 脚本已在本机 bash 3.2 下实跑通过** |
| **Linux** | ✅ 原生支持 | 自带 `patch`；部分精简发行版需 `sudo apt install patch` |
| **Windows** | ✅ 推荐用上面的 Node 安装器 | 纯 Node 实现，不依赖 `patch`/`pgrep`/`cp`/`find`，**没有路径分隔符问题**。若仍用 shell 版：Git for Windows 提供 `bash`；重启请用 `taskkill //F //IM node.exe`（`pgrep` 在 Windows 不存在） |

**为什么 Node 安装器在**所有**平台都是首选**（不只是 Windows）——它比 shell 版多四件事：

1. **零模糊**：`patch` 默认 fuzz=2，会容忍上下文行不匹配；Node 版要求每一行精确命中。
2. **主动报出 hunk 偏移**：`patch -F 0` 只关掉 fuzz，**不关掉 offset**，普通输出还看不见。
   Node 版会直接打印 `N hunk(s) matched at a different line than declared` —— 这是抓上游漂移的关键信号。
3. **套用后 `node --check`**：语法炸了自动从 `.bak` 回滚。
4. **先反向判「是否已套用」再套**：避免纯插入型补丁被**重复套用**（shell 版曾因此出过事故，
   见 [`ADAPTING.md`](ADAPTING.md) 的「严重 bug：shell 版会重复套用纯插入型补丁」）。

**统一前置条件**（任意平台）：
- 已安装 **Node.js**（含 `npm`）
- 已用 npm **全局安装 `@deepseek-ai/dsh`**；或从源码构建（见「源码构建（monorepo）用户」）

> **不装命令行工具也能用**：最省事的办法是把这个仓库链接（`https://github.com/chai1110/dsh-custom-patches`）发给你的 AI 助手，让它按本文档的「快速开始」在你的机器上完成安装与配置——它会自行处理 Windows 的 `taskkill` 等差异。

---

## 🚀 快速开始（各平台通用）

一共四步，**推荐用 HTTPS 克隆**（无需配置 SSH key）。把这整段丢给 AI 也能照着完成：

```bash
# 1) 安装 DSH（已装可跳过；版本要求见 Releases）
npm install -g @deepseek-ai/dsh@next
dsh --version          # 确认已装上

# 2) 克隆本仓库（HTTPS，对所有人可用）
git clone https://github.com/chai1110/dsh-custom-patches.git
cd dsh-custom-patches

# 3) 一键安装（-y 跳过交互确认；脚本会自动定位 DSH、校验版本、检测官方是否已内置、备份并应用）
node tools/dsh-patch.mjs -y

# 4) 重启 DSH —— macOS / Linux
pkill -f 'dsh web'; dsh web
```

> **Windows 重启**：把第 4 步换成 `taskkill /F /IM node.exe`（或结束对应 node 进程）后重新 `dsh web` 即可。
> **源码构建（monorepo）用户**：把第 3 步换成 `DSH_SOURCE=/path/to/deepseek-harness node tools/dsh-patch.mjs -y`，只需重建/重启你的开发服务（详见「源码构建（monorepo）用户」一节）。
> **shell 版仍然可用**：`bash install-dsh-custom.sh -y`（带版本诊断 + 内置检测）、`bash apply-dsh-patches.sh`（最简）。二者与 Node 版套用同一套补丁，按需选用；**但推荐入口是 Node 版**（更严：会报 hunk 偏移、有 `node --check` 回滚、且能防重复套用）。

然后**硬刷新**浏览器页面（`Cmd+Shift+R` / `Ctrl+Shift+R`），确认三件事：

- 输入框按 **↑** 能翻出上一条消息
- 最后一条用户消息 **hover** 出现 **✏️ 编辑** 按钮
- 「压缩失败自动重试」**没有 UI 信号**（只在限流 / 网络错误时于后台生效）；想确认可在会话日志里找 `llm/retry` 事件

**安装脚本会做什么**：定位 DSH 安装目录 → 版本诊断 → 校验版本（不匹配则拒绝并提示 checkout 正确 tag）→ **检测官方是否已内置功能**（已内置则跳过对应补丁）→ 逐一备份（`.bak`）并应用 → 输出汇总报告。再跑一次也能自诊断：输出 *"All features already present (built-in or applied). Nothing to do."* 即表示全部就位。

> 也可以把本仓库链接直接发给你的 AI 助手，让它按「快速开始」在你机器上完成配置；文档中的命令均可直接执行。

---

## 🖥️ 桌面版支持（DeepSeek Harness Desktop）

**桌面版是 Electron 应用，不走 npm 全局安装** —— 9 个补丁目标全部打包在 `resources/app.asar` 里，
所以要用本仓库的 `desktop/windows/apply-desktop-asar-patches.js`（纯 Node，无第三方依赖）单独安装。
**完整教程、平台差异、macOS 计划见 [`desktop/README.md`](desktop/README.md)**：

```bash
# 1) 先试套：只看补丁能否套上，不改动任何文件
node desktop/windows/apply-desktop-asar-patches.js --dry-run

# 2) 正式安装：退出应用 → 备份 app.asar → 打补丁 → 全量校验 → 替换 → 重启
node desktop/windows/apply-desktop-asar-patches.js

# 只生成新 asar 到指定路径、不替换原文件（应用可继续运行，适合先验证）
node desktop/windows/apply-desktop-asar-patches.js --out new.asar

# 两面一起打（CLI 侧 + 桌面版），并交叉核对功能标记
bash patch-all.sh
```

- **依赖**：Node（读写 asar 由脚本自带）+ `patch` 命令 —— Windows 装 Git for Windows 即有，
  也可用环境变量 `PATCH_BIN` 指定可执行文件路径。
- **路径自动探测**：Windows `%LOCALAPPDATA%\Programs\DeepSeek Harness\resources\app.asar`、
  macOS `/Applications/DeepSeek Harness.app/Contents/Resources/app.asar`、Linux `/opt/DeepSeek Harness/resources/app.asar`；
  不在这些位置就用 `--asar <path>`（或环境变量 `DSH_DESKTOP_ASAR`）。
- **幂等**：重复运行会先反向试套识别「已应用」并跳过，**不会重复叠加**（可放心重跑）。
- **每次替换前都会全量校验**：新 asar 必须可解析、路径顺序一致、**除 9 个补丁目标外的全部文件逐字节一致**、
  目标文件命中功能标记；任一项不过则不替换原文件（出错时自动回滚）。
- **⚠️ 桌面版带自动更新**：更新会覆盖 `app.asar`，补丁随即失效 —— 重跑本脚本，或用 `bash check-update.sh` 检测。
- **回滚**：把 `resources/app.asar.bak-<时间戳>` 改名回 `app.asar` 即可。
- **端口**：桌面宿主不再固定端口（早期版本硬编码 `19387`），改为动态分配；按固定端口探活 / 取 token 的脚本会失效。
- **与 npm 版共享 `~/.dsh` 根目录**（凭据、会话数据），但插件配置按 profile 独立：
  桌面版是 `~/.dsh/profiles/desktop`，不能直接照抄 web 版，见 `dsh-provider-config`。

---

## 🧩 源码构建（monorepo）用户

如果你不是用 `npm install -g` 装 DSH，而是**从源码克隆下来**（比如官方 [deepseek-harness](https://github.com/deepseek-ai/deepseek-harness) 的 pnpm monorepo，自己 `pnpm` + `tsdown` 构建、直接 serve 各包产物），同样可以打这套补丁——**补丁内容完全通用**，只是目标文件位置不同，脚本已支持这种布局。

### 第一步：确认两件事
- 你有 DSH 的**源码仓库根目录**（就是一个含 `packages/` 和 `pnpm-workspace.yaml` 的目录），例如 `/path/to/deepseek-harness`
- 各插件包**已构建**（生成了 `lib/` 产物；未构建时只有 `src/`，没有可打补丁的文件）

### 第二步：设置 `DSH_SOURCE` 并运行一键脚本
```bash
export DSH_SOURCE=/path/to/deepseek-harness          # 指向源码仓库根
bash install-dsh-custom.sh -y
```
脚本检测到 `DSH_SOURCE` 后会自动切换到源码布局：
- 在 `<DSH_SOURCE>/packages/**/lib/` 下定位目标文件、备份、应用
- **跳过 npm 版本校验**（源码没有语义化版本号），但请确认你的源码 checkout 与补丁版本对应
- 应用完成后，**重建/重启你的 DSH 开发服务**（和你平时重启方式一致），再硬刷新页面

### 源码布局下的目标文件（对应关系）
当前补丁集（9 项）在两种布局下的对应关系：

| 补丁目标文件（npm 布局） | 源码布局路径 |
|---|---|
| `dsh-api-session-controller/lib/index.js` | `packages/api/session-controller/lib/index.js` |
| `dsh-api-session-controller/lib/client.js` | `packages/api/session-controller/lib/client.js` |
| `dsh-api-session-controller/lib/typert.host.js` | `packages/api/session-controller/lib/typert.host.js` |
| `dsh-api-session-controller/lib/typert.remote-client.js` | `packages/api/session-controller/lib/typert.remote-client.js` |
| `dsh-api-remotes/lib/client.js` | `packages/api/remotes/lib/client.js` |
| `dsh-agent-loop/lib/index.js` | `packages/core/agent-loop/lib/index.js` |
| `dsh-compaction-basic/lib/index.js` | `packages/core/compaction-basic/lib/index.js` |
| `dsh-client-ui-conversation/lib/client.js` | `packages/client/ui-conversation/lib/client.js` |
| `dsh-client-ui-chat/lib/client.js` | `packages/client/ui-chat/lib/client.js` |

> 也就是说：一片补丁中写的 `dsh-xxx/lib/file.js`，在源码布局下就是 `<DSH_SOURCE>/packages/<对应目录>/lib/file.js`——内容一致，只是根不同。这也是为什么源码用户能直接趟通同一套补丁。
> 上表即脚本 `FILES` 数组第 1 段与第 4 段的映射；补丁集变化时以脚本为准。

### 如何恢复（源码布局）
```bash
# 在仓库目录下执行；清单取自脚本 FILES 的第 4 段，永远与当前补丁集同步
for e in $(sed -n '/^FILES=(/,/^)/p' install-dsh-custom.sh | grep '^  "' | sed 's/.*|\([^|]*\)"$/\1/'); do
  [ -f "$DSH_SOURCE/packages/$e.bak" ] && cp "$DSH_SOURCE/packages/$e.bak" "$DSH_SOURCE/packages/$e" && echo "restored $e"
done
```

> 想了解源码布局的更多细节，或如何为一处失效补丁重新适配，见 [ADAPTING.md](ADAPTING.md)。

---

## ↩️ 如何恢复原版（卸载补丁）

安装时脚本已为每个被改文件生成 `.bak` 备份。恢复只需把这些备份拷贝回去（**路径用 `npm root -g` 动态获取，兼容任意全局安装方式**；**文件清单直接取自脚本的 `FILES`，因此永远与当前补丁集同步**）：

```bash
# 在仓库目录下执行
PLUGIN="$(npm root -g)/@deepseek-ai/dsh/node_modules/@deepseek-ai"
for e in $(grep -oE '"dsh-[a-z-]+/lib/[a-z.-]+\.js' install-dsh-custom.sh | tr -d '"'); do
  [ -f "$PLUGIN/$e.bak" ] && cp "$PLUGIN/$e.bak" "$PLUGIN/$e" && echo "restored $e"
done
```

---

## 🔄 如何跟进官方更新

官方升级会覆盖这些补丁（因为改的是 node_modules 编译产物）。推荐用配套工具跟进：

```bash
# 1) 检测官方是否有新版（自动对比本地 / 最新 / 适配版本；也可指定版本：bash check-update.sh <version>）
bash check-update.sh

# 2) 升级官方
npm install -g @deepseek-ai/dsh@<新版本>

# 3) 重新应用（含内置检测；若官方新版没大改则直接成功）
bash install-dsh-custom.sh -y
```

- **官方是否已内置我们的功能？** 一键脚本会自动检测并跳过已内置的补丁；也可手动用 [`versions.md`](versions.md) 里的 grep 方法确认。
- **补丁失效了？** 按 [`ADAPTING.md`](ADAPTING.md) 的操作手册重新适配，并在 `versions.md` 追加新版本一行。
- **桌面版补丁被覆盖了？** 桌面版走 **nightly 自动更新**，官方包一更新就会把补丁冲掉。
  `bash check-update.sh` 会比对「来源指纹」并检查功能标记，告诉你是否需要重跑
  `bash desktop/macos/dsh-desktop-patch.sh`。
- **想一次确认两面都活着？** `bash patch-all.sh --check` —— 只核对不改动，退出码 0 即两面全绿。

> ⚠️ 若升级后 `patch` 报错，说明新版改了相应代码，需要按 `ADAPTING.md` 重新适配。

---

## 🤝 贡献与反馈

小项目，**没有单独的贡献指南** —— 有事直接开 [Issue](https://github.com/chai1110/dsh-custom-patches/issues) 或提 PR 就行。

- **报问题**：附上现象、环境（`dsh --version` / 操作系统 / Node 版本）、复现步骤、期望结果；
  有 `patch` 的 `Hunk #N failed` 输出最好。
- **提 PR**：欢迎新增功能补丁或修复适配。硬性要求只有四条 ——
  ① **补丁最小化**（只改必要几处）；② 留下可 grep 的**功能标记**；③ **三处 `FILES` 表必须同步**：
  `tools/dsh-patch.mjs`、`install-dsh-custom.sh`、`apply-dsh-patches.sh`
  （Node 版是推荐入口，另两处是 shell 版；三者字段不同，别只改一处）；
  ④ **同步更新 `tools/patch-markers.tsv`** —— 功能标记的单一数据源，
  `patch-all.sh` / `desktop/macos/dsh-desktop-patch.sh` / `check-update.sh` 都读它。
  挑标记的铁律：**官方原版里必须 0 次命中**（反例：`surfaceOp: "append"` 在原版已出现 8 次，无法判别）。
- **改桌面版相关**：见 [`desktop/README.md`](desktop/README.md) 与
  [`desktop/windows/README.md`](desktop/windows/README.md)（Windows 贡献清单）。
- **改文档**：主入口一律写 `node tools/dsh-patch.mjs`（shell 版是备选，提及请注明）；
  示例要能在全新 clone 后直接执行。
- **改补丁正文后**：跑一次 `node tools/dsh-patch.mjs --dry-run`，
  确认没有 `N hunk(s) matched at a different line than declared` ——
  理想情况是 **0**（详见 [`ADAPTING.md`](ADAPTING.md) 关于 `-F 0` 与 offset 的更正）。
- 重新适配新版的完整流程见 [`ADAPTING.md`](ADAPTING.md)。

---

## 📄 License

MIT — 见 [LICENSE](LICENSE)。

## 📎 相关资源

- SSH 多机并行插件: [chai1110/dsh-ssh-remote](https://github.com/chai1110/dsh-ssh-remote)
- 供应商配置模板: [chai1110/dsh-provider-config](https://github.com/chai1110/dsh-provider-config)
- DeepSeek Harness 官方: [deepseek-ai/deepseek-harness](https://github.com/deepseek-ai/deepseek-harness)
