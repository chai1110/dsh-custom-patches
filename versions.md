# 版本追踪表（Version Tracking）

记录每个官方版本下，本补丁集是否可用，以及官方是否已内置我们的功能。

| 官方版本 | 补丁可用？ | 官方内置「输入历史」？ | 官方内置「编辑重发」？ | 备注 |
|---|---|---|---|---|
| 0.1.0-rc.6 | ✅ 全部可用 | ❌ | ❌ | 最初适配（历史基准） |
| 0.1.0-rc.7 | ✅ 全部可用（ui 需用 `.rc7` 版） | ❌ | ❌ |  |
| 0.1.0-rc.8 | ✅ 全部可用（ui 用 `.rc8` 版） | ❌ | ❌ |  |
| 0.1.1-rc.2 | ✅ 全部可用（ui 用 `.rc2` 版） | ❌ | ❌ | **旧基准**；含压缩重试补丁（`compaction-basic`，见下） |
| 0.1.2-alpha.2 | ❌ 需重打（架构重构） | ❌ | ❌ | **预发布**；host-apiproxy/client-runtime 包消失，见 `ADAPTING.md` 预研记录 |
| **0.1.2-rc.1** | ✅ **全部可用（`.rc1` 版）** | ❌ | ❌ | **当前基准**；架构重构版：编辑重发改由 `dsh-api-session-controller` + `dsh-client-ui-chat` 承载，补丁全新 `.rc1` 文件 |

---

## 老版本安装

**无需 checkout 历史 commit。** 当前仓库同时保留 rc.1 / rc.7 / rc.8 / 0.1.1-rc.2 的补丁文件，
安装脚本支持版本参数自动匹配——ui-conversation 按版本取 `.rc1` / `.rc2` / `.rc7` / `.rc8` 文件。
rc.1（0.1.2-rc.1）为架构重构版，补丁文件全部独立（`.rc1`）：

| 官方版本 | 一键安装命令 |
|---|---|
| 0.1.2-rc.1（最新） | `bash install-dsh-custom.sh -y` |
| 0.1.1-rc.2 | `bash install-dsh-custom.sh -y 0.1.1-rc.2` |
| 0.1.0-rc.8 | `bash install-dsh-custom.sh -y 0.1.0-rc.8` |
| 0.1.0-rc.7 | `bash install-dsh-custom.sh -y 0.1.0-rc.7` |
| 0.1.0-rc.6 及更早 | 无独立补丁文件（仓库自 rc.7 起发布），需先升级官方 |

基础脚本：`bash apply-dsh-patches.sh 0.1.1-rc.2`；检测脚本：`bash check-update.sh 0.1.1-rc.2`。

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
| 编辑重发 | `editLastPrompt` | api-session-controller（host/client/typert 两端）+ ui-chat | host-apiproxy / agent-loop / client-connection / client-runtime / ui-conversation |
| 输入历史 | `recallHistory` `sendHistory` `historyIndexRef` | ui-conversation | ui-conversation |
| 归档恢复 | `unarchiveSession` / `archived-sessions` | workspace + client-connection + ui-workspace | workspace / client-connection / ui-workspace |
| agent-loop 去重 | `tailEvent?.type === "user/message"` | agent-loop | agent-loop |
| 压缩自动重试 | `compactionBackoffDelay` `providerRetryPolicy` | compaction-basic（`.rc1`） | compaction-basic（`.retry`） |

> **压缩自动重试**：官方 `dsh-llm-retry` 的重试只挂在 `agent/request-error`（正常对话请求），压缩（`dsh-compaction-basic` 直接调 `ctx.llm.stream()`）不走该扩展点，429/限流直接失败。本补丁在 `summarizeWithLlm` 内加重试循环，复用 provider 的 `retryPolicy`（maxRetries/retryableCodes/backoff，settings.yaml 已配），并记录 `llm/retry` 会话事件。详见 `ADAPTING.md`。

---

## rc.1（0.1.2-rc.1）架构变化与适配说明

0.1.2-rc.1 是**架构级重构**，官方变化概要（详见 `ADAPTING.md`）：

- **被移除的包**：`dsh-host-apiproxy`、`dsh-client-runtime`（我们旧补丁的两个目标包）
- **新架构**：远程网关统一为 `@Remote` 体系（`dsh-api-session-controller` 等），Session 数据 API 从 `events[]` 改为 `seq`/`eventAt()`/`snapshotEvents()`
- **编辑重发迁移**：旧实现走 host-apiproxy/client-runtime，新版走 `dsh-api-session-controller`（host 命令 + client binding + typert 协议两端）+ `dsh-client-ui-chat`（UI 编辑按钮）
- **agent-loop 去重**：改用 `session.eventAt()` 新 API（官方已迁移到该 API，但**去重功能本身官方未内置**）
- **官方已原生实现** `providerRetryPolicy`（dsh-llm 核心），可作对照但我们的压缩重试补丁仍需要（覆盖压缩路径）

rc.1 的 `.rc1.patch` 补丁文件已全部生成并验证可反向卸载（精确匹配当前全局安装）。
