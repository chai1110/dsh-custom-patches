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

### 各功能适配结论（预研）

| 功能 | alpha 下状态 | 行动 |
|---|---|---|
| **归档恢复**（unarchiveSession） | workspace 官方**未内置** unarchiveSession；client-connection 协议改为 `workspace/archiveSession`（斜杠形式） | 需按新结构重打补丁（workspace + client-connection + ui-workspace） |
| **编辑重发**（editLastPrompt） | alpha 全库**搜不到 editLastPrompt**；agent-loop 新增 `requestSurfaceGeneration`（官方可能改用新 surface 机制） | 先确认官方新机制是否覆盖该功能，若覆盖则删除补丁，否则重打 |
| **输入历史**（↑/↓） | ui-conversation 无我们的标记（`recallHistory`/`sendHistory`） | 需重打补丁 |

### 预研产出的 alpha 补丁（可复用）

| 补丁文件 | 状态 | 说明 |
|---|---|---|
| `patches/workspace/dsh-workspace-lib-index.js.alpha.patch` | ✅ 已生成，上下文匹配验证通过 | workspace 端 `unarchiveSession` |
| `patches/client-connection/dsh-client-connection-lib-client.js.alpha.patch` | ✅ 已生成，上下文匹配验证通过 | client-connection 端 `unarchiveSession` 实现 + dispatch（alpha 把 workspace 操作内联到此包，非 RPC） |
| UI 面板（归档恢复设置项） | ⏳ 待适配 | alpha 设置插槽 `settings.section` → `settings.general.item`（与 composer-enter 同款挂载），需按新插槽重写 |

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
