# v0.2.2-rc.1 — DSH 0.2.2-rc.1 补丁适配

> 本文件是 GitHub Release 的说明正文，可直接复制到
> https://github.com/chai1110/dsh-custom-patches/releases/new?tag=v0.2.2-rc.1

## 适配对象

DeepSeek Harness Desktop **0.2.2-rc.1**（Windows，安装于 `D:\Program Files\dsh`）

9 个补丁全部以 `-F 0` **零模糊**通过试套，全量校验 20510 个非目标文件逐字节一致。

## 本次重做的两个补丁

| 补丁 | 原因 |
|---|---|
| `dsh-agent-loop` | 官方改动了 `code: error instanceof ToolActivationError ? ... : "UNKNOWN"` 那一行，`__stack` 落点随代码迁移 |
| `dsh-client-ui-chat` | 官方把用户消息渲染重构为 `UserStyleBubble` + `renderSlotChain`，原 12 个 hunk 中 6 个失效；**编辑按钮改用「纯 Context」方案重写**（`EditPromptContext` 由 `ChatView` 发布、`UserMessageNodeView` 消费），不再穿 `ChatFlow` / `ChatNodeSeat` 的 props 链 |

其余 7 个补丁仅为消除偏移而重新生成。

## 功能

- 输入框 **↑/↓ 翻历史消息**（`recallHistory`）
- **编辑最后一条消息并重新生成**（`editLastPrompt`，hover 出 ✏️）
- 压缩（上下文总结）失败**自动重试**（`compactionBackoffDelay`）
- 编辑重发后**不再残留**「已停止」「深度求索中」等状态条（`wholeTurnShadowed` / `deadRanges`）

## 用法（桌面版 Windows）

```sh
node desktop/windows/apply-desktop-asar-patches.js \
  --asar "D:/Program Files/dsh/resources/app.asar"
```

跨盘会被 `EXDEV` 拦下时，先 `--out` 输出到同盘再替换：

```sh
node desktop/windows/apply-desktop-asar-patches.js \
  --asar "D:/Program Files/dsh/resources/app.asar" \
  --out  "D:/Program Files/dsh/resources/app.patched.asar"
```

## 校验判据

只看**功能标记**（`tools/patch-markers.tsv`），不要相信 `patch` 的退出码：

```
editLastPromptOnce / editLastPrompt / session/editLastPrompt
tailEvent?.type === "user/message" / compactionBackoffDelay / recallHistory
wholeTurnShadowed
```

## 回滚

`resources/app.asar.bak-<时间戳>`（脚本自动生成）改名回 `app.asar` 即可。

## 已知问题：nightly 静默安装反复失败

官方 nightly 的 NSIS 静默安装（`--updated /S`）在部分机器上反复失败：应用下载完成后立即 `quitAndInstall` 退出，安装未落盘，重开仍是旧版本，于是「更新完还是提示更新」无限循环。

已排除的原因（实测）：

- 安装包损坏 → size / sha512 与 `nightly.yml` 声明完全一致
- 权限不足 → 目录 ACL 中 `Authenticated Users` 有 Modify，实测可写
- 文件被占用 → `app.asar` 可以 `r+` 打开
- 需要提权 → 安装包清单为 `requestedExecutionLevel level="asInvoker"`

但安装器执行完毕（退出码 0）后，`DeepSeek Harness.exe` 与 `app.asar` 的时间戳均未变化。

**注意**：NSIS 安装后文件 mtime 是**安装包的构建时间**，不是安装时间，不能拿 mtime 判断「装没装」。

绕行方案：用 7-Zip 直接从安装包取产物（详见 `docs/adapt-0.2.2-rc.2-wip.md`）：

```sh
7z e deepseek-harness-0.2.2-rc.2-win-x64.exe '$PLUGINSDIR/app-64.7z' -o./out -y
7z e ./out/app-64.7z "resources/app.asar" -o./out -y
```
