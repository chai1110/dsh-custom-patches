# 版本追踪表（Version Tracking）

记录每个官方版本下，本补丁集是否可用，以及官方是否已内置我们的功能。

> **版本管理方式**：每个已适配的 DSH 版本对应**一个 git tag + 一个同名快照分支**（tag `vX` ↔ 分支 `version/X`，两者指向同一提交），tag 内补丁与脚本为该版本专用。用户 checkout 对应 tag 后直接 `bash install-dsh-custom.sh -y`，**无需版本参数**。
>
> 已发布的版本：`0.1.0-rc.7` / `0.1.0-rc.8` / `0.1.1-rc.2` / `0.1.2-rc.1` / `0.1.5-rc.1` / `0.1.7-rc.2` / `0.2.0-rc.1`（共 7 个）。
> 一致性自查（在仓库目录执行）——**以命令输出为准，不要相信静态描述**：
>
> ```sh
> for t in $(git tag -l | sort -V); do
>   b="version/${t#v}"
>   printf '%-14s tag=%s  分支=%s  %s\n' "$t" "$(git rev-parse --short $t)" \
>     "$(git rev-parse --short $b 2>/dev/null || echo 缺失)" \
>     "$([ "$(git rev-parse $t^{tree})" = "$(git rev-parse $b^{tree} 2>/dev/null)" ] && echo ✅ 一致 || echo ⚠️ 不一致)"
> done
> ```
>
> ⭐ **当前基线是 `main` 分支（目标 `0.2.0-rc.1`）** —— 直接 `git clone` 用 `main` 即可，不必 checkout tag。
> ⚠️ **注意 `0.2.0-rc.1` 在官方 `next` 频道**，`latest` 仍是 `0.1.7-rc.2`。
> `npm install -g @deepseek-ai/dsh` 默认装到 `0.1.7-rc.2` —— 那种情况请 **checkout `v0.1.7-rc.2`**，
> 或显式装新版：`npm install -g @deepseek-ai/dsh@0.2.0-rc.1`。
> ✅ **每个 tag 都自带正确的版本常量。** tag 内的 `install-dsh-custom.sh` / `apply-dsh-patches.sh` / `check-update.sh`
> 都把版本钉在该 tag 对应的官方版本上，checkout 后直接 `-y` 即可。
> 一条命令自查全部 tag（在仓库目录执行）——**不要相信本文档的静态描述，以这条命令的输出为准**：
>
> ```sh
> for t in $(git tag -l); do echo -n "$t → "; git show "$t:install-dsh-custom.sh" | grep -m1 '^TARGET_VERSION='; done
> ```
>
> 正常应逐行输出与 tag 名一致的版本号。**若某个 tag 的常量与 tag 名不符，说明该 tag 已损坏** —— 请改用 `main`，并在 Issue 里附上上面这条命令的输出。
>
> 🕘 **历史事故（2026-09-28 已修复）**：`v0.1.7-rc.2` 曾指向 `d389396`（落后 `main` 11 个提交），
> 其内置脚本仍钉在 `0.1.5-rc.1`，checkout 该 tag 会因版本不匹配直接失败。
> 现已重打为 `main` 的快照。tag 与 `main` 的差距随时可用 `git rev-list --count <tag>..main` 查，本文档不再硬编码该数字。

| 官方版本 | 补丁可用？ | 官方内置「输入历史」？ | 官方内置「编辑重发」？ | 备注 |
|---|---|---|---|---|
| 0.1.0-rc.6 | ✅ 全部可用 | ❌ | ❌ | 最初适配（历史基准） |
| 0.1.0-rc.7 | ✅ 全部可用（ui 需用 `.rc7` 版） | ❌ | ❌ |  |
| 0.1.0-rc.8 | ✅ 全部可用（ui 用 `.rc8` 版） | ❌ | ❌ |  |
| 0.1.1-rc.2 | ✅ 全部可用（ui 用 `.rc2` 版） | ❌ | ❌ | **旧基准**；含压缩重试补丁（`compaction-basic`，见下） |
| 0.1.2-alpha.2 | ❌ 需重打（架构重构） | ❌ | ❌ | **预发布**；host-apiproxy/client-runtime 包消失，见 `ADAPTING.md` 预研记录 |
| 0.1.2-rc.1 | ✅ 全部可用（`.rc1` 版） | ❌ | ❌ | 架构重构版：编辑重发改由 `dsh-api-session-controller` + `dsh-client-ui-chat` + `dsh-api-remotes`（浏览器端方法表冻结副本，必须同步）承载。补丁集在 `version/0.1.2-rc.1` 分支 / tag `v0.1.2-rc.1` |
| 0.1.5-rc.1 | ✅ 全部可套用（已重打，12/12） | ❌ | ❌ | **历史基准（`version/0.1.5-rc.1` 分支）**，已被 0.1.7-rc.2 取代；官方 0.1.5 收编了 `SURFACE_EVENT_TYPES`/`isSurfaceEvent`（`core/session/src/surface.ts`），本补丁已删重复声明。⚠️ 仅静态校验通过（可套用 + `node --check`） |
| **0.2.0-rc.1** | ✅ **补丁集零改动，9/9 直接可用** | ❌ | ❌ | ⭐ **当前基准（`main` 分支）**；官方 `next` 频道首个 `0.2.0` 候选版。**官方这次没碰我们任何一个锚点区** —— 实测 `patch -F 0`（**零模糊**）9/9 干净套用，实套 + `node --check` 9/9 通过，端到端跑 `install-dsh-custom.sh -y` 9/9 成功且幂等（二次运行正确识别 9 个标记并跳过）。**无需重打任何补丁。** 依赖闭包只新增 `dsh-experimental-schedule-bundle`（对应「自动化任务改由可选插件包提供」），我们打补丁的 6 个包**全部仍在**。官方在 `dsh-agent-loop` 新增的 `ToolCallRecovery`（修「工具调度异常后对话无法继续」）与本补丁的 `__stack` 诊断 + `user/message` 去重**不是同一件事**，故保留。补丁依赖的运行时 API（`ctx.llm.providerRetryPolicy`、`session.surface.nodes`、`session.eventAt`、`isReplacementSurfaceEvent`）在新版**全部仍存在**。真机运行时验证原记为「尚未做」，2026-09-29 补齐 ✅ **真机运行时验证通过（2026-09-29）**：真机暴露 4 个静态校验查不出的 bug 并已全部修复 —— typert codec `schema:`→`create:`、`surfaceOp` `start/end`→`startSeq/endSeq`、ui-conversation `scanShadowed` 键名（导致重发后旧轮次残留）、安装脚本 Windows 版本检测转义；详见 ADAPTING.md 文末小节。 |
| 0.1.7-rc.2 | ✅ 全部可用（11→9 项） | ❌ | ❌ | **上一基准**，已被 0.2.0-rc.1 取代；官方 `latest` 仍是本版。归档相关补丁（`client-connection` / `workspace` / `client-ui-workspace`）已全部退役：`client-connection` 在 0.1.7-rc.2 适配早期退役（12→11），`workspace` + `client-ui-workspace` 于 2026-09-28 退役（11→9）—— 官方已提供完整链路（归档 + 取消归档 + 侧边栏三态筛选 + 行内恢复 + 搜索恢复 + 归档提示的 undo），我们不再重复实现。适配要点：0.1.7 schema 全面改 lazy `??=` 风格、api-remotes codec 的 `schema:` 改名 `create:`、chat 组件签名重构（ChatNodeSeat/ChatView 新 props、inbox projection）、composer keymap 经 `installDraftKeymap` 薄封装（history recall 需直调 `registerComposerKeymap` 覆盖 arbitrate）。三道校验通过（dry-run 9/9 零失败 + 全新副本套用 + node --check）；运行时验证已通过（2026-09-26：套用后 launchd 服务干净启动、契约探针全绿、session/editLastPrompt 方法存在且形状被接受），并已修复 2 处真机运行时 bug（2026-09-27） |

> **桌面版（DeepSeek Harness Desktop）**：桌面版是 Electron 应用，**不走 npm 安装**，9 个补丁目标全部打包在
> `resources/app.asar` 里。本机实测桌面版 `0.2.0-rc.2` 与 npm `0.2.0-rc.1` 的补丁集**零改动兼容**（对 asar 内容
> 9/9 dry-run 通过，2026-09-29 已打上并真机验证）。安装方式不同：`node desktop/windows/apply-desktop-asar-patches.js`
> （详见 README「🖥️ 桌面版支持」与 `ADAPTING.md` 末节）。两个要点：① asar 内容与 npm tarball 存在**构建产物级
> 差异**（CSS 模块类名哈希、构建机绝对路径），试套必须对 asar 抽出的文件做，不能拿 npm 包推断；
> ② 桌面版**自带自动更新**，更新会覆盖 `app.asar`，届时需重跑脚本（先 `--dry-run`）。

> **0.1.5-rc.1 适配要点（详见 `ADAPTING.md` 末节）**：
> - 6 个补丁的锚点需重打（agent-loop / api-remotes / api-session-controller typert.remote-client /
>   client-ui-chat / client-ui-conversation / client-ui-workspace），本质是官方行号漂移与
>   组件参数新增（`usePanelInfo`、`loadImage`、`skillNames`、`uploads`、`attachmentIds` 改名等）。
> - `client-ui-conversation` 的 `SURFACE_EVENT_TYPES` / `isSurfaceEvent` **官方已内置**，
>   已从补丁中删除重复声明，仅保留 `isReplacementSurfaceEvent` + `shadowed` 折叠逻辑。
> - **不存在**「官方已内置」的功能：`editLastPrompt` / `recallHistory` / `sendHistory` /
>   `unarchiveSession` / `message.editPrompt` / `archived-sessions` 在 0.1.5 全部缺失。

---

## 老版本安装

⚠️ **2026-09-28 修正**：本节旧写法（`install-dsh-custom.sh -y <版本号>`）**已失效** —— 当前脚本只接受 `-y`，
传版本号会直接报 `Unknown argument: <版本号>` 并退出。老版本请走 **tag** 路径：

| 官方版本 | 安装方式 |
|---|---|
| **0.1.7-rc.2（最新基线）** | 直接用 `main`：`git clone` 后 `bash install-dsh-custom.sh -y` |
| 0.1.5-rc.1 | `git checkout v0.1.5-rc.1` 后 `bash install-dsh-custom.sh -y` |
| 0.1.2-rc.1 | `git checkout v0.1.2-rc.1` 后 `bash install-dsh-custom.sh -y` |
| 0.1.1-rc.2 | `git checkout v0.1.1-rc.2` 后 `bash install-dsh-custom.sh -y` |
| 0.1.0-rc.8 | `git checkout v0.1.0-rc.8` 后 `bash install-dsh-custom.sh -y` |
| 0.1.0-rc.7 | `git checkout v0.1.0-rc.7` 后 `bash install-dsh-custom.sh -y` |
| 0.1.0-rc.6 及更早 | 无独立补丁文件（仓库自 rc.7 起发布），需先升级官方 |

> 每个 tag 内的 `install-dsh-custom.sh` 已把 `TARGET_VERSION` 钉在该版本上，checkout 后直接 `-y` 即可，
> **不需要也不接受版本参数**。（自查方式见本文档开头那条 `for t in $(git tag -l)` 命令。）

辅助脚本（随 tag 走，同样不接受版本参数）：`bash apply-dsh-patches.sh`（备选安装器）、`bash check-update.sh`（版本检测）。

---

## 检测方法

### 1. 官方是否内置了我们的功能
在官方源码/新版 npm 包里搜索功能标记：
```bash
# 编辑重发
grep -rl "editLastPrompt" node_modules/@deepseek-ai/*/lib/ 2>/dev/null
# 输入历史
grep -rl "recallHistory\|sendHistory\|historyIndexRef" node_modules/@deepseek-ai/*/lib/ 2>/dev/null
```
若无输出 ⇒ 官方未内置，需要保留/继续适配我们的补丁。

> ⚠️ **0.1.2 起的重要提醒**：`editLastPrompt` 这类 @Remote 方法在宿主侧
> （`api-session-controller/lib/index.js` / `typert.host.js`）命中**不代表浏览器端可用**。
> 浏览器端 `remote.session` 方法表来自 `dsh-api-remotes/lib/client.js`（构建期内嵌的
> 各包 typert 模型**冻结副本**，ModuleLoader bundle）。若宿主/协议补丁都命中、但浏览器
> 仍报 `xxx is not a function`，请检查该包是否同步补了（grep `dsh-api-remotes/lib/client.js`）。
> 各包自己的 `typert.remote-client.js` 是纯 ESM 工具产物，**浏览器不加载**，改它不影响运行。

### 2. 补丁是否仍适配新版
用 dry-run 测试是否仍能套上：
```bash
# 对每个补丁，切换到新版目标文件所在目录后：
patch --dry-run -N -p1 < 补丁文件.patch
```
- 全部通过 ⇒ 补丁沿用。
- 有 hunk 失败 ⇒ 需要重新适配（见 `ADAPTING.md`）。

---

## 功能标记对照

| 功能 | 核心标记（grep 用） | rc.1（0.1.2-rc.1）涉及插件 | 旧版（≤0.1.1-rc.2）涉及插件 |
|---|---|---|---|
| 编辑重发 | `editLastPrompt` | api-session-controller（host/client/typert 两端）+ **api-remotes（浏览器端冻结方法表，必须同步）** + ui-chat | host-apiproxy / agent-loop / client-connection / client-runtime / ui-conversation |
| 输入历史 | `recallHistory` `sendHistory` `historyIndexRef` | ui-conversation | ui-conversation |
| agent-loop 去重 | `tailEvent?.type === "user/message"` | agent-loop | agent-loop |
| 压缩自动重试 | `compactionBackoffDelay` `providerRetryPolicy` | compaction-basic（`.rc1`） | compaction-basic（`.retry`） |

> ⚠️ **归档相关标记已不再是「我们的补丁」**：`unarchiveSession` / `archived-sessions` 曾用于补丁校验，
> 但归档相关补丁已于 2026-09-28 **全部退役**（官方已原生提供完整链路）。
> 现在 grep 到 `archiveSession` / `unarchiveSession` 只能说明**官方已内置**，不能再用来判断补丁是否生效。

> ⭐ **机器可读的标记表在 [`tools/patch-markers.tsv`](tools/patch-markers.tsv)** ——
> 上表是给人看的说明，TSV 是给脚本用的单一数据源。`patch-all.sh` / `desktop/macos/dsh-desktop-patch.sh` /
> `check-update.sh` 都读它。**新增或修改补丁时，两处都要更新。**
> 一条命令核对「两面是否都生效」：
>
> ```sh
> bash patch-all.sh --check      # 退出码 0 = CLI 侧与桌面版 9 个标记全绿
> ```

> **压缩自动重试**：官方 `dsh-llm-retry` 的重试只挂在 `agent/request-error`（正常对话请求），压缩（`dsh-compaction-basic` 直接调 `ctx.llm.stream()`）不走该扩展点，429/限流直接失败。本补丁在 `summarizeWithLlm` 内加重试循环，复用 provider 的 `retryPolicy`（maxRetries/retryableCodes/backoff，settings.yaml 已配），并记录 `llm/retry` 会话事件。详见 `ADAPTING.md`。

---

## 桌面版（Electron）

**桌面版是独立的第四个面**，用的是**同一套 `patches/**`**，但要打到签名过的 `app.asar` 里。
完整说明见 [`desktop/README.md`](desktop/README.md)。

| 桌面版版本 | 补丁可用？ | 备注 |
|---|---|---|
| **0.2.0-rc.2** | ✅ **9/9 零 fuzz 套用 + 9 个功能标记全绿** | ⭐ 当前实测版本。`Info.plist` 的 `CFBundleShortVersionString` 与 asar 内 `@deepseek-ai/dsh` 版本**都是 `0.2.0-rc.2`**。 |

**2026-09-29 实测数据（桌面版 `0.2.0-rc.2`）**：

| 项 | 值 |
|---|---|
| 官方 asar | `18d5036b…` · 121,387,457 字节 |
| 补丁版 asar（macOS 模块） | `4286629a…` · 123,850,535 字节（保留原数据区 + 把 9 个新文件追加到末尾） |
| 补丁版 asar（Windows 模块，macOS 分支） | `5360c9e5…` · 121,441,457 字节（就地紧凑重排数据区） |
| 两套实现的等价性 | 从两份产出各抽 9 个目标文件比对，**9/9 逐字节相同** ⇒ 等价（整包 sha256 不同，属打包策略差异，非缺陷） |
| 未改动条目 | **12,964 / 12,964 逐字节一致** |
| 替换条目 | 9 / 9，缺失 0，意外变化 0 |
| 功能标记 | 9 / 9 命中 |
| 可复现性 | 同一脚本两次运行产出的 asar **逐字节相同**（跨脚本不适用，见上） |
| 来源指纹 | 两套实现**都会**写 `.dsh-desktop-patch.json`（`sourceAsarSha256` / `patchedAsarSha256` / `targets`），供 `check-update.sh` 判覆盖 |
| 重签名 | ad-hoc，`valid on disk` + `satisfies its Designated Requirement` |
| 两面一致性 | CLI 侧与桌面版标记计数**逐项相等**（2/2、2/2、1/1、1/1、1/1、1/1、2/2、3/3、11/11） |

**桌面版特有的两个坑**：

1. **走 nightly 自动更新** —— 官方包一更新，补丁就被覆盖。`bash check-update.sh` 会比对
   打补丁时记录的「来源指纹」（官方 asar 的 sha256）并重查功能标记，提示是否要重跑。
2. **与官方版共用 user-data** —— 单实例锁 + 固定端口 `19387`，两者不能同时运行。
   补丁版是**独立的一份 app**（默认 `~/Applications/DeepSeek Harness Patched.app`），回滚就是删掉它。

> **Windows 桌面版是独立模块** —— 源码 `desktop/windows/apply-desktop-asar-patches.js`（跨平台，纯 Node），
> 已在 Windows `0.2.0-rc.1` / `0.2.0-rc.2` 实测；**其 macOS 分支 2026-09-29 也已在本机跑通**。
> 交付清单与「合并判据」见 [`desktop/windows/README.md`](desktop/windows/README.md)。

---

## rc.1（0.1.2-rc.1）架构变化与适配说明

0.1.2-rc.1 是**架构级重构**，官方变化概要（详见 `ADAPTING.md`）：

- **被移除的包**：`dsh-host-apiproxy`、`dsh-client-runtime`（我们旧补丁的两个目标包）
- **新架构**：远程网关统一为 `@Remote` 体系（`dsh-api-session-controller` 等），Session 数据 API 从 `events[]` 改为 `seq`/`eventAt()`/`snapshotEvents()`
- **编辑重发迁移**：旧实现走 host-apiproxy/client-runtime，新版走 `dsh-api-session-controller`（host 命令 + client binding + typert 协议两端）+ `dsh-client-ui-chat`（UI 编辑按钮）+ **`dsh-api-remotes`（浏览器端方法表：其 lib/client.js 内嵌各包 typert 模型冻结副本，只补各包的 typert.remote-client.js 无效，必须同步补它）**
- **agent-loop 去重**：改用 `session.eventAt()` 新 API（官方已迁移到该 API，但**去重功能本身官方未内置**）
- **官方已原生实现** `providerRetryPolicy`（dsh-llm 核心），可作对照但我们的压缩重试补丁仍需要（覆盖压缩路径）

rc.1 的 `.rc1.patch` 补丁文件已全部生成并验证可反向卸载（精确匹配当前全局安装）。
2026-09-04 复盘补丁：编辑重发此前"重装后仍失效"，根因是漏补 `dsh-api-remotes`
（浏览器端唯一加载的方法表来源）；已新增 `patches/api-remotes/` 补丁并把
`requestId` 同步进 api-session-controller 的 4 个 `.rc1` 补丁（与已装文件逐字节一致）。
