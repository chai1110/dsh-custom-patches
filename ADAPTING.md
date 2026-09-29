# 适配官方新版本（ADAPTING Guide）

> 当官方发布新版本，导致本补丁集失效时，按本指南重新适配。
> 适用人群：维护者。

---

## 何时需要适配

运行 `bash install-dsh-custom.sh -y` 后，若日志出现：
```
❌ 应用失败: <某个文件>
  可能是补丁已应用或文件已被改动
```
说明官方新版本改了对应代码，旧的补丁 hunk 不匹配，需要重新生成。

---

## 适配流程（一次完整循环）

### 第 1 步：装好新版本官方包
```bash
# 查最新版
npm view @deepseek-ai/dsh version

# 装新版（可装全局，或用临时目录隔离，避免干扰工作环境）
npm install -g @deepseek-ai/dsh@<新版本>
```

### 第 2 步：确认官方是否已内置我们的功能
**推荐**直接用一键脚本（它内置了检测，会自动跳过官方已内置的补丁）：
```bash
bash install-dsh-custom.sh -y
```
脚本会逐条判断：目标文件已含功能标记 ⇒ 视为官方已内置 ⇒ 自动跳过；否则列入待应用。

若想手动确认，也可 grep 功能标记：
```bash
PLUGIN=<全局或临时 DSH 的 node_modules>/@deepseek-ai
grep -rl "editLastPrompt" $PLUGIN/*/lib/ 2>/dev/null || echo "编辑重发：官方未内置，需保留补丁"
grep -rl "recallHistory"  $PLUGIN/*/lib/ 2>/dev/null || echo "输入历史：官方未内置，需保留补丁"
```
> 若官方某功能已内置 ⇒ 从 `patches/` 删除对应补丁，更新脚本 `install-dsh-custom.sh` 与 `apply-dsh-patches.sh` 的 `FILES` 数组及 `versions.md`，就不用再适配它。

### 第 3 步：重新实现 / 重新生成补丁
对每个失效的插件文件逐一手动重新改一遍（把功能代码补到新版对应位置），然后生成补丁：
```bash
# 假设你又在 lib/client.js 里改好了功能，且保留原始备份 client.js.bak
cd <到该插件目录>
diff -u lib/client.js.bak lib/client.js > /path/to/dsh-custom-patches/patches/client-ui-conversation/dsh-client-ui-conversation-lib-client.js.<新版本>.patch
```

> **技巧**：新版通常只是少数几行上下文变了。可先看旧补丁哪个 hunk 失败（`patch` 会输出 `Hunk #N failed`），只修正那一处，其余沿用。

### 第 4 步：更新脚本与追踪表
- 把新补丁文件名更新到 `install-dsh-custom.sh` 与 `apply-dsh-patches.sh` 的 `FILES` 数组（两者都改，保持一致）
- 在 `versions.md` 追加新版本一行
- 提交：
```bash
cd dsh-custom-patches
git add -A
git commit -m "适配官方 vX.Y.Z"
git push
```

### 第 5 步：验证
在其他设备 / 干净环境跑一遍 `bash install-dsh-custom.sh -y` 确认成功，再重启 `dsh web` 实测功能。

---

## 常见问题

| 现象 | 处理 |
|---|---|
| 某个补丁 1 个 hunk 失败，其余成功 | 手动把缺失的几行补到新版对应位置，重新生成该文件补丁 |
| 整个补丁全失败 | 官方该文件大改，需要对照功能逻辑重写 |
| 官方内置了某功能 | 删除该功能对应补丁，更新脚本和 versions.md |
| 不确定官方是否内置 | 用 `versions.md` 里的 grep 命令确认 |

---

## 保持补丁最小化

- 每次只改**必要几处**，避免为了"更像官方"而无关改动。
- 补丁尽量小 ⇒ 与新版的冲突点少，适配容易。
- 每个功能标记清晰（`editLastPrompt` 等），便于 grep 定位和排查。

---

## 预研记录：官方 `0.1.2-alpha.2`（2026-08-30 发布，alpha 预发布）

> ⚠️ 这是**预研**，不是已完成适配。`0.1.2-alpha.2` 是 alpha 预发布（npm `latest` 仍是 `0.1.1-rc.2`），且为**架构级重构**，建议等官方稳定版（`latest` 升到 0.1.2+）再实际升级适配。

### 官方变化要点

| 项 | rc.2 | 0.1.2-alpha.2 | 对我们补丁的影响 |
|---|---|---|---|
| `dsh-host-apiproxy` | 存在（我们打了 editLastPrompt 补丁） | **包消失** | 补丁失效，功能拆分到新包 |
| `dsh-client-runtime` | 存在（我们打了 unarchive 客户端补丁） | **包消失** | 补丁失效 |
| `dsh-client-connection` | 10340 行 | 4809 行 | 大幅拆分，RPC 面结构变化 |
| `dsh-client-ui-conversation` | 10453 行 | 16037 行 | 大幅扩编，需重定位补丁点 |
| `dsh-client-ui-workspace` | 2510 行 | 2739 行 | 中幅，归档设置面板补丁需重定位 |
| `dsh-agent-loop` | 1323 行 | 1387 行 | 新增 `requestSurfaceGeneration` / `startsRequestSeries` 机制 |
| `dsh-workspace` | 772 行 | 757 行 | 有 `archiveSession`+`archivedSessionIds`，**无 `unarchiveSession`** |

### 各功能适配结论（预研 + 全集 dry-run 验证）

> 以下为**补丁全集**在 alpha 上逐一 `patch --dry-run` 的实测结果（2026-08-31 复核）。

| 功能 / 补丁文件 | alpha 实测 | 行动 |
|---|---|---|
| **归档恢复·host 侧**（workspace） | ✅ `dsh-workspace-lib-index.js.alpha.patch` 已应用验证通过；workspace 官方**无 unarchiveSession**（README 明确 "no unarchive action exists yet"） | 用 alpha 补丁 |
| **归档恢复·协议侧**（client-connection） | ✅ `dsh-client-connection-lib-client.js.alpha.patch` 已应用验证通过；alpha 把 workspace 操作内联实现（非 callUnary RPC），`emitWorkspace({type:"archived"})` 广播 | 用 alpha 补丁 |
| **归档恢复·UI**（client-ui-workspace） | ❌ archive 补丁 3 hunk 中 2 失败；alpha 仍无恢复 UI，设置插槽改为 `settings.general.item` | 需按新插槽重打（指引见下） |
| **decision 消息去重**（agent-loop） | ❌ rc.2 补丁 1 hunk 全失败；alpha **未内置**该修复（`decision.messages` 循环仍是单行 append） | ✅ 已生成 `dsh-agent-loop-lib-index.js.alpha.patch` 并**实际应用验证通过** |
| **编辑重发·引擎层**（client-runtime / host-apiproxy） | ⚠️ 两包在 alpha **消失**；能力改为 alpha 原生 `session.surface.replaceGeneration`（client-connection 内联实现，`shadowedSeqs` 位置替换） | 引擎层 **官方已内置** → 删除 client-runtime 与 host-apiproxy 的 editLastPrompt 补丁，改用官方机制 |
| **编辑重发·UI 层**（client-ui-conversation） | ❌ rc.8 补丁 18 hunk 中 **16 失败**；alpha 无用户消息编辑重发入口（仅有 composer 队列 queue.edit） | 引擎层虽内置，**UI 入口未内置** → 需按 alpha 新消息渲染结构重打 |
| **输入历史**（↑/↓）（client-ui-conversation） | ❌ 同上；alpha grep `sendHistory`/`recallHistory` = 0 | 需重打补丁（指引见下） |

### 输入历史（↑/↓）alpha 重打指引

- alpha `ui-conversation` 的 `InputBar` 仍在（15094 行，`function InputBar`），但文件从 rc.2 的 10453 行扩到 16037 行——**结构大改**，rc.2 补丁的 18 个 hunk 无法直接套用，需按逻辑重写。
- 我们的标记函数：`recallHistory` / `sendHistory` / `historyIndexRef` / `historyStack`。alpha 中 grep 这些标记为 0（未内置）。
- 重打方式：在 alpha `InputBar` 组件内加 `onKeyDown`（↑/↓ 召回历史），复用 rc.2 补丁的逻辑思路（见 `patches/client-ui-conversation/dsh-client-ui-conversation-lib-client.js.rc2.patch`），替换到 alpha 的新 InputBar 结构。
- 因 alpha 未稳定且 InputBar 结构可能再变，**建议等稳定版再实施**。

### 预研产出的 alpha 补丁（可复用）

| 补丁文件 | 状态 | 说明 |
|---|---|---|
| `patches/workspace/dsh-workspace-lib-index.js.alpha.patch` | ✅ 已生成 + **实际应用验证通过** | workspace 端 `unarchiveSession`（应用后 grep=1，语法 OK） |
| `patches/client-connection/dsh-client-connection-lib-client.js.alpha.patch` | ✅ 已生成 + **实际应用验证通过** | client-connection 端 `unarchiveSession` 实现 + dispatch（应用后 grep=2，语法 OK；alpha 把 workspace 操作内联到此包，非 RPC） |
| `patches/agent-loop/dsh-agent-loop-lib-index.js.alpha.patch` | ✅ 已生成 + **实际应用验证通过** | decision.messages 去重（rc.2 补丁上下文已变，alpha 版按新 `step(assembly, startsRequestSeries)` 行重打；应用后语法 OK） |
| UI 面板（归档恢复设置项） | ⏳ 待适配 | alpha 设置插槽 `settings.section` → `settings.general.item`（与 composer-enter 同款挂载），需按新插槽重写 |
| 编辑重发 UI 层（client-ui-conversation） | ⏳ 待适配 | 引擎层官方内置，但 alpha 无用户消息编辑入口，需按新渲染结构重打 |
| 输入历史（↑/↓）（client-ui-conversation） | ⏳ 待适配 | alpha InputBar 大改，需按逻辑重打 |

> alpha 的 client-connection 里 `archiveSession` 是**直接实现**（非 callUnary RPC），`emitWorkspace({type:"archived"})` 广播——我们的 unarchiveSession 补丁按同款结构编写。

### 归档面板 UI 适配指引（alpha）

alpha 设置 UI 插槽从 `settings.section` 改为 **`settings.general.item`**（每项一个插槽，参考 ui-conversation 的 `composer-enter` 挂载方式）：
```js
ctx.slots.inject("settings.general.item", () => ctx.slots.register({
    name: "settings.general.item",
    id: "archived-sessions",   // 换成自己的 id
    order: 45,
    locale: NS,
    // inject 提供恢复动作
}, ArchivedSessionsPanel));
```
> 归档数据来源变化：alpha 里 `workspace.list.getSnapshot().archivedSessionIds` 仍在（client-connection 内联实现，`emitWorkspace` 广播），UI 通过订阅 workspace list 获取。

### 预研结论 / 建议

1. **不要现在升级 alpha**：架构重构 + 预发布不稳定 + 会覆盖当前可用环境。
2. 等官方 `latest` 升到 0.1.2 稳定版后再适配。
3. 届时按本表：先查官方是否已内置（grep 标记），再决定重打 or 删除补丁。
4. `dsh-ssh-remote` 插件的 vendored 组件（easyssh / dsh-ssh / aionui-panel）依赖 host 的 `ctx.provide("easysshCore")` 等接口，升级前需先验证这些接口在 alpha 下是否保留。

---

### 隔离验证实录（2026-08-31，用户选择「隔离验证，不碰当前环境」）

> 把 alpha 0.1.2-alpha.2 装进 `/tmp/dsh-alpha-verify`（临时目录），套上 3 个 alpha 补丁做冒烟，全程未动全局 rc.2 环境。

**重要发现：alpha.2 官方发布不完整** —— `npm install @deepseek-ai/dsh@0.1.2-alpha.2` 会失败：

- 主包依赖 `@deepseek-ai/dsh-session-turn-outline@^0.1.2-alpha.3`，但该包**整个不在 npm registry**（E404）。
- 因此即便想升级 alpha，**npm 也无法正常安装完整依赖树**——这是官方打包遗漏，非我们环境问题。
- 绕行：我们的 3 个目标包（workspace / client-connection / agent-loop）**不依赖**该坏包，可单独拉取它们的 @deepseek-ai 闭包构建最小加载树。

**验证结果（全部通过）**

| 验证项 | 结果 |
|---|---|
| 3 个补丁在 alpha 真实文件上干净套用 | ✅（从 tgz 重建后一次 apply 成功） |
| 3 个文件语法检查 | ✅ |
| 功能标记存在 | ✅ workspace unarchive=1、client-connection=2、agent-loop tailEvent=2 |
| workspace / agent-loop ESM 模块加载 | ✅（在补齐的真实 alpha 依赖树上 import 成功） |
| `unarchiveSession` 为真实 API | ✅ `WorkspaceRegistry.prototype.unarchiveSession` 是函数（enqueueOperation 过滤归档集，同 rc.2 行为） |
| client-connection | ⚠️ 是浏览器 bundle（`window.__ModuleLoader__.load`），Node 无法加载属正常，以语法+标记验证 |
| agent-loop 去重逻辑行为测试 | ✅ 3 场景全过：尾=同 id user 跳过 / 尾=assistant 追加 / 尾=不同 user 追加 |

**结论**：3 个 alpha 补丁（workspace / client-connection / agent-loop）在真实 alpha 上**可套用、可加载、逻辑正确**，可直接用于后续稳定版或修复后的 alpha 发布；唯一阻断升级的是**官方 alpha.2 漏发 `dsh-session-turn-outline`**。

### 补：dsh-ssh-remote 在 alpha 下的接口兼容性（2026-08-31 实测）

| vendored 组件依赖 | alpha 0.1.2-alpha.2 | 结论 |
|---|---|---|
| `ctx.provide("easysshCore")` / `ctx.get("easysshCore")` | ✅ client-connection 仍保留 `.provide` 服务 API | 兼容 |
| `ctx.get("sshWorkspaceMode")` | ✅ 保留 | 兼容 |
| `slots.inject("conversation.input.left")` | ✅ 保留（ui-conversation slots 契约） | 兼容（SSH 连接按钮挂载点） |
| `slots.inject("conversation.session.header.actions")` / `.utilities` | ✅ 保留 | 兼容 |
| `slots.inject("settings.section")` | ❌ 改名 `settings.general.item` | 仅影响 settings 相关挂载；easyssh 的「SSH 远程工作区」设置项本就已禁用（补丁），无实际影响 |

---

## 压缩自动重试补丁（2026-09-01）

**背景**：SenseNova 网关 TPM 限流（`429001 inference tpm exhausted`）导致大会话压缩失败。
官方 `dsh-llm-retry` 的重试只监听 `agent/request-error`（正常对话请求），压缩
（`dsh-compaction-basic` 直接 `ctx.llm.stream()`）不走该扩展点，429 直接失败且无重试。

**补丁**：`patches/compaction-basic/dsh-compaction-basic-lib-index.js.retry.patch`

- 在 `summarizeWithLlm` 内把单次 `ctx.llm.stream()` 调用改为重试循环。
- 复用 provider 的 `retryPolicy`（经 `ctx.llm.providerRetryPolicy(provider)` 读取：
  `maxRetries` / `retryableCodes` / `backoff{initialDelayMs,maxDelayMs,jitterRatio}`）。
- 仅当 `error.code` ∈ `retryableCodes` 且未超 `maxRetries`、未取消时重试；
  每次重试按指数退避 + jitter 等待，并在会话记录 `llm/retry` / `llm/retry-started` 事件。
- 复用现有 `randomUUID` 导入；新增 `compactionBackoffDelay` / `cancellableDelay` 两个局部函数。
- 配置无需新增：直接用 settings.yaml 里 `sensenova.retryPolicy`（本项目已配
  `maxRetries: 15`、retryableCodes 含 `RATE_LIMIT`、backoff 至 30s）。

**适配新版本时**：若官方重构压缩路径，检查 `summarizeWithLlm` 是否存在、是否已内置重试
（grep `compactionBackoffDelay`）。内置则删除本补丁并更新 `install-dsh-custom.sh` /
`apply-dsh-patches.sh` 的 FILES 与 `versions.md`。

---

## 0.1.2-rc.1 适配教训：浏览器端方法表 = dsh-api-remotes 冻结副本（2026-09-04）

> 复盘"编辑重发"在 0.1.2-rc.1 上三轮修复仍报
> `this.remote.session.editLastPrompt is not a function` 的根因与应对规则。

### 现象
补丁仓库适配 rc.1（commit 4f73c03）时，把 `editLastPrompt` 补进了
api-session-controller（host index.js 实现 + `@Remote` 装饰器 + typert.host.js
invocations + client.js binding + typert.remote-client.js schema/描述符）和
ui-chat（UI 按钮），重装后宿主侧 grep 标记全命中、安装日志全绿，但浏览器编辑重发
始终报 not a function。

### 根因
0.1.2 架构重构后，**浏览器端 `remote.session` 的方法表不再由各包自带的
`typert.remote-client.js` 提供**，而是来自新增包 **`dsh-api-remotes`** 的
`lib/client.js`：它是一份 tsdown 生成的 ModuleLoader bundle（`window.__ModuleLoader__.load`），
**构建期内嵌**了所有包 typert.remote-client 模型的**冻结副本**
（`//#region ../session-controller/lib/typert.remote-client.js` 等）。
浏览器启动时读这份 bundle 构造 remote 服务表；宿主进程侧的 typert.host.js
invocations 与各包自己的 typert.remote-client.js（纯 ESM 工具产物，"Generated… do not edit"）
**都不是浏览器加载的路径**。因此宿主侧实现再完备，只要 dsh-api-remotes 内嵌副本
缺该描述符，浏览器端就永远没有这个方法——而补丁仓库此前对该包的引用为 0。

### 铁律：给 @Remote 增删一个方法，需同步 5 处（0.1.2 起）
1. `dsh-api-session-controller/lib/index.js`（宿主实现 + 装饰器 + command 委托）
2. `dsh-api-session-controller/lib/typert.host.js`（宿主 invocations 描述符 + zod schema）
3. `dsh-api-session-controller/lib/client.js`（client 绑定方法）
4. `dsh-api-remotes/lib/client.js`（**浏览器端冻结副本**：schema const + 描述符，缺它 = 浏览器 not a function）
5. UI 层（如 `dsh-client-ui-chat/lib/client.js`）

### 重新生成 dsh-api-remotes 补丁的注意点
- npm 独立发布的 `@deepseek-ai/dsh-api-remotes` 包里的 `lib/client.js`（约 109KB）
  与 `@deepseek-ai/dsh` 安装树嵌套的版本（约 305KB，含全部内嵌模型）**不是同一份文件**；
  运行用的是嵌套版，补丁必须针对它生成（`diff <嵌套版原始备份> <已改嵌套版>`）。
- 嵌套版由 dsh 随包分发、无 postinstall 脚本，改后跨重启持久，但 **npm 重装 @deepseek-ai/dsh
  后需重新套补丁**（与其他补丁一致）。
- 补丁上下文取内嵌 session 区的唯一锚点（`prompt_result$schema` const 之后、
  `session/rename` 描述符之前），避免 hunk 错位。
- requestId 同步：参数 schema、client 发送体、host 读取三处必须一致
  （`SessionEditLastPromptRequest` 含 `requestId`，`source.rpcId` 用它回标）。

---

## 0.1.5-rc.1 适配实录（2026-09-10，分支 `version/0.1.5-rc.1`）

官方 `dsh-v0.1.5-rc.1`（首个 0.1.5 候选版，汇总 `0.1.2-rc.1` 以来变更）。

### 结论速览

| 项 | 结果 |
|---|---|
| 补丁可套用 | **12/12**（重打 6 个后） |
| `node --check` 语法 | 12/12 通过（本轮新增的校验关卡，**抓出 1 个真 bug**） |
| 官方已内置的我们的功能 | **无**（`editLastPrompt`/`recallHistory`/`sendHistory`/`unarchiveSession`/`message.editPrompt`/`archived-sessions` 全缺） |
| 官方**部分**收编的共享代码 | `SURFACE_EVENT_TYPES` + `isSurfaceEvent`（见下） |
| 运行时验证 | ❌ 未做（本机 DSH 仍是 0.1.2-rc.1，未升级） |

### 官方 0.1.5 与本补丁集相关的破坏性变更

- **Session 数据格式 V3**：升级后的会话日志不支持降级读取。
- **Session 生命周期**：持久化改由 `SessionHandle` 持有；`agentLoop.create()` 变异步；
  **新增 session 锁（同一 session 至多被一个进程持有）**。
- **默认工具调整**：Web `minimal` 默认只给持久 shell，`str_replace_editor` 需显式启用。
- **移除 `ctx.agent`**；**`Inbox` 改为 type-only**（`agent.inbox`，`hasPending`/`claim` 不再公开）。
- **Web 插件面板 API**：新增 `sidebar.panellist` 与 `main`；原 `conversation` Slot 迁到 `main.conversation`。
- **persona 拆分为前缀 + 后缀**；pi-ai 升至 0.85.1。

### 6 个补丁的失败原因（逐 hunk 实证）

| 补丁 | 失败 hunk | 根因 | 修法 |
|---|---|---|---|
| `agent-loop/lib/index.js` | #1（1/2） | 官方把 `user/message` append 挪进 `while(true)` 重试循环，并加 `firstAttempt` 守卫 | 换锚点：`if (firstAttempt) for (...) {...}` 外包我们的尾节点同 id 去重 |
| `api-remotes/lib/client.js` | #2（1/2） | `session/prompt` 描述符的 `sourceLocation.line` **327 → 346** | 补丁上下文行号改 346（纯元数据漂移） |
| `api-session-controller/lib/typert.remote-client.js` | #2（1/2） | 同上（327 → 346） | 同上 |
| `api-session-controller/lib/typert.host.js` | #2 | 同上；**原先靠 BSD patch 默认 fuzz=2 吃掉首行失配才侥幸通过** | 重生成后上下文自动为 346 |
| `client-ui-chat/lib/client.js` | #1、#2（2/11） | #1 官方在 `UserStyleBubble` 参数中新增 `...data.skillNames` 展开行；#2 `ChatNodeSeat` 参数 `selectedCallId` 换成 `loadImage` | 更新上下文签名 |
| `client-ui-conversation/lib/client.js` | #9、#11（2/12） | #9 字段 `imageIds` → `attachmentIds`；#11 `attachments` 的 `draftImages` → `resolveDraftAttachments`，并新增 `uploads`/`uploadsPending` 两行 | 换锚点 + 跟随改名 |
| `client-ui-workspace/lib/client.js` | #2（1/4） | `WorkspaceBrowser` 参数新增 `usePanelInfo` | 更新签名（保留官方新参数） |
| `client-ui-conversation/lib/client.js` | 语法校验发现 | **官方已在 `core/session/src/surface.ts` 原生导出 `SURFACE_EVENT_TYPES` + `isSurfaceEvent`**，与补丁插入的同名声明冲突（`SyntaxError: Identifier 'SURFACE_EVENT_TYPES' has already been declared`） | **删除补丁中的重复声明**，`isReplacementSurfaceEvent` 直接复用官方原生 `isSurfaceEvent` |

### 新增铁律 1：上下文漂移 ≠ 语义安全，必须过 `node --check`

BSD `patch` 默认 **fuzz=2**：hunk **首/尾最多 2 行**上下文失配时仍会「成功」，只提示 `offset`。
所以 `dry-run 全绿` 只能证明「能贴上」，不能证明「贴对了」。重复声明、错位插入这类问题
**只有真实套用 + 语法检查才能发现**（本轮就是靠它抓到 `SURFACE_EVENT_TYPES` 冲突）。

```bash
# 套用后必须过语法关（bundle 是 window.__ModuleLoader__.load 工厂，CJS 即可解析）
node --check <套用后的文件>
# ESM 包（api-session-controller/lib/index.js 等）改用 .mjs 副本再 --check
```

### 新增铁律 2：官方「部分收编」不会命中功能标记

`grep editLastPrompt` 这类**功能标记**检测只能发现「整个功能被官方收编」。
但官方可能只收编**共享的底层工具函数**（本轮：`SURFACE_EVENT_TYPES`/`isSurfaceEvent`），
此时功能标记仍然 miss，而插入会造成重复声明。→ 必须叠加上一条的语法校验。

### 重生成补丁的推荐姿势（本轮采用）

1. `npm pack` 目标包 → 解包到隔离目录（`npm install` 到 /tmp 会被 broker 拦，`pack` 可以）。
2. `patch -N -p2` 把**旧补丁**贴到新版文件：能贴的自动贴，贴不上的落 `.rej`。
3. 对着 `.rej` 手工重锚（按新版真实上下文），顺手删掉官方已收编的重复声明。
4. `diff -u <pristine> <已改>` 重生成补丁，头部路径写成 `@deepseek-ai/<pkg>/lib/<file>`（保持 `-p2` 语义）。
5. 三道校验：`patch --dry-run -N -p2` 零失败 → 真实套用 → `node --check`。

> 本轮工具脚本留在 `~/Documents/dsh_data/.probe015/`（`dryrun.py` / `hunkstat.py` / `regen.py`），
> 下个版本可直接复用。

### 0.1.5 下 dsh-vscode-lite / fork 的兼容性结论（实证）

- **dsh-lite（自研 VS Code 插件）RPC 契约完全兼容**：0.1.5 的 @Remote 方法表**没有删除任何**
  其依赖的方法（`session/list`、`session/follow`、`session/rename`、`session/prompt`、
  `workspace/follow`、`workspace/archiveSession`、`commands/*`、`goals/*`、`$events` 全在），
  仅新增 `workspaceFiles/*`、`fileUploads/upload`、`sessionFeedback/record`、`goals/get`。
  `dsh-api-workspace-controller` 在 0.1.2-rc.1 与 0.1.5-rc.1 之间**逐字节相同**。
  `session/list` 的 projections 为**兼容扩展**（新增 `inbox`/`subagentCatalog`，`title` 仍在）。
  ⚠️ 行为级风险两条：**session 锁**（同库多实例并存）与 **Session V3 单向迁移**（不要混跑 0.1.2/0.1.5）。
- **dsh-vscode（fork）的宿主层未受影响**：启动就绪行格式 `dsh web: <url>[ (LAN: <url>)]`
  与 `connection.authenticatedUrl()`、`BrowserAuth` 401/换 cookie 机制在 0.1.5 **未变**；
  fork 的解析正则 `/dsh web: (https?:\/\/[^\s)]+)/` 天然忽略 ` (LAN: …)` 后缀。
  但 `dsh-client-connection` 内部改动较大（index.js 221 行 / client.js 3121 行差异，
  新增流式请求体路由），本地鉴权代理的**大文件上传**路径需回归。
- **dsh-ssh-remote 的挂载点全部保留**：`sidebar.workspaces.directoryFlow`、
  `conversation.session.header.utilities`、`conversation.input.left/right`、
  `conversation.composer.bar`、`settings.general.item` 在 0.1.5 均存在
  （`settings.*` slot 全集逐项一致）。仍需人工确认 host 侧 `systemPrompt.section` 与
  persona 前缀/后缀拆分、以及 `ctx.agent` 移除对其 vendored 子包的影响。

---

## 0.1.7-rc.2 适配记录（2026-09-26）

- **官方收编清单（补丁相应删除）**：archiveSession / unarchiveSession / insertSessionBefore / forkSession（客户端与 host 全链路原生提供）、DirectoryBrowseError（client-ui-workspace + api-workspace-controller 原生）。`client-connection` 补丁退役（0.1.7 的 client-connection 已无 archiveSession 相关代码，实现迁移至 client-ui-workspace）。
- **仍缺失、补丁保留**：editLastPrompt（编辑重发全链路）、recallHistory/sendHistory（输入历史）、compaction 重试（llm/retry 规避）。
- **2026-09-28 补记 · 归档相关补丁全部退役（11 → 9 项）**：经实测核对，官方 0.1.7-rc.2 已提供**完整的归档/恢复链路** —— `archiveSession` + `unarchiveSession`（host 与客户端全链路）、侧边栏三态筛选（隐藏归档 / 全部会话 / 仅归档）、归档行内「取消归档」按钮、搜索结果里的恢复、以及归档提示自带的 **undo**。
  > 📌 计数口径：本轮退役的是 `workspace` + `client-ui-workspace` **2 项**（11 → 9）；
  > `client-connection` 是**更早一轮**在 0.1.7-rc.2 适配期退役的（12 → 11，见上一节）。
  > 因此「12 → 9」是**跨两轮**的累计结果，不是本轮数字 —— 本轮为 **11 → 9**。
  因此本仓库**不再重复实现**，删除了两个补丁文件与两条 `FILES` 条目：
  - `patches/workspace/dsh-workspace-lib-index.js.patch`（host 侧 `unarchiveSession`，此前已被内置检测自动跳过）
  - `patches/client-ui-workspace/dsh-client-ui-workspace-lib-client.js.patch`（设置面板「已归档会话」列表）
  > 附带修掉一个缺陷：后者把 `ctx.slots.inject("settings.section", ...)` 整块写了两遍（同一 `id: "archived-sessions"`），
  > 而官方 `SlotCore` 对 list slot 的重复 `id` 会**直接抛错**（`list slot "X" already has an entry with id "Y"`），
  > 表现为控制台多一条报错。删除后该问题一并消失。
  > 同时把 `apply-dsh-patches.sh` 里**硬编码的恢复清单**改为从 `FILES` 动态生成（此前仍列着已删文件）。
- **0.1.7 结构变化与重锚要点**：
  - typert schema 全面改 lazy `??=` 风格（`let _X$value; const _X = () => (_X$value ??= z/object({...}))`），editLastPrompt schema 按同风格插入；
  - api-remotes codec 字段 `schema:` → `create:`（方法表条目同步改写）；
  - api-remotes 方法表区域重排（job-controller 块前移），editLastPrompt 条目改插在 `session/rename` 前；
  - client-ui-chat：ChatNodeSeat/ChatView 签名重构（新增 `useChatGroup`/`useConversation`/`openSkill`/`openExternalLink` 等，移除 `historyIncomplete`/`compactTranscript`/`useTranscriptView`），editLastPrompt 经 `seatProps` 流入 ChatNodeList；`messageDefinition.match` 保留 replacement 分支（编辑重发渲染的核心）；渲染尾部 0.1.7 用 `scroll.*`/`pendingInputs` 重构，旧结构作废；
  - client-ui-conversation：composer keymap 0.1.7 提供 `installDraftKeymap` 薄封装，**不支持 arbitrate 覆盖** → 输入历史需直调 `registerComposerKeymap` 并包裹 `keyboard.arbitrate`；`intakeFiles` 新签名 `(files, directories)`；
  - compaction-basic：消息构造 `createUserMessage` → `deepFreeze`，重试 hunk 的锚点随行号漂移重打。
- **验证**：dry-run 11/11 零失败 → 全新副本真实套用 11/11 → node --check 全通过 → 功能标记计数与 0.1.5 参考成品一致（editLastPrompt 11/11、recallHistory 3/3、sendHistory 3/3）→ 套用后真机运行时验证通过（见 versions.md）。

### 0.1.7-rc.2 运行时验证发现的两个真 bug（2026-09-27 已修）

1. **`IconEditOutline16` 不存在**：编辑按钮图标名是 0.1.5 primitives 的，0.1.7 改名
   `IconEditOutlineRegular` → isLastUser=true 渲染 extraActions 时 TypeError →
   **整条用户消息气泡崩溃消失**（用户报「编辑后消息不见了」的真凶）。已换新名。
2. **lastUserKey 扫错了列表**：原补丁扫 `order`，但 0.1.7 ChatView 实际渲染
   `groupedEntries`（分组视图），order 与之脱节 → lastUserKey 恒 null → 编辑按钮
   永不出现。已改为扫 `groupedEntries ?? order`。（该 bug 自 0.1.5 就存在，当时
   标注「未运行时验证」故未暴露；另 0.1.5 的 `kind === "user"` 判定本身正确，
   node.kind 确为 "user"，key 字符串里的 "input-message" 是 definition kind。）
3. 验证方式：浏览器实录——发消息→点编辑→改文本→保存重发→两轮对话均正常显示。

---

## 0.2.0-rc.1 适配记录（2026-09-28）—— ⭐ 首个「零改动」适配

**结论：9 个补丁一个字都没改，直接可用。** 这是本仓库第一次遇到官方大版本更新却完全不需要重打锚点。

> 版本背景：`0.2.0-rc.1` 是官方 `0.2.0` 系列首个候选版，发布在 **`next`** 频道
> （`latest` 仍是 `0.1.7-rc.2`），2026-09-28 发布，是 `0.1.7-rc.2` 之后的首个版本。

### 为什么这次不用改

**官方这次没碰我们 9 个补丁的任何一个锚点区。** 逐文件对比两个版本的行数：

| 目标文件 | 0.1.7-rc.2 | 0.2.0-rc.1 | 差异行 |
|---|---|---|---|
| `dsh-api-session-controller/lib/index.js` | 3189 | 3189 | **0** |
| `dsh-api-session-controller/lib/typert.remote-client.js` | 1288 | 1288 | **0** |
| `dsh-compaction-basic/lib/index.js` | 1027 | 1027 | **0** |
| `dsh-api-session-controller/lib/typert.host.js` | 3059 | 3059 | 4 |
| `dsh-api-session-controller/lib/client.js` | 3674 | 3675 | 5 |
| `dsh-agent-loop/lib/index.js` | 1966 | 1981 | 29 |
| `dsh-client-ui-conversation/lib/client.js` | 18401 | 18465 | 114 |
| `dsh-api-remotes/lib/client.js` | 13040 | 13314 | 274 |
| `dsh-client-ui-chat/lib/client.js` | 12420 | 12552 | 276 |

有文件改动（`dsh-api-remotes` 改了 274 行、`dsh-client-ui-chat` 改了 276 行），
但**改动都落在锚点区之外** —— 所以补丁照样套得上。

### ⭐ 新增铁律 3：`patch` 默认允许 2 行模糊，「干净套用」不等于「锚点没漂」

`patch` 默认的 fuzz factor 是 **2** —— 它能在**上下文对不上 2 行**的情况下照样成功。
这意味着 `patch --dry-run` 返回 0 **并不能证明锚点精确匹配**。

**必须用 `-F 0` 复测：**

```sh
patch --dry-run -N -F 0 -p1 <target> < <patch>   # -F 0 = 零模糊，锚点必须逐字对上
```

本轮两轮结果一致（都 9/9），所以可以确信锚点真的没漂。
**若 `-F 0` 失败而默认通过 —— 说明锚点已漂，必须重打，否则套用位置可能错位。**

### 验证清单（全部通过）

| 检查项 | 结果 |
|---|---|
| `patch -F 0`（零模糊）dry-run | **9/9** |
| 真实套用 | **9/9** |
| `node --check`（套用后） | **9/9** |
| 端到端跑 `install-dsh-custom.sh -y` | **9/9 成功**，9 个 `.bak` 齐全 |
| 幂等性（二次运行） | ✅ 正确识别 9 个标记并全部跳过 |
| 运行时 API 存活 | `ctx.llm.providerRetryPolicy`、`session.surface.nodes`、`session.eventAt`、`isReplacementSurfaceEvent` **全部仍在** |
| 官方是否已内置我们的功能 | ❌ `editLastPrompt` / `recallHistory` / `sendHistory` / `message.editPrompt` / `compactionBackoffDelay` **一个都没有** |

> ✅ **真机运行时验证已完成（2026-09-29）**：本机安装 `0.2.0-rc.1` 真机运行后，
> 静态校验覆盖不到的 4 个 bug 已全部暴露并修复，见文末「真机运行时验证发现的 4 个 bug」。

### 官方 0.2.0 的改动中，与本补丁集相关的

从 release notes 与实测代码对比，只有一处需要判断：

- **官方在 `dsh-agent-loop` 新增 `ToolCallRecovery`**（对应 release note
  「修复工具调度异常后对话无法继续的问题；已执行但结果未知的操作会提示先核实副作用，不盲目重试」）。
  实现方式是 `session/event` 监听 + 在 catch 里补 `tool/result`。
  **判断：与本补丁不是同一件事，保留。** 我们的 agent-loop 补丁做的是
  ① 给错误对象加 `__stack`（诊断增强）② `user/message` 去重（尾部已是同 id 就不重复 append）。
  官方的 `ToolCallRecovery` 修的是工具结果丢失，两者机制不同、可共存。

其余 release note 条目（动画间距、图片重传、桌面更新提示、未命名会话、插件管理界面、
深色主题开关、Office/PDF 预览选区、Windows 沙箱权限诊断、macOS 录音权限、Safari 刷新恢复、
Linux npm 安装）**均不涉及我们打补丁的 6 个包**。

- **自动化任务改由可选插件包提供** → 依赖闭包只新增 `dsh-experimental-schedule-bundle`，
  其余 81 个包一个没少（`0.1.7-rc.2` 81 个 → `0.2.0-rc.1` 82 个）。
  ⭐ **这顺便证伪了一个误判**：光看主包 `package.json` 的**直接**依赖会以为
  `dsh-agent-loop` / `dsh-api-session-controller` 等包「消失了」—— 其实它们是**传递依赖**，
  从来就不在直接依赖里。**判断「包还在不在」必须解析完整依赖树，不能只看主包的直接依赖。**

### 本轮改了什么（只有版本常量与文档）

- 3 个脚本的版本常量：`TARGET_VERSION` / `TARGET` → `0.2.0-rc.1`
- `README.md` / `README.en.md`：适配版本、安装命令、多版本支持表、文件状态表
- `versions.md`：新增 0.2.0-rc.1 行，0.1.7-rc.2 降为「上一基准」
- 本文件：本节

**补丁文件初版零改动**；真机验证后修了补丁内 3 处键名/codec 问题（另修安装脚本 1 处），见文末小节 —— 修复只动 `+` 新增行，不碰锚点，`patch -F 0` 仍 9/9。

---

## 0.2.0-rc.1 真机运行时验证发现的 4 个 bug（2026-09-29 已修）

静态校验（dry-run / 真实套用 / `node --check`）能证明「补丁套得上」，但证明不了「套上之后是对的」。真机运行后暴露以下 4 个问题，均已修复并回归通过：

1. **typert codec 写了 `schema:` 而不是 `create:`**（`api-session-controller` 的 `typert.host.js` / `typert.remote-client.js`）。
   0.1.7 起 codec 方法表的键名是 `create:`；写成 `schema:` 会让 strict 定义注册失败，
   连带 `permissionPresets` / `llm` / `agentPresets` 三个 surface 全部 `withdrawn`，设置页空白。
2. **`surfaceOp` 用了 `start:` / `end:`**（`api-session-controller/lib/index.js` 的 `editLastPromptOnce`）。
   `isReplaceOp` 要求该对象**恰好 3 个键**（`op` / `startSeq` / `endSeq`），多出 `start`/`end` 就判非法 →
   `session/edit-rejected: ... carries an invalid replace surfaceOp`，**编辑上一条消息一按重新生成就报错**。改用 `startSeq` / `endSeq` 后正常。
3. **`scanShadowed` 读了 `op.start` / `op.end`**（`client-ui-conversation/lib/client.js`，两处）。
   同上，replace surfaceOp 的真实键是 `startSeq` / `endSeq`；读到 `undefined` 后
   `for (seq = undefined; undefined <= undefined; ...)` 循环体一次都不执行 → `shadowed` 集合恒空 →
   `matchInput` 永不跳过被替换的事件 → **编辑重发后，旧的那一轮（旧提问 + 旧 AI 回复）仍然留在会话里**，
   新消息追加在后面，同一句话出现两遍。
   > 交叉印证：同文件官方代码 L1066 / L1077 / L1078 用的正是 `op.startSeq` / `op.endSeq`。
   > 这是用户 2026-09-29 直接报上来的现象。
4. **`apply-dsh-patches.sh` 的版本检测在 Windows 下必失败**。
   `node -e "require('$DSH_DIR/package.json')"` 里 `DSH_DIR` 是反斜杠路径，
   `\n` / `\U` 被 JS 当转义序列 → 抛错 → `VERSION` 为空 → 脚本直接 `版本不匹配` 退出。
   改为 `require(process.argv[1])` 并把路径作为**参数**传入。

### 回归

- `node --check` 通过；
- 9 个补丁在 pristine `0.2.0-rc.1` 上仍 **9/9 可套用**（4 处修复只动 `+` 新增行，不碰上下文锚点）；
- 真机功能验证：编辑重发 → 旧轮次即刻从会话消失，只留下替换后的新一轮。
