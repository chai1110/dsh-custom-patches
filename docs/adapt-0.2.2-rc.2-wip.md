# DSH 0.2.2-rc.2 适配工作记录（WIP）

> 状态：**未完成**。7 个目标文件中 6 个已改造完成并通过语法校验，`dsh-client-ui-conversation/lib/client.js`（↑/↓ 历史消息）尚未开始。
> 补丁文件（`patches/**`）尚未生成——本次官方把浏览器侧 bundle 改成了压缩单行包，行级 diff 不再适用，需改用字符串替换式补丁（见下文「机制问题」）。
> 最后更新：2026-11-12

---

## 一、这次为什么不能沿用旧流程

rc.2 把浏览器侧 bundle 从「一行一条语句」改成了**整个文件一两行的压缩包**：

| 文件 | rc.1 行数 | rc.2 行数 | 去空白后体积变化 | 60 字符片段命中率 |
|---|---|---|---|---|
| `dsh-client-ui-chat/lib/client.js` | 15,589 | **20** | −11.9% | 8/30 |
| `dsh-client-ui-conversation/lib/client.js` | 23,145 | **27** | −7.9% | 9/30 |
| `dsh-api-remotes/lib/client.js` | 28,329 | **3** | +4.8% | 8/30 |
| `dsh-api-session-controller/lib/client.js` | 4,342 | **5** | −29.6% | 10/30 |
| `dsh-api-session-controller/lib/index.js` | 4,204 | 4,301 | +2.3% | **29/30** |
| `dsh-agent-loop/lib/index.js` | 1,779 | 1,795 | +1.4% | **27/30** |

结论（两条同时成立）：

1. **打包方式变了**（主因）：行级 `diff`/`patch` 在单行文件里无处可挂，不是锚点漂移，而是「行」这个前提没了。
2. **逻辑也有真实改动**（次因）：未压缩的两个文件片段命中 27–29/30（几乎逐字相同，所以补丁原样就能套）；压缩文件只有 8–10/30，说明实现细节也变了。

> 实测命令见 `tools/rc2-adapt/compare.mjs`。

---

## 二、已完成的 6 个文件

| # | 文件 | 改动内容 | 校验 |
|---|---|---|---|
| 1 | `dsh-api-session-controller/lib/index.js` | `editLastPrompt` 命令 + `Remote()` 装饰器 | 原补丁 `-F0` 直接套上 |
| 2 | `.../typert.host.js` | `session/editLastPrompt` 描述符 + `z.object` / `z.strictObject` 双 schema | 语法通过，落在 `session/rename` 之后 |
| 3 | `.../typert.remote-client.js` | 远程侧同款描述符 | 语法通过 |
| 4 | `.../lib/client.js`（控制器客户端） | 新增 `async editLastPrompt(text)`，插在 `async prompt(...)` 之前 | 语法通过，锚点唯一 |
| 5 | `dsh-api-remotes/lib/client.js` | 3 组 schema 助手 + 61 行描述符 | 语法通过 |
| 6 | `dsh-client-ui-chat/lib/client.js` | ✏️ 编辑按钮全套（8 处） | 语法通过 |
| 7 | `dsh-client-ui-conversation/lib/client.js` | ↑/↓ 历史消息 | **未开始** |

### 6 号（chat）的 8 处改动

1. 插入 `EditPromptContext = react.createContext(void 0)`
2. `ChatView({...})` 入参增加 `editLastPrompt`
3. 插入 `lastUserKey` 计算（从 rc.1 已适配版本整段搬运，仅压掉空白）
4. `renderSlot("conversation.chat.flow", …)` 外包 `EditPromptContext.Provider`
5. **整段替换 `UserMessageNodeView`**：630 字符 → 4,059 字符（内联编辑框、Enter 提交、Esc 取消、错误提示、`extraActions` 里的 ✏️）
6. binding 的 `inject()` 里注入 `editLastPrompt`
7. 补 4 条中英文案（`message.editPrompt` / `saveEdit` / `cancelEdit` / `editing`）
8. `messageDefinition.match` 允许 replacement surface 事件（否则编辑后的消息不渲染）

---

## 三、关键方法：插入的代码不需要压缩

JS 不看待换行，所以**可以直接把 rc.1 那份可读代码按锚点插进压缩单行包**，比手写压缩版可靠得多。做法：

- 锚点必须是压缩原文里的**精确子串**（注意 rc.2 把 `'` 换成了反引号）
- 每次替换都断言 **命中次数 === 1**，避免插错位置
- 大段代码（如 `UserMessageNodeView`、`lastUserKey`）从 rc.1 已适配版本**原样搬运**，只做 `\s*\n\s*` → `` 的空白压缩
- 改完立即 `node --check`（复制成 `.mjs` 后检查，bundle 是 CJS 工厂也能解析）

脚本见 `tools/rc2-adapt/`：

| 脚本 | 作用 |
|---|---|
| `slice.mjs` | 按锚点截取「括号配平」的代码片段（处理字符串/模板/注释） |
| `compare.mjs` | 量化对比两个版本文件（行数、去空白体积、片段命中率） |
| `patch_ctrl_client.mjs` | 控制器客户端插入 `editLastPrompt` |
| `patch_remotes.mjs` | 从旧补丁提取 `+` 行，按锚点插入 api-remotes |
| `patch_chat.mjs` | chat 的 8 处改动（含整段替换组件） |

> ⚠️ 脚本顶部的 `SRC` / `DST` / `PATCH` / `TARGET` 是**主工作机上的绝对路径**，在别的机器上跑要先改这几行。

---

## 四、从安装包里取官方 asar（不依赖安装器）

rc.2 的 NSIS 静默安装（`--updated /S`）在本机反复失败，改用 7-Zip 直接从安装包取产物：

```sh
Z="/c/Program Files/7-Zip/7z.exe"
EXE="deepseek-harness-0.2.2-rc.2-win-x64.exe"

# 1) 取出 electron-builder 的 app 载荷
"$Z" e "$EXE" '$PLUGINSDIR/app-64.7z' -o./out -y

# 2) 取出 asar
"$Z" e ./out/app-64.7z "resources/app.asar" -o./out -y
```

同理，若要**整体覆盖安装**（安装器不可用时）：

```sh
"$Z" x ./out/app-64.7z -o"D:/Program Files/dsh" -y   # 关掉应用后再执行
```

> 覆盖安装前务必备份整个安装目录；本机备份在 `D:\dsh-install-backup\rc1-202611121720\`（1.3 GB）。

---

## 五、机制问题（待定）

压缩单行包如果继续用 `diff`，每个文件会产生 ~1 MB 的巨型补丁（整个文件当一行删、一行加）。建议改为字符串替换式补丁：

```jsonc
// patches/<pkg>/<file>.subst.json
{
  "target": "@deepseek-ai/dsh-client-ui-chat/lib/client.js",
  "ops": [
    { "find": "const MOTION_TAIL_MS=800;", "replace": "const MOTION_TAIL_MS=800;const EditPromptContext=…", "expect": 1 }
  ]
}
```

并在 `desktop/windows/apply-desktop-asar-patches.js` 里增加对 `.subst.json` 的支持：非压缩包可继续用 `.patch`，压缩包用 `.subst.json`，两者共用现有的 dry-run / 功能标记 / 全量逐字节校验流程。

---

## 六、下一步

1. 完成 `dsh-client-ui-conversation`（↑/↓，12 处改动：`historyIndexRef` / `savedDraftRef` / `recallHistory()` / keymap 仲裁改接 `registerComposerKeymap`）
2. 落地 `.subst.json` 机制 + apply 脚本支持
3. 7 个文件全量 `node --check` + 功能标记校验
4. 7z 覆盖安装 rc.2 → 打补丁 → 启动实测
5. 通过后合并回 `main`，打 `v0.2.2-rc.2` tag + `version/0.2.2-rc.2` 快照分支 + Release
