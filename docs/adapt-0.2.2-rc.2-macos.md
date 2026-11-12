# macOS 侧 DSH 0.2.2-rc.2 适配记录

> 2026-11-12 完成。参考远端 `wip/0.2.2-rc.2` 分支（Windows 侧提交 `69ae6ab`）
> 的 `docs/adapt-0.2.2-rc.2-wip.md` 与 `tools/rc2-adapt/patch_chat.mjs`；
> Windows、macOS 的浏览器侧 bundle 逐字相同，其 8 个锚点在 macOS 包上全部精确命中 1 次。

## 一、为什么旧补丁不能沿用

官方把 4 个浏览器侧 bundle 从「多行可读代码」改成**压缩单行包**，UI 两个还启用了
minify（变量名变成 `n/e/t/Nl`）。我直接读 asar 数据区原始字节核对过，不是抽取工具出错：

| 文件 | rc.2 行数 | 旧补丁 hunk 锚点 |
|---|---|---|
| `dsh-client-ui-chat/lib/client.js` | 19 | 9 个里 8 个失效 |
| `dsh-client-ui-conversation/lib/client.js` | 26 | 12 个里 8 个失效 |
| `dsh-api-remotes/lib/client.js` | 2 | 3 个里 2 个失效 |
| `dsh-api-session-controller/lib/client.js` | 4 | 1 个失效 |
| `typert.host.js` / `typert.remote-client.js` | 5013 / 2714 | 各 2 个失效 |

另外 3 个未压缩文件（host `index.js`、`agent-loop`、`compaction-basic`）旧补丁直接沿用。

结论：**行级 `patch` 在单行文件里仍有解**（BSD patch 实测可处理 160 KB 以上的超长行），
但补丁必须是「整行删 + 整行加」的形式；`api-remotes` 因此产生 2.3 MB 补丁，
`ui-chat` 967 KB、`ui-conversation` 317 KB。

## 二、9 个文件的处理

| # | 文件 | 做法 |
|---|---|---|
| 1 | `api-session-controller/lib/index.js` | 旧补丁沿用 |
| 2 | `api-session-controller/lib/client.js` | 在 `beginSubmission(input){` 前插入 `async editLastPrompt(text){...}` |
| 3 | `typert.host.js` | 旧补丁贴 h1/h4；h2 的 strict schema 内联、h3 注册块插在 `'session/rename':` 前 |
| 4 | `typert.remote-client.js` | 同上 |
| 5 | `api-remotes/lib/client.js` | 3 组 schema 全部内联成 IIFE，只需一个 `"session/rename":` 注入点 |
| 6 | `agent-loop/lib/index.js` | 旧补丁沿用 |
| 7 | `compaction-basic/lib/index.js` | 旧补丁沿用 |
| 8 | `client-ui-chat/lib/client.js` | 按 Windows 侧 8 处替换：`EditPromptContext`、`ChatView` 入参、`lastUserKey`、flow Provider、**整段替换 `UserMessageNodeView`（630→4059 字符）**、binding 注入、中英文案、`match` 允许 replacement |
| 9 | `client-ui-conversation/lib/client.js` | ↑/↓ 历史改为 **DOM 外挂**（见下） |

大段代码（`lastUserKey`、`UserMessageNodeView`）从 **rc.1 官方包 + 旧补丁重建的已适配版**
整段搬运，只做 `\s*\n\s*` 空白压缩，比手写压缩版可靠。每次替换都断言锚点命中 1 次。

## 三、↑/↓ 历史为什么改成 DOM 外挂

minify 后变量名不稳定（下个 rc 又会变），把 12 个 hunk 硬锚进压缩 React 组件既脆弱又易白屏。
改成在 bundle 末尾注入一段**自包含 IIFE**：

- `document.addEventListener('keydown', ..., true)` 捕获阶段处理，先于 React 委托；
- 输入框为空或光标在行首时，`ArrowUp` 召回上一条已发送文本，`ArrowDown` 返回；
- `Enter` / 带「发送」语义的按钮点击时把文本写入 `localStorage`（最多 200 条，页面重载仍在）；
- 写入用 `HTMLTextAreaElement.prototype.value` 的原生 setter + `input` 事件，保证 React 受控组件能收到变更；
- 命中时 `stopImmediatePropagation()` 阻止官方 keymap 抢走按键。

不引用任何压缩变量名，**跨版本稳定**。函数名保留 `recallHistory` 以通过功能标记核对。

## 四、验证结果

```
成功应用 9 / 9，无 .rej
未改动且哈希一致: 21777 / 21777
预期替换: 9 / 9    缺失: 0   意外变化: 0
9 个功能标记全命中，node --check 全部通过
重签 designated requirement = 官方 DR（NAN929V4UM）
codesign --verify: valid on disk
```

## 五、注意事项

- UI 层的 `UserMessageNodeView` 来自 rc.1 已适配版，**语法与标记已验证，运行时表现需真机实测**
  （编辑按钮、内联编辑框、Enter 提交 / Esc 取消、编辑后消息渲染）。
- conversation 的「被替换回合隐藏」（旧补丁 h1–h8）本次未移植，属显示优化，不影响两个核心功能；
  若编辑重发后旧消息仍显示，下次按同样方式补。
- 官方每次自动更新仍会覆盖 `app.asar` 清空补丁；新版本需重新量化 hunk 失败情况再重打。
- 脚本重签已显式写入官方 designated requirement，自动更新不会再因签名校验失败而装不上。

## 六、运行时修复（2026-11-12，真机反馈后）

初版只做了语法 / 标记 / 进程启动验证，真机暴露两个问题：

1. **编辑重发后旧回合不消失、消息一遍遍累积**。
   根因：rc.1 补丁 h1–h7 的 `wholeTurnShadowed` / `deadRanges` / `scanShadowed`
   残留修复没移植（Windows 侧 `c43a363` 的 revert 说明也点出这一点）。
   会话转录证实 host 是对的：每次编辑发一个
   `{op:"replace",startSeq,endSeq}` 的 `user/message`，范围逐次覆盖上一轮。
   修法：在投影引擎 `dispatchInput(input,accept){const event=input.event;` 后注入
   一段过滤——遍历 `this.inputs`，若某 replacement 的 `startSeq..endSeq` 覆盖
   `event.seq` 就 `return \`none\``（不派发该回合）。等价于整轮隐藏，
   且不依赖 rc.2 压缩后的方法名，也不需要 7 个人工锚点。
2. **↑/↓ 无反应**。输入框是 Lexical 的
   `<div contentEditable data-composer-input>`，初版外挂用 `textContent` 写值会被
   虚拟 DOM 覆盖。v2 改为：`window` 捕获阶段注册、用 `[data-composer-input]` 定位、
   全选后 `document.execCommand('insertText', ...)` 写入（触发原生 input 让 Lexical 同步）、
   MutationObserver 在输入框清空时把内容记入 `localStorage` 历史。

> Windows 侧 `5328a37` 的 `subst_apply.mjs`（去空白映射）实测 12 个 hunk 自动定位 5 个，
> 失败 7 个；其文档也标注 `client-ui-conversation` 的 ↑↓ 待重写。
> macOS 侧因此没有硬套 12 个 hunk，改用上述两处等效注入。
> `main` 已由 `c43a363` 恢复为实测可用的 rc.1 补丁集；本分支保留 rc.2 适配成果待合并。
>
> ⚠️ 这两处只做了语法 / 9/9 补丁 / 标记 / 进程启动验证，**运行时仍需真机点测**。
