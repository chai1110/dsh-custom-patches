# DSH 自定义增强补丁
> 📖 [English](README.en.md)


为 [DeepSeek Harness (DSH)](https://github.com/deepseek-ai/deepseek-harness) Web GUI 添加三个官方暂未提供的实用改进：
**① 输入框 ↑/↓ 键发送历史**、**② 编辑最后一条消息并重新生成** 与 **③ 压缩（上下文总结）失败自动重试**。

- 适配版本：见 [**Releases**](https://github.com/chai1110/dsh-custom-patches/releases) —— 每个版本对应一个 tag，老版本 checkout 对应 tag 即可
- 许可证：**MIT**（详见 [LICENSE](LICENSE)）
- 维护：chai1110（<chai011379@gmail.com>）

> **这是什么 / 不是什么**：这是一套**编译产物补丁**，不是官方插件，也不是源码 fork。
> 它通过 `diff`/`patch` 直接修补 DSH 已装好的 npm 包文件（`node_modules` 里的编译 JS），
> 给 DSH 加上官方还没有的三个功能。**任何 npm 重装 / 升级 DSH 都会覆盖这些补丁，需重新应用。**

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
- 更早的消息只保留复制，不可编辑；要改更早的内容，请用该条消息的**「分叉」**另起一个会话
- **AI 正在生成时也允许编辑**：会先撤销当前回合（**保留排队中的输入**），再按新文本重新生成
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

## ⚠️ 前置要求

- **Node.js**（任意 18+）—— 只用来跑补丁脚本，桌面版本身不依赖它
- **`patch` 命令** —— Windows 装 Git for Windows 即自带；也可用环境变量 `PATCH_BIN` 指定路径
- **DeepSeek Harness 桌面版** 已安装

> 脚本会自动探测 asar 位置：Windows `%LOCALAPPDATA%\Programs\DeepSeek Harness\resources\app.asar`、
> macOS `/Applications/DeepSeek Harness.app/Contents/Resources/app.asar`、Linux `/opt/DeepSeek Harness/resources/app.asar`。
> 装在别处就用 `--asar <path>`（或环境变量 `DSH_DESKTOP_ASAR`）。

---

## 🚀 快速开始

**本仓库只面向桌面版（Electron）。** CLI / 网页端 / VS Code 插件已不再支持（相关脚本已于 2026-10-30 退役，历史版本可 checkout 旧 tag）。

```bash
# 1) 克隆仓库
git clone https://github.com/chai1110/dsh-custom-patches.git
cd dsh-custom-patches

# 2) 先试套：只看补丁能否套上，不改动任何文件
node desktop/windows/apply-desktop-asar-patches.js --dry-run

# 3) 正式安装：退出应用 → 备份 app.asar → 打补丁 → 全量校验 → 替换 → 重启
node desktop/windows/apply-desktop-asar-patches.js
```

装完打开桌面版，确认三件事：

- 输入框按 **↑** 能翻出上一条消息
- 最后一条用户消息 **hover** 出现 **✏️ 编辑** 按钮
- 「压缩失败自动重试」**没有 UI 信号**（只在限流 / 网络错误时于后台生效）；想确认可在会话日志里找 `llm/retry` 事件

**脚本做了什么**：定位 `app.asar` → 清点补丁 → 反向试套识别「已应用」（幂等，可放心重跑）→ 备份 → 打补丁 → 重建 asar → 全量校验（非目标文件逐字节一致 + 功能标记命中）→ 替换。任一项不过则不替换原文件。

> 也可以把本仓库链接直接发给你的 AI 助手，让它按「快速开始」在你机器上完成安装。

---

## 🔧 补充说明

- **只生成不替换**：`node desktop/windows/apply-desktop-asar-patches.js --out new.asar` 会把打过补丁的 asar 输出到指定路径，应用照常运行，适合先验证。
- **幂等**：重复运行会先反向试套识别「已应用」并跳过，**不会重复叠加**。
- **端口**：桌面宿主不再固定端口（早期版本硬编码 `19387`），改为动态分配；按固定端口探活 / 取 token 的脚本会失效。
- **profile 独立**：桌面版与 npm 版共享 `~/.dsh` 根目录（凭据、会话），但插件配置按 profile 分开 —— 桌面版是 `~/.dsh/profiles/desktop`，见 `dsh-provider-config`。
- **macOS**：`desktop/macos/dsh-desktop-patch.sh` 是独立分支（签名 / 重签名流程不同），细节见 [`desktop/README.md`](desktop/README.md)。

---

## ↩️ 如何恢复原版（卸载补丁）

打补丁时脚本会在同目录生成 `app.asar.bak-<时间戳>`。恢复只需把它改名回 `app.asar`：

```bash
cd "$LOCALAPPDATA/Programs/DeepSeek Harness/resources"
mv app.asar.bak-20261030060331. app.asar    # 换成你自己的时间戳
```

Windows 资源管理器里直接重命名也行（注意文件名末尾那个点要去掉）。

---

## 🔄 官方更新后

**桌面版走 nightly 自动更新，每次更新都会覆盖 `app.asar`，补丁随即失效** —— 这是必然的，不是出错。

更新完照这个顺序来：

```bash
cd dsh-custom-patches
git pull
node desktop/windows/apply-desktop-asar-patches.js --dry-run   # 先确认还能套上
node desktop/windows/apply-desktop-asar-patches.js             # 正式重打
```

- **`--dry-run` 报「版本未在支持列表」**：官方动了补丁的锚点区，需要重新适配 —— 按 [`ADAPTING.md`](ADAPTING.md) 操作，并在 `versions.md` 补一行。
- **`--dry-run` 通过、只提示「待应用」**：说明是零改动兼容，直接跑正式安装即可（历史上多次如此，见 `versions.md`）。
- **想知道官方是否已内置这些功能**：`versions.md` 里有 grep 方法，功能标记命中即为已内置，对应补丁可以退役。

> ⚠️ 官方更新器会**连备份一起清掉**（`app.asar.bak-*` 全部消失），所以每次重打都得等脚本重新生成备份，别指望旧的回滚点还在。

---

## 🤝 贡献与反馈

小项目，**没有单独的贡献指南** —— 有事直接开 [Issue](https://github.com/chai1110/dsh-custom-patches/issues) 或提 PR。

- **报问题**：附上现象、桌面版版本、操作系统、复现步骤、期望结果；有 `Hunk #N failed` 输出最好。
- **提 PR**：欢迎新增功能补丁或修复适配。硬性要求三条 ——
  ① **补丁最小化**（只改必要几处）；② 留下可 grep 的**功能标记**；③ **同步更新 `tools/patch-markers.tsv`** ——
  桌面版脚本读它做功能标记核对。挑标记的铁律：**官方原版里必须 0 次命中**
  （反例：`surfaceOp: "append"` 在原版已出现 8 次，无法判别）。
- **改补丁正文后**：跑一次 `node desktop/windows/apply-desktop-asar-patches.js --dry-run --force`，
  确认 9 个补丁都无失败 hunk。
- **完整适配流程**：见 [`ADAPTING.md`](ADAPTING.md)；桌面版细节见 [`desktop/README.md`](desktop/README.md)。

---

## 📄 License

MIT — 见 [LICENSE](LICENSE)。

## 📎 相关资源

- SSH 多机并行插件: [chai1110/dsh-ssh-remote](https://github.com/chai1110/dsh-ssh-remote)
- 供应商配置模板: [chai1110/dsh-provider-config](https://github.com/chai1110/dsh-provider-config)
- DeepSeek Harness 官方: [deepseek-ai/deepseek-harness](https://github.com/deepseek-ai/deepseek-harness)
