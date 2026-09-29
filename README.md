# DSH 自定义增强补丁
> 📖 [English](README.en.md)


为 [DeepSeek Harness (DSH)](https://github.com/deepseek-ai/deepseek-harness) Web GUI 添加三个官方暂未提供的实用改进：
**① 输入框 ↑/↓ 键发送历史**、**② 编辑最后一条消息并重新生成** 与 **③ 压缩（上下文总结）失败自动重试**。

- 适配版本：**`@deepseek-ai/dsh@0.2.0-rc.1`**（官方 `next`；本仓库按 tag 管理版本，其他 DSH 版本用户请 checkout 对应 tag，见「多版本支持」）
- 许可证：**MIT**（详见 [LICENSE](LICENSE)）
- 维护：chai1110（<chai011379@gmail.com>）

> **这是什么 / 不是什么**：这是一套**编译产物补丁**，不是官方插件，也不是源码 fork。
> 它通过 `diff`/`patch` 直接修补 DSH 已装好的 npm 包文件（`node_modules` 里的编译 JS），
> 给 DSH 加上官方还没有的三个功能。**任何 npm 重装 / 升级 DSH 都会覆盖这些补丁，需重新应用。**

---

## 📌 当前适配范围（哪些文档是「最新」的）

**本仓库 `main` 分支的目标版本：`@deepseek-ai/dsh@0.2.0-rc.1`（官方 `next` 频道）。**

> ⚠️ `0.2.0-rc.1` 在官方 **`next`** 频道，**`latest` 仍是 `0.1.7-rc.2`**。
> `npm install -g @deepseek-ai/dsh` 默认装到 `0.1.7-rc.2` —— 那种情况请 **checkout `v0.1.7-rc.2`**，
> 或显式装新版：`npm install -g @deepseek-ai/dsh@0.2.0-rc.1`。

⚠️ 本仓库是**多版本仓库**，而且**并非每个文档都随最新版同步重写过**。下表如实说明各文件的状态 ——
请以「状态」列判断可信度，**不要默认所有文档都是最新的**。

| 文件 | 状态 | 说明 |
|---|---|---|
| `tools/dsh-patch.mjs` | ✅ 已适配 0.2.0-rc.1 | **推荐安装器（全平台）**；零依赖 Node，无 `patch`/`cp`/`find`/`pgrep` 依赖，零模糊匹配 + `node --check` 校验 + 自动回滚 |
| `install-dsh-custom.sh` | ✅ 已适配 0.2.0-rc.1 | shell 版主安装器；`TARGET_VERSION=0.2.0-rc.1`，9 项补丁 |
| `apply-dsh-patches.sh` | ✅ 已适配 0.2.0-rc.1 | shell 版备选安装器（无版本诊断 / 无内置检测） |
| `check-update.sh` | ✅ 已适配 0.2.0-rc.1 | 检测官方是否有新版 |
| `patches/**` | ✅ 已重适配 | 11 → 9 项；归档相关补丁（`client-connection` / `workspace` / `client-ui-workspace`）**全部退役** —— 官方已原生提供完整链路（归档 + 取消归档 + 侧边栏筛选 + 行内恢复 + 搜索恢复）。相对上一发布版 `v0.1.5-rc.1` 的 12 项为 **12 → 9**（`client-connection` 在 0.1.7-rc.2 适配早期退役，12→11；`workspace` + `client-ui-workspace` 于 2026-09-28 退役，11→9） |
| `README.md` / `README.en.md` | ✅ 已适配 0.2.0-rc.1 | 本文件 |
| `versions.md` | ✅ 已适配 0.2.0-rc.1 | 版本追踪表 |
| `ADAPTING.md` | ✅ 含 0.2.0-rc.1 适配记录 | 另含历史各版实录（`0.1.2-alpha.2` 预研 / `0.1.2-rc.1` / `0.1.5-rc.1`），属**有意保留的历史档案** |
| `POSTMORTEM.md` | 🕘 历史记录（2026-08-19，rc.8 时期） | 事故复盘；**未随新版更新，也不需要** |
| `docs/SSH-REMOTE.md` | 🕘 仅作跳转说明 | SSH 插件本体在独立仓库 [dsh-ssh-remote](https://github.com/chai1110/dsh-ssh-remote)，**维护已暂停、不再跟进 0.1.5+** |
| `SECURITY.md` | ➖ 与版本无关 | 漏洞上报联系方式 |

**未适配的版本**：官方 **alpha 预发布线**（如 `0.1.2-alpha.2`）**未适配** —— 仅做过预研（见 `ADAPTING.md`）。
本仓库只承诺上表标注「✅」的版本。

> 这里的「适配」指：**补丁能在该版本上干净套用、并通过校验**；
> 它**不等于**本仓库每个文档都重写过 —— 上面这张表就是用来区分这件事的。

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
- 更早的消息只保留复制，不可编辑；AI 正在工作时不允许编辑（防冲突）
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
| **macOS** | ✅ 原生支持 | 自带的 `bash`/`patch` 即可（`pgrep` 也已内置） |
| **Linux** | ✅ 原生支持 | 自带 `patch`；部分精简发行版需 `sudo apt install patch` |
| **Windows** | ✅ 推荐用上面的 Node 安装器 | 纯 Node 实现，不依赖 `patch`/`pgrep`/`cp`/`find`，**没有路径分隔符问题**。若仍用 shell 版：Git for Windows 提供 `bash`；重启请用 `taskkill //F //IM node.exe`（`pgrep` 在 Windows 不存在） |

**统一前置条件**（任意平台）：
- 已安装 **Node.js**（含 `npm`）
- 已用 npm **全局安装 `@deepseek-ai/dsh`**（本仓库 main 适配 `0.2.0-rc.1`；其他 DSH 版本用户 checkout 对应 tag，见「多版本支持」）；或用源码构建（见「源码构建（monorepo）用户」）

> **不装命令行工具也能用**：最省事的办法是把这个仓库链接（`https://github.com/chai1110/dsh-custom-patches`）发给你的 AI 助手，让它按本文档的「快速开始」在你的机器上完成安装与配置——它会自行处理 Windows 的 `taskkill` 等差异。

---

## 🚀 快速开始（各平台通用）

一共四步，**推荐用 HTTPS 克隆**（无需配置 SSH key）。把这整段丢给 AI 也能照着完成：

```bash
# 1) 安装匹配版本的 DSH（已装且版本正确可跳过）
npm install -g @deepseek-ai/dsh@0.2.0-rc.1
dsh --version          # 应输出 0.2.0-rc.1

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
> **shell 版仍然可用**：`bash install-dsh-custom.sh -y`（主安装器）、`bash apply-dsh-patches.sh`（备选）。二者与 Node 版套用同一套补丁，按需选用。

然后**硬刷新**浏览器页面（`Cmd+Shift+R` / `Ctrl+Shift+R`）：
- 输入框按 **↑** 即可翻历史
- 最后一条用户消息 **hover（鼠标悬停）** 出现 **✏️ 编辑** 按钮

> 也可以把本仓库链接 `https://github.com/chai1110/dsh-custom-patches` 直接发给你的 AI 助手，
> 让它按本文档的「快速开始」步骤在你的机器上完成配置；文档中的命令均可直接执行。

---

## 🧩 多版本支持（不同 DSH 版本的用户都能用）

**不同用户可能装在各自的 DSH 版本上——本项目为每个已适配的版本都保留了独立补丁文件，老版本用户无需升级官方即可使用同一套功能。**

| 你的 DSH 版本 | 适配情况 | 一键安装命令 |
|---|---|---|
| **0.2.0-rc.1**（官方 `next`） | `v0.2.0-rc.1`（默认 main） | `git clone` 后直接 `bash install-dsh-custom.sh -y` |
| 0.1.7-rc.2（官方 `latest`） | `v0.1.7-rc.2` | `git checkout v0.1.7-rc.2` 后 `bash install-dsh-custom.sh -y` |
| 0.1.5-rc.1 | `v0.1.5-rc.1` | `git checkout v0.1.5-rc.1` 后 `bash install-dsh-custom.sh -y` |
| 0.1.2-rc.1 | `v0.1.2-rc.1` | `git checkout v0.1.2-rc.1` 后 `bash install-dsh-custom.sh -y` |
| 0.1.1-rc.2 | `v0.1.1-rc.2` | `git checkout v0.1.1-rc.2` 后 `bash install-dsh-custom.sh -y` |
| 0.1.0-rc.8 | `v0.1.0-rc.8` | `git checkout v0.1.0-rc.8` 后 `bash install-dsh-custom.sh -y` |
| 0.1.0-rc.7 | `v0.1.0-rc.7` | `git checkout v0.1.0-rc.7` 后 `bash install-dsh-custom.sh -y` |
| 0.1.0-rc.6 及更早 | ❌ | 无独立补丁（仓库自 rc.7 起发布），建议升级官方后使用 |

> **为什么用 tag 而不是参数？** 官方每个版本的补丁内容不同（尤其 0.1.2-rc.1 是架构重构版），
> 用 tag 把「补丁文件 + 安装脚本」打包成该版本专用快照，最干净也最不容易出错。
> checkout 对应 tag 后，脚本会校验本机 DSH 版本与 tag 一致；不一致会明确报错并提示 checkout 正确的 tag。

---

## 🛠 分步说明（想了解细节再看）

### 第 1 步：确认 DSH 版本
```bash
npm install -g @deepseek-ai/dsh@0.2.0-rc.1   # 装到匹配版本（老版本用户装自己那版即可）
dsh --version                                 # 确认是 0.2.0-rc.1
```

### 第 2 步：克隆仓库
HTTPS（推荐，任何机器可用）：
```bash
git clone https://github.com/chai1110/dsh-custom-patches.git
cd dsh-custom-patches
```
SSH（可选，需你已在自己机器上配好 GitHub SSH key）：
```bash
git clone git@github.com:chai1110/dsh-custom-patches.git
cd dsh-custom-patches
```

### 第 3 步：运行安装脚本
推荐用带诊断与内置检测的**一键脚本**：
```bash
bash install-dsh-custom.sh -y
```
脚本会自动：
1. 定位 DSH 安装目录（同时探测系统级与用户级全局路径）
2. 读取本地版本并查询 npm 官方最新版，给出版本诊断
3. **校验版本**（本仓库 main 期望 `0.2.0-rc.1`；不匹配会拒绝并提示 checkout 正确的 tag）
4. **检测官方是否已内置功能**——若目标文件已含功能标记（例如官方新版把这些功能收编了），自动跳过对应补丁
5. 对需要应用的补丁**逐一备份（生成 `.bak`）并应用**
6. 汇总报告 + 提示重启

> 备选：`bash apply-dsh-patches.sh`（功能相同，但没有版本诊断与内置检测；两者等效地应用同一套补丁，任选其一即可）。老版本用户请 checkout 对应 tag（该脚本不接受版本参数）。

### 第 4 步：重启 DSH
```bash
kill $(pgrep -f 'dsh web') 2>/dev/null; sleep 1; dsh web
```

### 第 5 步：验收（确认安装成功）
刷新页面后，检查以下**可观察信号**，全部满足即安装成功：
- [x] 输入框按 **↑** 能翻出上一条消息
- [x] 鼠标悬停到**最后一条用户消息**上出现 **✏️ 编辑** 按钮
- [x] 点击编辑 → 改内容 → 「保存并重新生成」能替换并重新生成

> 第 3 项（压缩失败重试）**没有可观察的 UI 信号** —— 它只在限流 / 网络错误时于后台生效，无需人工验收；
> 想确认它是否生效，可在会话日志里找 `llm/retry` 事件。

> 也可用脚本自诊断：再次运行 `bash install-dsh-custom.sh -y`，若输出 *"All features already present (built-in or applied). Nothing to do."* 即表示所有功能已就位。

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
- **跳过 npm 版本校验**（源码没有 `0.2.0-rc.1` 这种版本号），但请确认你的源码 checkout 对应最新 rc 或对应版本时代的代码
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
# 1) 检测官方是否有新版（自动对比本地/最新/适配版本；也可指定版本：bash check-update.sh 0.1.0-rc.8）
bash check-update.sh

# 2) 升级官方
npm install -g @deepseek-ai/dsh@<新版本>

# 3) 重新应用（含内置检测；若官方新版没大改则直接成功）
bash install-dsh-custom.sh -y
```

- **官方是否已内置我们的功能？** 一键脚本会自动检测并跳过已内置的补丁；也可手动用 [`versions.md`](versions.md) 里的 grep 方法确认。
- **补丁失效了？** 按 [`ADAPTING.md`](ADAPTING.md) 的操作手册重新适配，并在 `versions.md` 追加新版本一行。

> ⚠️ 若升级后 `patch` 报错，说明新版改了相应代码，需要按 `ADAPTING.md` 重新适配。

---

## 📦 项目结构

```
dsh-custom-patches/
├── install-dsh-custom.sh   # 一键安装（推荐）
├── apply-dsh-patches.sh    # 备选安装（无版本诊断/内置检测）
├── check-update.sh         # 检测官方是否有新版本
├── versions.md             # 版本追踪表
├── ADAPTING.md             # 适配官方新版的操作手册
├── patches/                # 补丁文件（按包分目录）
├── docs/SSH-REMOTE.md      # 指向独立仓库 dsh-ssh-remote（已暂停维护）
├── POSTMORTEM.md           # 历史事故复盘（rc.8 时期）
├── SECURITY.md             # 漏洞上报方式
└── LICENSE                 # MIT
```

---

## 🤝 贡献与反馈

小项目，**没有单独的贡献指南** —— 有事直接开 [Issue](https://github.com/chai1110/dsh-custom-patches/issues) 或提 PR 就行。

- **报问题**：附上现象、环境（`dsh --version` / 操作系统 / Node 版本）、复现步骤、期望结果；
  有 `patch` 的 `Hunk #N failed` 输出最好。
- **提 PR**：欢迎新增功能补丁或修复适配。硬性要求只有三条 ——
  ① **补丁最小化**（只改必要几处）；② 留下可 grep 的**功能标记**；③ `install-dsh-custom.sh` 与
  `apply-dsh-patches.sh` 的 `FILES` 保持同步。
- **改文档**：主入口脚本一律写 `install-dsh-custom.sh`（`apply-dsh-patches.sh` 是备选，提及请注明）；
  示例要能在全新 clone 后直接执行。
- 重新适配新版的完整流程见 [`ADAPTING.md`](ADAPTING.md)。

---

## 📄 License

MIT — 见 [LICENSE](LICENSE)。

## 📎 相关资源

- SSH 多机并行插件: [chai1110/dsh-ssh-remote](https://github.com/chai1110/dsh-ssh-remote)
- 供应商配置模板: [chai1110/dsh-provider-config](https://github.com/chai1110/dsh-provider-config)
- DeepSeek Harness 官方: [deepseek-ai/deepseek-harness](https://github.com/deepseek-ai/deepseek-harness)
