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
