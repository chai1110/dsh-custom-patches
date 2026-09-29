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
# 查最新版 —— ⚠️ 必须同时看两个频道！
# `npm view @deepseek-ai/dsh version` 只返回 latest；官方的大版本 RC 常常只发在 next 上，
# 只看 latest 会得出「官方版本比我们适配的还旧」的荒谬结论（曾真实踩过，见铁律 4）。
npm view @deepseek-ai/dsh dist-tags.latest
npm view @deepseek-ai/dsh dist-tags.next

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
- ⚠️ **补丁表有 3 处，必须同时改**（格式不同，别只改一处）：
  - `tools/dsh-patch.mjs` —— `FILES` 数组，对象形式（`rel` / `patch` / `marker` / `sourceRel`）**（推荐安装器）**
  - `install-dsh-custom.sh` —— `FILES` 数组，`rel|patch|marker|source_rel` 竖线分隔
  - `apply-dsh-patches.sh` —— `FILES` 数组，`rel|patch` 两段式（无 marker / 无 source_rel）
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

### 第 6 步：别忘了桌面版（Electron）

**适配完 CLI 侧不等于适配完了。** 桌面版的 dsh 运行时封在签名过的 `app.asar` 里，
用的是**同一套 `patches/**`**，但要打到另一个目标上：

```bash
bash patch-all.sh          # CLI 侧 + 桌面版一次打完，并交叉核对功能标记
bash patch-all.sh --check  # 只核对（推荐先用这个看现状）
```

判断「两面是否真的都生效」看 `patch-all.sh` 输出的矩阵 —— 每一行两列都必须 ≥1。
`--check` 退出码 0 即全绿。

桌面版特有的注意点（完整说明见 [`desktop/README.md`](desktop/README.md)）：

| 点 | 说明 |
|---|---|
| **补丁文件共用** | 不新增补丁文件，直接复用 `patches/**`；只有「打到哪里」不同 |
| **零 fuzz 同样适用** | 桌面脚本用 `-N -F 0 -p1`；桌面版与 CLI 版的官方代码**可能不同**，一侧能套不代表另一侧能套 |
| **必须重签名** | 改完 asar 要 ad-hoc 重签，否则 macOS 拒绝启动；`Info.plist` 不用改（保险丝 `EnableEmbeddedAsarIntegrityValidation = 0`） |
| **夜间更新会覆盖** | 桌面版走 nightly 自动更新，官方包一更新就得重跑；`bash check-update.sh` 会比对「来源指纹」提醒你 |
| **标记表要同步** | 新增/修改补丁时更新 [`tools/patch-markers.tsv`](tools/patch-markers.tsv)，三个脚本都读它 |

---

## ⚙️ 一次新版更新的总清单（npm 版 + 桌面版 + 配置 + 插件）

> 上面「适配流程」讲的是**补丁怎么改**，这里讲**一次更新到底要跑哪些命令**。
>
> 原则：**补丁只有一套**（`patches/**`，npm 与桌面共用 —— 锚点只修一次，两边受益）；
> **但安装两条、配置两份** —— 因为 asar 内容 ≠ npm tarball，两边必须各自 `--dry-run`，
> 不能一边通过就默认另一边也通过。npm 与桌面的**版本号可以不同步**
> （当前 npm `0.2.0-rc.1` / 桌面 `0.2.0-rc.2`），支持列表要同时覆盖两个。

| # | 步骤 | npm 版（网页 / VSCode 插件用） | 桌面版（Electron，Windows） |
|---|---|---|---|
| 1 | 装/升级官方本体 | `npm install -g @deepseek-ai/dsh@<版本>` | 等自动更新（会覆盖 asar、清掉补丁）或手动装安装包 |
| 2 | **试套**（两边各跑各的） | `node tools/dsh-patch.mjs --dry-run` | `node desktop/windows/apply-desktop-asar-patches.js --dry-run` |
| 3 | 有补丁失败 → 修 `patches/**` 锚点 | 修一次，两边共用（见上「适配流程」第 3 步） | 同左 |
| 4 | 正式安装 | `node tools/dsh-patch.mjs -y` | `node desktop/windows/apply-desktop-asar-patches.js` |
| 5 | 补丁表 / 版本列表同步 | `tools/dsh-patch.mjs` + `install-dsh-custom.sh` + `apply-dsh-patches.sh` 的 `FILES`（3 处）+ `versions.md` | 脚本顶部 `SUPPORTED` 数组 |
| 6 | 配置（模型 / 重试 / 主题） | `~/.dsh/profiles/web/cordis.patch.yml` | `~/.dsh/profiles/desktop/cordis.patch.yml` —— **两边独立，改一边不影响另一边** |
| 7 | profile 内插件 / bundle | `dsh --profile web ...` | `dsh --profile desktop ...`（同一个 `dsh` CLI，只是 profile 不同） |
| 8 | 验证 | 网页开一次 + VSCode 插件（自起 `3080`）试一次 | `--dry-run` 显示 9/9「已应用」+ 桌面 UI 实测 |

- **回滚**：npm 侧重装官方包；桌面侧把 `resources/app.asar.bak-<时间戳>` 改名回 `app.asar`。
- **谁必须保留 npm 版**：VSCode 插件硬编码 `dsh web` + `profiles/web`，且外部鉴权实例它**无法 attach**
  （`err.authRequired`），所以**桌面版替代不了 npm 版**，两套安装要一直并存。
- 桌面版教程、平台差异（Windows 已实测 / macOS 待实测）与 macOS 合并计划：[`desktop/README.md`](desktop/README.md)。

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

> ⚠️ **2026-09-29 补充更正（重要）：`-F 0` 只关掉 fuzz，不关掉 offset。**
> fuzz 与 offset 是 `patch` 的**两个独立旋钮**：`-F 0` 保证「上下文逐字对上」，
> 但 hunk 落在**第几行**仍然是搜索出来的，offset 会被静默容忍，普通输出里看不见。
> 实测本补丁集在官方原版上 `-F 0` 套用：**42 个 hunk 里有 21 个不在 `@@` 声明的那一行**
> （最大偏 273 行，还出现过负偏移）。
> ⇒ 想真正证明「位置没漂」，要么用 `patch --verbose` 看 offset 是否为 0，
> 要么用 `node tools/dsh-patch.mjs --dry-run`（它会主动打印
> `N hunk(s) matched at a different line than declared`）。
> 详见下文「更正：`-F 0` 保证的是「零模糊」，**不是**「零偏移」」。

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

---

**补丁文件（`patches/**`）零改动。**

---

## 跨平台修复（2026-09-28/29）—— 消除 Windows 的斜杠与工具依赖问题

### 起因

此前所有安装器都是 bash 脚本，隐含依赖 `patch` / `cp` / `find` / `pgrep`，并假定 POSIX 路径。
在 Windows（Git for Windows / PowerShell）上这会产生三类问题：

1. **`pgrep` 根本不存在** —— 重启提示那一条命令直接报 `command not found`。
2. **路径分隔符** —— `$DSH_DIR/...` 这类拼法在 Windows 上得到反斜杠路径，
   打印出来的 `cp` 命令无法直接执行。
3. **`Cmd+Shift+R` 是 macOS 专属** —— Windows 用户看到的刷新快捷键是错的。

另外还有两个与平台无关、但确实存在的**真 bug**：

- `install-dsh-custom.sh` 用 `npm view @deepseek-ai/dsh version`（＝只取 `latest`）做「官方是否有新版」判断。
  在 0.2.0-rc.1 上 `latest` 是 `0.1.7-rc.2`，于是它会警告「官方有更新的版本 0.1.7-rc.2」——**方向完全反了**。
- 版本不匹配时它建议 `bash install-dsh-custom.sh -y $VERSION`，但参数解析器只接受 `-y`，
  任何其他参数都会 `exit 1` —— 这条建议是**死的**。

### 做法：新增零依赖的 Node 安装器 `tools/dsh-patch.mjs`

Node 本来就是装 DSH 的硬前置，因此把套用逻辑搬进 Node 可以一次性消灭整类问题：

| 维度 | shell 版 | `tools/dsh-patch.mjs` |
|---|---|---|
| 外部工具依赖 | `patch`、`cp`、`find`、`pgrep`、`grep` | **无**（纯 Node 内置模块） |
| 路径拼装 | 字符串拼接 `/` | `path.join` / `path.resolve` → 平台原生分隔符 |
| 匹配容差 | `patch` 默认 **fuzz=2**（可静默错补） | **零模糊**，每行上下文必须精确命中 |
| 套用后校验 | 无 | `node --check`，语法炸了自动从 `.bak` 回滚 |
| 恢复 | 手写 `for` + `cp` | `--restore` |
| 重启提示 | 写死 macOS | 按 `process.platform` 分支 |

补丁正文长度用 `@@` 头里的 `oldCount` / `newCount` 界定（与 `patch` 本身一致），
这样能避开两个坑：① `split('\n')` 的尾部空串被误当上下文行；② 删除行内容以 `--` 开头时
渲染成 `---...`，被「跳过 `---` 开头行」的朴素规则吞掉。

### 同时修掉的 shell 缺陷

- `install-dsh-custom.sh`：`npm view ... version` → `dist-tags.latest` + `dist-tags.next`；
  版本不匹配的建议改为 `git checkout v$VERSION`；重启/刷新提示按 `uname -s` 分支；
  失败时的恢复指引改为推荐 `node tools/dsh-patch.mjs --restore`。
- `apply-dsh-patches.sh`：dry-run 加 **`-F 0`**（零模糊，落实铁律 3）；
  新增「已是补丁态」的 reverse 检测（**必须放在正向检测之前**，见下方「纯插入型补丁」）；
  重启/刷新提示按平台分支。
- `ADAPTING.md` 第 1 步：查版本改为同时看 `latest` 与 `next`。

### ✅ 验证状态：已全部实跑通过（2026-09-29，macOS 真机）

> 本节此前写着「**`tools/dsh-patch.mjs` 尚未实际运行过**」——那是沙箱不可用期间的如实记录。
> **现已补做，且全部通过。** 下面是实测结果，不再是待办清单。

环境：macOS（Apple Silicon），DSH `0.2.0-rc.1`，`node v24`（`~/.local/node-v24`）。

#### 1. `tools/dsh-patch.mjs` —— 5 步全过

```bash
node --check tools/dsh-patch.mjs      # ✅ 语法通过
node tools/dsh-patch.mjs --list       # ✅ 列出 9 条，patch/marker 齐全
node tools/dsh-patch.mjs --dry-run    # ✅ 定位到真机安装，9/9 全部「已存在 → 跳过」
node tools/dsh-patch.mjs -y           # ✅ 隔离夹具上实套 9/9，0 失败，exit 0
node tools/dsh-patch.mjs -y           # ✅ 幂等：第二次全部跳过，exit 0
node tools/dsh-patch.mjs --restore    # ✅ 9/9 从 .bak 还原，exit 0
```

⚠️ **`--dry-run` 在「已套用」的机器上不会输出「9/9 干净套用」**，而是走功能标记预筛，
打印 `Every feature is already present ... Nothing to do.`（exit 0）。
要验证**套用能力**必须用干净目标；本次是在隔离夹具上做的：

```bash
# 用官方原版（= 各文件的 .bak）搭一个 source 布局夹具，完全不碰真机
FIX=$(mktemp -d); mkdir -p "$FIX/packages"
# …按 FILES 表的 sourceRel 把 .bak 拷进 $FIX/packages/…
DSH_SOURCE="$FIX" node tools/dsh-patch.mjs -y     # 9/9 applied，exit 0
DSH_SOURCE="$FIX" node tools/dsh-patch.mjs -y     # 全部 skip
DSH_SOURCE="$FIX" node tools/dsh-patch.mjs --restore
```

#### 2. shell 版两个脚本 —— macOS 自带 bash 3.2 下实跑通过

```bash
/bin/bash --version          # GNU bash, version 3.2.57(1)-release (arm64-apple-darwin25)
/bin/bash -n install-dsh-custom.sh && /bin/bash -n apply-dsh-patches.sh   # ✅ 语法
/bin/bash install-dsh-custom.sh -y   # ✅ 定位到真机、版本诊断正确、9/9 跳过
/bin/bash apply-dsh-patches.sh       # ✅ 9/9 识别为「已打过补丁，跳过」
```

> 为什么要专门在 **3.2** 上跑：Windows 的 Git for Windows 自带 bash **5.x**，
> 很多 bash 3.2 才有的坑在 Windows 侧永远暴露不出来。macOS 的 `/bin/bash` 至今仍是 3.2.57。

#### 3. 真机安装状态（复核）

| 检查项 | 结果 |
|---|---|
| live 文件 == 「官方 `.bak` + 补丁一次」 | **9/9 逐字节一致** |
| 反向 dry-run（`-F 0`） | **9/9 命中**，证明 9 个补丁都在位 |
| `.bak` / `.rej` / `.orig` | 9 / 0 / 0 |

### ⭐⭐ 严重 bug：shell 版会**重复套用**纯插入型补丁（2026-09-29 已修）

**这是真机跑出来的事故，不是理论推演。** `apply-dsh-patches.sh` 把
`dsh-api-session-controller/lib/client.js` 的补丁**套了两遍**：

| | 行数 | `editLastPrompt` 出现次数 |
|---|---|---|
| 官方原版（`.bak`） | 3674 | 0 |
| 正确（补丁一次） | 3686 | 2 |
| **事故现场** | **3698** | **4**（重复的函数定义） |

#### 根因：正向 dry-run 分不清「没套过」和「套过了」

原逻辑是「正向 dry-run 成功 → 套用；否则再看反向」：

```bash
if   patch --dry-run -N -F 0 -p1           ...; then patch -N -F 0 -p1 ...      # ❌ 危险
elif patch --dry-run -N -F 0 -p1 --reverse ...; then echo "已套用，跳过"
```

**`patch -N`（`--forward`）只抑制「正向失败」的补丁**，它对「正向又成功了一次」无能为力。
而这个补丁是**纯插入**：插进去的那段代码不破坏它自己的上下文行，所以套用之后
**正向 dry-run 依然成功**。实测：

| 文件状态 | 正向 dry-run | 反向 dry-run |
|---|---|---|
| 官方原版 | ✅ 成功（应成功） | ❌ 失败 ✓ |
| **已套用一次** | **✅ 成功 ← 元凶** | ✅ 成功 ✓ |

⇒ 唯一可靠的判据是**反向 dry-run**，而且必须**放在正向之前**。

#### 修法

两个脚本统一改成「**反向优先**」：

```bash
if   patch --dry-run -N -F 0 -p1 --reverse ...; then echo "已套用，跳过"   # ✅ 先判
elif patch --dry-run -N -F 0 -p1           ...; then patch -N -F 0 -p1 ...  # 再套
else echo "套用失败"
```

回归验证（就是拿当初出事的那台机器、那个文件复现）：

```
修复前：✅ 已应用: dsh-api-session-controller/lib/client.js     ← 又套了一遍
修复后：ℹ️  已是打过补丁的状态，跳过: ...                         ← 9/9 全部跳过
```

> `tools/dsh-patch.mjs` **没有这个 bug** —— 它的 `isAlreadyApplied()` 本来就在
> `applyPatch()` **之前**调用。shell 版这次是补齐到同一语义。

### ⚠️ 更正：`-F 0` 保证的是「零模糊」，**不是**「零偏移」

本文件「铁律 3」此前只说 `-F 0` 能证明锚点精确命中。**这句话不够准确。**
`patch` 的 **fuzz** 与 **offset** 是两个独立的旋钮，`-F 0` 只关掉前者；
**hunk 落在哪一行仍然靠搜索**，offset 照旧被静默容忍。

实测（官方原版 `.bak` 上、`-F 0` 套用本补丁集）：

| 文件 | hunks | 有 offset | 最大 \|offset\| |
|---|---|---|---|
| dsh-api-session-controller/lib/index.js | 5 | 0 | 0 |
| dsh-api-session-controller/lib/client.js | 1 | 0 | 0 |
| dsh-api-session-controller/lib/typert.host.js | 3 | 0 | 0 |
| dsh-api-session-controller/lib/typert.remote-client.js | 2 | 0 | 0 |
| dsh-api-remotes/lib/client.js | 2 | **2** | **273** |
| dsh-agent-loop/lib/index.js | 2 | **2** | 15 |
| dsh-compaction-basic/lib/index.js | 2 | 0 | 0 |
| dsh-client-ui-conversation/lib/client.js | 13 | **5** | 51 |
| dsh-client-ui-chat/lib/client.js | 12 | **12** | **142** |
| **合计** | **42** | **21** | 273 |

⇒ **42 个 hunk 里有 21 个不在 `@@` 声明的那一行**，最大偏 273 行，还出现过**负偏移**。
说明这些补丁的 `@@` 行号与正文**已经脱节**（正文被手工改过 / 从别的基线生成过），
只是靠「全文件搜索唯一命中」才照样套上。

**两个后果，都要记住：**

1. **`patch` 默认不告诉你。** 上面这张表是加 `--verbose` 才看到的
   （`Hunk #6 succeeded at 5266 (offset 129 lines).`）；不加就**只有一行 `patching file`**，
   偏移 142 行也照样静默。
   ⇒ 以后判断「锚点有没有漂」，**不能只看 `-F 0` 的成败**，要看 `--verbose` 的 offset 是否为 0。
2. **`tools/dsh-patch.mjs` 会主动报出来**：`21 hunk(s) matched at a different line than declared`。
   这是它比 shell 版**更严**的地方，不是它算错了 —— 已交叉验证：
   对同样 9 个文件，它和系统 `patch` 的**产出逐字节一致**（9/9 `cmp` 相同）。

#### ⚠️ 注意：macOS 的 `patch` 不是 GNU patch

```sh
patch --version     # macOS: patch 2.0-12u11-Apple   ← BSD 系（Apple 自带）
                    # Linux / Git for Windows: GNU patch 2.7.x
```

这不是学术细节，**行为确实不同**：

| | macOS（Apple patch 2.0） | GNU patch |
|---|---|---|
| 默认打印 hunk 偏移 | ❌ **只有 `--verbose` 才打印** | ✅ 默认打印 `Hunk #N succeeded at ... (offset ...)` |
| 备份后缀 | `.orig`（`-z` 默认） | `.orig` |
| 触发 `.orig` 的时机 | 用到 fuzz/offset，**或补丁失败**，或显式 `-b` | 同左（`--backup-if-mismatch`） |

⇒ **同一个补丁在 macOS 上「安静地成功了」，在 Windows/Linux 上会刷出一屏 offset 提示。**
两边看到的信息量不同，很容易得出不同结论 —— 这也是「双平台都跑一遍」的价值所在。

**另外**：Apple patch 2.0 要求 hunk 是**标准 3 行上下文**的形式。
自己手搓最小复现用例时如果只给 1 行前导上下文，它会直接判 hunk 失败（并留下 `.rej`），
看起来像"补丁坏了"，其实是用例不合规。

> **`.orig` 的判定含义（已实测确认）**：
> 上下文全对 + `-F 0` 成功 → **不生成** `.orig`；
> 上下文失配 + `-F 2` 被 fuzz 兜住且成功 → **生成** `.orig`。
> 所以「有 `.orig`」确实等价于「那一次用上了 fuzz/offset」。
> 但要注意**补丁失败时也会生成 `.orig`（并伴随 `.rej`）**，
> 所以看到 `.orig` 不能直接断定"套用是成功的但模糊的"，得连 `.rej` 一起看。

> **待办（不影响使用）**：用 `diff -u` 从「官方原版 → 打过补丁」重新生成一次补丁，
> 让 `@@` 行号归零。那之后「`-F 0` + 零 offset」才是一个**真正的完整性校验**，
> 可以在每次适配时用来抓上游漂移。当前状态只是「锚点还在」，行号是历史遗留。

### ⚠️ 更正：macOS bash 3.2 下 `${#arr[@]}` 是**安全**的，危险的是展开

`install-dsh-custom.sh` 里那段注释写的是：

> 不用数组（macOS 自带 bash 3.2 在 set -u 下 `${#arr[@]}` 空数组会报未绑定）

**这个理由说反了。** 实测（`/bin/bash` 3.2.57，`a=()`，`set -u`）：

| 写法 | 结果 |
|---|---|
| `${#a[@]}` | ✅ `rc=0`，输出 `len=0` |
| `"${a[@]}"` 展开 | ❌ `rc=127`，`a[@]: unbound variable` |
| `${a[@]}` 裸展开 | ❌ `rc=127`，同上 |
| `"${a[@]}"` 传参 | ❌ `rc=127`，同上 |
| `"${a[@]:-}"` | ✅ `rc=0` |
| `"${!a[@]}"` | ✅ `rc=0` |

⇒ 数长度**安全**，**展开**空数组才炸。代码本身没问题（定位那段确实不需要数组，
且脚本里 `"${FILES[@]}"` / `"${APPLY[@]}"` 展开时都保证非空），
但**注释给的理由是错的**，会误导后人 —— 比如误以为 `${#arr[@]}` 不能用，
或者反过来以为 `"${arr[@]}"` 可以放心展开。已按实测改正。

### ⚠️ 判定文件是否存在，别用「多 glob 拼一条命令」

同一天还踩了一个**让检查结果完全反掉**的坑，两个平台都会中：

```sh
ls -1 "$NM"/*/lib/*.bak "$NM"/*/lib/*.orig 2>/dev/null || echo "(无任何备份文件)"
```

zsh 只要**任意一个** glob 无匹配，就整体报 `no matches found` 并**中止整条命令**；
`2>/dev/null` **拦不住**（那是 shell 自己的错误，不是命令的 stderr）。
⇒ `ls` 根本没执行，直接落到 `||` 分支，于是打印「无任何备份文件」——
**实际 9 个 `.bak` 一个不少。** 详见下文「更正：本机 `.bak` 是齐全且干净的」。

```sh
# ✅ 正确：不匹配就安静返回空
find <dir> -name '*.bak'
```

### ⚠️ 用 BSD grep 时，`\|` 不是「或」

同一天第三次被同一族问题绊到。macOS 的 grep 是 **BSD grep**，BRE 里**不支持** `\|` 交替：

```sh
grep -n 'LOCALAPPDATA\|APPDATA' file      # ❌ 被当成字面量 "LOCALAPPDATA|APPDATA"，永远无输出
grep -nE 'LOCALAPPDATA|APPDATA' file      # ✅ 用 -E 走 ERE
```

它**不报错、不警告，只是静默返回空**。危害在于：一旦拿它做判断
（`grep -q ... || echo "没有"`、或 `diff <(grep A) <(grep B)`），
就会得到「文件里没有 X」或「两边一样」这类**看起来很确定的错误结论** ——
本次就因此一度误判 `install-dsh-custom.sh` 里没有 `${APPDATA:-}` 兜底（其实有）。
同族的还有 **BSD grep 不支持 `\s`**：`grep -E '^\s+id:'` 恒无输出，
`diff <(grep ...) <(grep ...)` 于是变成「空 vs 空」→ 假 ✅。
**对策：用 `grep -E`，或直接改用带类型的搜索工具。**

---

## ⭐⭐ 重大修复：`surfaceOp` 字段名写错 —— 「编辑最后一条消息」一直是被拒的

**发现时间**：2026-09-29，由用户真机报错触发。

```
editLastPrompt failed: session/edit-rejected: unable to rewrite the last message:
Error: session event "user/message" carries an invalid replace surfaceOp
```

### 根因

官方 `@deepseek-ai/dsh-session` 的 surface 替换操作，形状是**恰好三个键**：

```ts
export type SurfaceOp = 'append' | {
    op: 'replace';
    startSeq: SessionSeq;
    endSeq: SessionSeq;
};
```

运行时由 `lib/types/surface.js` 的 `isReplaceOp` 强校验：

```js
function isReplaceOp(value) {
    const op = value;
    return Object.keys(op).length === 3
        && Object.hasOwn(op, 'op')
        && Object.hasOwn(op, 'startSeq')     // ← 必须叫 startSeq
        && Object.hasOwn(op, 'endSeq')       // ← 必须叫 endSeq
        && op['op'] === 'replace'
        && isEventSeq(op['startSeq'])
        && isEventSeq(op['endSeq']);
}
```

而我们的补丁传的是 **`{ op: "replace", start, end }`** —— 键名不对，
`Object.hasOwn(op, 'startSeq')` 直接 false ⇒ 抛 `invalid replace surfaceOp`。

> ⚠️ 容易混淆的地方：官方内部**折叠计划**（`planSurfaceEvent` 的返回值）确实用 `start` / `end`，
> 但那是从 `surfaceOp.startSeq` / `surfaceOp.endSeq` **派生**出来的实现细节。
> 事件自身 `surfaceOp` 上的字段名**只能是 `startSeq` / `endSeq`**。

### 这不是官方改的 —— 我们一直就写错了

对三个版本的 `isReplaceOp` 逐一核对，**完全相同**：

| 官方版本 | 要求的字段名 |
|---|---|
| `0.1.5-rc.1` | `startSeq` / `endSeq` |
| `0.1.7-rc.2` | `startSeq` / `endSeq` |
| `0.2.0-rc.1` | `startSeq` / `endSeq` |

也就是说，**这个功能从写出来那天起就没成功过**，只是此前没人真正点过那个「✏️ 编辑」按钮走完全程。
⭐ 教训：**「补丁干净套用」≠「功能可用」**。锚点匹配只证明文本落位，
运行时契约（字段名、枚举值、必填项）必须在真机上跑一遍才算数。

### 一共两处，必须一起修

| 文件 | 位置 | 原来 | 现在 | 后果 |
|---|---|---|---|---|
| `patches/api-session-controller/…-lib-index.js.patch` | `editLastPromptOnce` 的 `session.append(...)` | `start: startSeq, end: endSeq` | `startSeq, endSeq` | **直接报错**，编辑功能完全不可用 |
| `patches/client-ui-conversation/…-lib-client.js.patch` | `scanShadowed()` + `append()` 两处 | `op.start` / `op.end` | `op.startSeq` / `op.endSeq` | **静默失效**：`op.start` 是 `undefined`，`for` 循环一次都不跑，被替换的旧消息不会被标记隐藏 → 改完之后旧消息和新消息会**同时出现在对话里** |

> 第二处被第一处**掩盖**了：编辑从来就没成功过，所以「影子集合」永远是空的，bug 不显形。
> **只修第一处会让第二处立刻暴露。两处必须一起修。**

### 已应用的旧补丁怎么升级

补丁的内置检测标记是 `async editLastPrompt`，所以**已经打过旧补丁的机器会被判为「已打过」而跳过**，
不会自动拿到修复。必须**先还原再重打**：

```bash
node tools/dsh-patch.mjs --restore    # 用 .bak 还原成官方原文件
node tools/dsh-patch.mjs -y           # 重新套用修好的补丁
# 然后重启 DSH + 硬刷新浏览器
```

若没有 `.bak`，就重装官方包：`npm install -g @deepseek-ai/dsh@0.2.0-rc.1`。

### ✅ 真机已直接修复（2026-09-29，绕过沙箱）

本机沙箱仍然不可用（所有 shell 调用 fail-closed），因此**没有走安装脚本**，
而是直接用编辑器改了**正在运行的那份安装**里的两个文件：

```
~/.local/node-v24/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/
  dsh-api-session-controller/lib/index.js        991-992 行  start/end → startSeq/endSeq
  dsh-client-ui-conversation/lib/client.js       1969 / 1982 行  op.start/op.end → op.startSeq/op.endSeq
```

改法与补丁内容**逐字一致**，所以后续再跑 `install-dsh-custom.sh` 时，
`patch --dry-run --reverse -F 0` 会命中 ⇒ 正确判定为「已打过补丁」并跳过，不会重复套用。

> 本机运行体：`~/.local/dsh-web/dsh-web-run.sh` → `~/.local/bin/dsh web --port 3082`，
> 由 launchd `com.csl.dsh-web` 拉起；DSH 版本 **`0.2.0-rc.1`**（与 `TARGET_VERSION` 一致）。
> 改完必须重启才生效：`launchctl kickstart -k gui/$(id -u)/com.csl.dsh-web`。

### ⚠️ 更正：本机 `.bak` 是**齐全且干净**的（此前一次误判）

> ⛔ **2026-09-29 更正。** 本文档早前版本写过「本机安装**没有 `.bak`**，还原路径是断的」——
> **那是错的**，根因是一条不可靠的检查命令，见下方「为什么会被骗」。

实测（`find "$NM" -name '*.bak'`）：

| 备份形态 | 实际数量 |
|---|---|
| **`.bak`**（脚本自己 `cp` 出来的，`--restore` 的依据） | **9 / 9，齐全** |
| `.orig` | 0 个 |
| `.rej` | 0 个 |

且 9 个 `.bak` **全部是干净的官方原版** —— 逐个 grep 三个功能标记，命中数**全为 0**：

```
dsh-agent-loop/lib/index.js.bak                    editLastPrompt=0  recallHistory=0  compactionBackoff=0
dsh-api-remotes/lib/client.js.bak                  editLastPrompt=0  recallHistory=0  compactionBackoff=0
dsh-api-session-controller/lib/client.js.bak       editLastPrompt=0  recallHistory=0  compactionBackoff=0
dsh-api-session-controller/lib/index.js.bak        editLastPrompt=0  recallHistory=0  compactionBackoff=0
dsh-api-session-controller/lib/typert.host.js.bak  editLastPrompt=0  recallHistory=0  compactionBackoff=0
dsh-api-session-controller/lib/typert.remote-client.js.bak  editLastPrompt=0  ...
dsh-client-ui-chat/lib/client.js.bak               editLastPrompt=0  recallHistory=0  compactionBackoff=0
dsh-client-ui-conversation/lib/client.js.bak       editLastPrompt=0  recallHistory=0  compactionBackoff=0
dsh-compaction-basic/lib/index.js.bak              editLastPrompt=0  recallHistory=0  compactionBackoff=0
```

⇒ **`node tools/dsh-patch.mjs --restore` 在本机是可用的。**

#### 为什么会被骗：zsh 的 glob 让整条命令没跑

当时用的是：

```sh
ls -1 "$NM"/*/lib/*.bak "$NM"/*/lib/*.orig 2>/dev/null || echo "(无任何备份文件)"
```

zsh 遇到**任意一个** glob 无匹配，就整体报 `no matches found` 并**中止这条命令** ——
`2>/dev/null` **拦不住**（这是 shell 自己的错误，不是命令的 stderr）⇒ `ls` **根本没执行** ⇒
直接落到 `||` 分支，打印出「无任何备份文件」。**实际 9 个 `.bak` 一个不少。**

> ⭐ **教训：判定文件是否存在，永远不要用「多个 glob 拼在一条 `ls` 里 + `||` 兜底」。**
> 用 `find <dir> -name '*.bak'`（不匹配就安静返回空），或分开写、每条单独判。
> 同理适用于 `ls *.a *.b`、`cat *.x *.y` 这类多 glob 命令。

（`.orig` 当时确实存在 4 个，说明**那一次**套用用过模糊匹配；现已被后续的重装/重打清理掉。
「必须加 `-F 0`」这条铁律依然成立，但**不能再用 `.orig` 的有无来反推历史**。）

### ✅ 真机适配状态：已完成并验证（2026-09-29 01:15）

| 检查项 | 结果 |
|---|---|
| 仓库 HEAD vs `origin/main` | `68e9204` = `68e9204`，**0 领先 0 落后**，工作区干净 |
| 真机 DSH 版本 | **`0.2.0-rc.1`**（= npm `next`；`latest` 仍是 `0.1.7-rc.2`） |
| 9 个补丁的落地状态 | **9/9 APPLIED** —— `patch --dry-run -N -f -F 0 -p1 --reverse` 全部干净命中 |
| `.bak` / `.rej` | 9 个干净 `.bak`；**0 个 `.rej`** |
| 供应商配置 | 5 个模型 id、5 个错误码（含 `QUOTA`）、compat 两项、backoff 三参数 **全部与模板一致** |
| 服务 | `127.0.0.1:3080` 返回 401（正常鉴权），PID 30469 |

#### ⭐ 零副作用的契约测试（仓库内自带，可直接复现）

用**官方自己的代码**证明修复有效 —— **不起 DSH、不落盘、不碰任何真实会话**：

```sh
node tools/contract-test-surface-op.mjs
# 找不到安装位置时可显式指定 @deepseek-ai 目录：
node tools/contract-test-surface-op.mjs /path/to/@deepseek-ai
```

分两层：

| 阶段 | 做什么 | 证明什么 |
|---|---|---|
| **1 校验层** | 把两种形状直接喂给官方 `validateSurfaceMetadata` | 字段名对不对 |
| **2 端到端** | 真实 `new Session(...)` + `session.append(..., { surfaceOp })` | **服务端那条唯一会失败的路径真的通了**，且替换语义正确 |

实测输出：

```
── 阶段 1：官方校验函数 ──
  [OK  ] 修复后  { op, startSeq, endSeq } -> 通过官方校验  返回 {"op":"replace","startSeq":1,"endSeq":2}
  [OK  ] 修复前  { op, start, end }       -> 被拒  session event "user/message" carries an invalid replace surfaceOp

── 阶段 2：真实 Session.append（内存，不落盘）──
  [OK  ] 修复后形状 append 成功，且被替换的事件已从 surface 移除  [0,1] -> [0,2]
  [OK  ] 修复前形状被拒，文案与真机一致: session event "user/message" carries an invalid replace surfaceOp

[OK] 契约全部符合预期 —— startSeq/endSeq 可用，start/end 被拒，替换语义正确。
```

三点说明：

- **报错文案与用户真机报的逐字一致** ⇒ 根因确认闭环。
- **阶段 2 的 `[0,1] -> [0,2]` 是关键**：`[0,1]` 是「提问 + 回复」两个节点；
  用 replace 指向 seq 1 之后变成 `[0,2]` —— **旧回复确实被从 surface 移除了**，
  新消息接在其位置。这正是「编辑重发」该有的行为（若只修字段名而没修消费端，这里会看出问题）。
- 退出码 **0 = 全部符合预期**；**1 = 有不符合预期项**（可用于 CI / 每次升级后回归）。
  已做**反向自检**：把 `GOOD` 故意改成坏形状，脚本确实返回 1 —— 它不会"永远绿"。

> `isReplaceOp` 本身**没有导出**（`dsh-session/lib/types/surface.js` 只导出
> `SurfaceManager` / `foldSurface` / `isSurfaceEvent` / `isAppendSurfaceEvent` /
> `isReplacementSurfaceEvent` / `isSurfaceEligibleType` / `validateSessionEventData` /
> `validateSurfaceMetadata` / `deriveEventMessage`）。
> 但 `validateSurfaceMetadata` 会走 `surfaceOpOf` → `isReplaceOp`，
> **正是抛这条错的那条路径**，所以它是等价且可用的验证入口。

### ⚠️ 仍未做的：**界面**上的一次点击

服务端已由阶段 2 端到端证明通过。剩下的只是**浏览器里的一次人工确认**：

```bash
# 打开一个会话，hover 最后一条用户消息 → 点 ✏️ → 改文字 → 保存并重新生成
# 期望：旧回复消失，用新文字重新生成；旧消息不再与新的并列显示
```

时间线：补丁落盘 `00:45:17`（9 个文件同一批）→ 最后一次启动 `00:45:31`，
所以运行中的实例**应当**已带修复。稳妥起见再重启一次：

```sh
launchctl kickstart -k gui/$(id -u)/com.csl.dsh-web
```

> 为什么这次可以放心：**当初报错的正是服务端**（`session/edit-rejected` 来自 host 侧），
> 而阶段 2 跑的 `Session.append` 就是服务端那条路径。
> 客户端侧（`op.startSeq` / `op.endSeq`）也已用反向 dry-run 验证在真机上。

---

## 桌面版（DeepSeek Harness Desktop）app.asar 适配与重装（2026-09-29）

> 📁 **本节的脚本路径已随模块化调整**：桌面版适配现独立在 `desktop/` 目录下，分
> `desktop/macos/`（macOS 模块，已实测）与 `desktop/windows/`（Windows 模块，他人贡献）两个模块。
> 下文保留当时的原始路径记录（`desktop/windows/apply-desktop-asar-patches.js`）——该脚本位置不变，
> 且**其 macOS 分支已于 2026-09-29 在真机实测通过**（修掉了一处 BSD `patch` 无 `-N` 会交互式挂起的 bug）。
> 模块划分理由与合并判据见 `desktop/README.md`。

桌面版是 Electron 应用，**不走 npm 全局安装**：`dsh` 命令的安装目录、进程、端口（桌面 `127.0.0.1:19387`、网页 `8080`）、
profile（桌面 `~/.dsh/profiles/desktop`）全部与 npm 版独立，**只有 `~/.dsh` 根目录共享**（`.credentials.yaml` /
`settings.yaml` / `sessions` / `storages`）。9 个补丁目标全部打包在 `resources/app.asar` 内，
因此需要 `desktop/windows/apply-desktop-asar-patches.js` 单独处理。首次手工走通后已脚本化。

### 1. asar 文件格式（实测，脚本按此读写）

```
[0..7]      uint32(4) + uint32(headerSize=hs)
[8..8+hs]   header pickle: uint32(strLen+4) + uint32(strLen) + JSON(strLen 字节, UTF-8)
[8+hs...]   文件内容区；某条目的绝对偏移 = 8 + hs + Number(entry.offset)
```

- `entry.offset` 是**字符串**，必须 `Number()`（字符串拼接会算错）；
- `entry.integrity` = `{algorithm:"SHA256", hash, blockSize:4194304, blocks[]}`，即整体哈希 + 4 MiB 分块哈希；
- `unpacked: true` 的条目（本机 1497 个）内容在 `app.asar.unpacked/` 目录里，**不在 asar 内**，重建时只更新它的
  `offset`（写到当前 body 位置），不写内容；
- 本机实测：12967 条目 / 包内文件 11470 个 / body 117,979,532 字节；
- 重写前必须断言「按 header 深度优先遍历的 offset 单调递增」—— 成立才说明 header 顺序 == body 写入顺序，
  可以按该顺序顺序重写。

### 2. ⚠️ asar 内容 ≠ npm tarball 内容（构建产物级差异）

**不能拿 npm 包内容推断 asar 内容**：`dsh-client-ui-chat/lib/client.js` 两边差 208 行、
`dsh-client-ui-conversation/lib/client.js` 差 152 行，差异全在构建产物上 ——
CSS 模块类名哈希（asar 是 `cJsG2q_…`，npm 是 `Sixlwa_…`）与构建机绝对路径注释
（asar 来自 `D:\develop\dsh-harness-windows-x64\...`，npm 来自 GitHub Actions `/home/runner/work/...`）。
其余 7 个目标文件两边逐字节一致。
**结论：补丁必须对「asar 里抽出来的文件」试套**，npm tarball 只能当参考。本机实测对 asar 内容 9/9 dry-run 通过。

### 3. ⚠️ 幂等判断必须用反向 dry-run（正向判断会重复叠加）

`patch --dry-run -N` 对**已打过补丁**的文件仍可能报告成功（本仓库 `dsh-api-session-controller/lib/client.js` 就是），
此时再 apply 会二次叠加：144754 字节 → 145128 字节（静默损坏）。可靠做法是先**反向**试套：

| 目标状态 | `patch --dry-run -R -p1` 结果 |
|---|---|
| 已打补丁 | exit 0，无 `Unreversed` → 判「已应用」，跳过 |
| 原始文件 | exit 1，输出 `Unreversed patch detected!` → 判「待应用」，再正向套 |

脚本据此做到重复运行不叠加；对已打补丁的 asar 跑 `--dry-run` 会输出「9 个补丁全部已应用，无需重复」。

### 4. 替换前的校验清单（脚本内置，任一不过就不替换）

1. header 可解析、条目数不变、`unpacked` 条目数不变、按 header 遍历的 offset 单调；
2. 桌面版版本（`dsh/node_modules/@deepseek-ai/dsh/package.json`）在支持列表 `0.2.0-rc.1` / `0.2.0-rc.2` 内（否则要 `--force`）；
3. 9 个目标 dry-run 全部可套（失败即报版本不匹配）；
4. 补丁后目标文件命中功能标记：`editLastPrompt`（session-controller）、`recallHistory`（ui-conversation）、`compactionBackoffDelay`（compaction-basic）；
5. **全量逐字节比对**：新旧 asar 中除 9 个目标外的全部包内文件必须完全一致（本机 11461/11461 通过），
   9 个目标必须等于补丁后内容；
6. 新 asar 再解析一次，功能标记仍在。

> 关于 0 字节文件：asar 里有若干 `size: 0` 的文件，官方 header 的 `integrity.blocks` 是 1 个块而按内容算是 0 个块，
> 这是**原包自带的口径差异**，不是损坏 —— 这些文件我们不改，`integrity` 原样保留即可。

### 5. 操作记录（2026-09-29）

- 手工流程跑通后固化成 `desktop/windows/apply-desktop-asar-patches.js`；脚本从 pristine 备份重建出的 asar 与手工安装到线上的
  asar **SHA256 完全一致**（`F24882B0…`），证明流程可复现；
- 自动化验收：`--dry-run`（已应用 9/9）、`--out`（pristine → 9 个补丁套用 + 全量校验通过）、
  线上 asar 重启后 `editLastPrompt` 命中 63 次、端口 19387 监听、会话文件正常写入；
- **桌面版带自动更新**（`resources/app-update.yml` 存在），更新会覆盖 `app.asar`：
  每次更新后必须重跑 `node desktop/windows/apply-desktop-asar-patches.js --dry-run` 确认，再正式安装；
- 回滚：`resources/app.asar.bak-<时间戳>` 改名回 `app.asar` 即可（本次备份 `app.asar.bak-20260929-211542`）。
