# macOS 桌面版模块

> 📖 [English](README.en.md) ｜ 上层说明：[../README.md](../README.md)

把本仓库的 9 个功能补丁打进 **macOS 版 DeepSeek Harness 桌面应用**。

---

## 一条命令

```bash
# 从仓库根目录执行
bash desktop/macos/dsh-desktop-patch.sh
```

| | 默认路径 |
|---|---|
| 源（**只读，不动**） | `/Applications/DeepSeek Harness.app` |
| 目标（产出） | `~/Applications/DeepSeek Harness Patched.app` |

自定义：

```bash
bash desktop/macos/dsh-desktop-patch.sh "/Applications/DeepSeek Harness.app" "$HOME/Applications/DSH Patched.app"
bash desktop/macos/dsh-desktop-patch.sh --help    # 打印脚本头部说明
```

---

## 前置条件

| 依赖 | 说明 |
|---|---|
| macOS | Apple Silicon 或 Intel 均可，脚本不区分架构 |
| Node.js | 任意近期版本；只用标准库，无 npm 依赖 |
| `patch` | macOS 自带（`/usr/bin/patch`） |
| `codesign` | macOS 自带（Xcode Command Line Tools；系统自带版本足够） |
| 官方桌面版 | 装在 `/Applications/DeepSeek Harness.app` |

---

## 脚本内部（6 步）

| 步骤 | 做什么 | 失败时会怎样 |
|---|---|---|
| 1/6 克隆 | `cp -c -R`（APFS 写时复制，秒级、不占额外磁盘）；非 APFS 自动退回 `cp -R` | 目标目录已存在则先删除；**拒绝**把目标设在 `/Applications` 下 |
| 2/6 抽取 | 用 `../dsh-desktop-asar.mjs cat` 从 asar 里取出 9 个目标文件 | asar 路径找不到即报错（提示 `ASAR_REL` 可能已变） |
| 3/6 打补丁 | `patch -N -F 0 -p1`，**零 fuzz**；产生 `.rej` 即中止 | 中止，**不会**碰目标 app |
| 4/6 改写 | 只替换这 9 个条目，其余字节原样保留 | 工具内部有键序安全检查，不通过即拒绝改写 |
| 5/6 校验 | 逐条目比对 + **9 个功能标记核对** | 任一标记未命中 → **放弃写入**，目标 app 保持原样 |
| 6/6 重签 | ad-hoc 重签（保留 hardened runtime + 原 entitlements），去 quarantine | 报错退出（此时 asar 已替换，重跑一次即可） |

**安全设计**：第 3、5 步任何一环失败，都不会留下「半成品」的 app —— 要么完整可用，要么原样未动。

---

## 产出长什么样

以 2026-09-29 在 DSH 桌面版 `0.2.0-rc.2` 上的实测为例：

```
源: .../app.asar
  大小 121387457  headerBufLen 3393616  dataStart 3393624  数据区 117993833
  dsh-api-session-controller/lib/index.js   offset 12831083 -> 117993833   size 124151 -> 127574
  ...
新 dataStart 3393632（偏移 8），追加 2463070 字节
输出 .app.asar.new  123850535 字节  ✓

未改动且哈希一致: 12964 / 12964
预期替换: 9 / 9
缺失: 0   意外变化: 0
✅ 通过：只有预期条目被替换，其余全部字节一致
```

- **未改动的 12,964 个条目逐字节一致** —— 这是「最小爆炸半径」的直接证据。
- 数据区从 117,993,833 → 120,456,903 字节（只多了被替换文件的增量 2,463,070）。
- 原数据区**原样保留**（旧内容仍在，只是不再被索引），所以 asar 体积只增不减 —— 这是刻意的取舍：
  换来的是「其余条目一个字节都不用动」，比重新打包安全得多。

---

## 重签名细节

改动 asar 后**必须**重签，否则 macOS 会拒绝启动（代码签名封印了 `Resources`）。

| 项 | 值 |
|---|---|
| 签名方式 | ad-hoc（`--sign -`） |
| 保留 | `--options runtime`（hardened runtime）+ 原 entitlements（4 项：`cs.allow-jit`、`cs.allow-unsigned-executable-memory`、`cs.disable-library-validation`、`device.audio-input`） |
| 结果 | `flags=0x10002(adhoc,runtime)`、`Signature=adhoc`、`TeamIdentifier=not set` |
| **不需要**改 `Info.plist` | Electron 的 `EnableEmbeddedAsarIntegrityValidation` 保险丝实测为 `0`，asar 内容变了不会被拒绝，因此 `ElectronAsarIntegrity` 不必同步 |

> 为什么 ad-hoc 就够：Electron 用该保险丝自行校验 asar 完整性，与 macOS 的代码签名是两套机制。
> 保险丝关着 → 改完 asar 只要让 macOS 的签名重新生效（ad-hoc 即可）就能跑。

---

## 功能标记核对

脚本第 5 步会逐个核对（官方原版 0 次命中、打过补丁 ≥1 次命中才算通过）：

| 目标文件 | 标记 | 官方原版 | 打过补丁 |
|---|---|---|---|
| `dsh-api-session-controller/lib/index.js` | `editLastPromptOnce` | 0 | 2 |
| `dsh-api-session-controller/lib/client.js` | `editLastPrompt` | 0 | 2 |
| `dsh-api-session-controller/lib/typert.host.js` | `session/editLastPrompt` | 0 | 1 |
| `dsh-api-session-controller/lib/typert.remote-client.js` | `session/editLastPrompt` | 0 | 1 |
| `dsh-api-remotes/lib/client.js` | `session/editLastPrompt` | 0 | 1 |
| `dsh-agent-loop/lib/index.js` | `tailEvent?.type === "user/message"` | 0 | 1 |
| `dsh-compaction-basic/lib/index.js` | `compactionBackoffDelay` | 0 | 2 |
| `dsh-client-ui-conversation/lib/client.js` | `recallHistory` | 0 | 3 |
| `dsh-client-ui-chat/lib/client.js` | `editLastPrompt` | 0 | 11 |

手动核对单个文件：

```bash
ASAR="$HOME/Applications/DeepSeek Harness Patched.app/Contents/Resources/app.asar"
node desktop/dsh-desktop-asar.mjs cat "$ASAR" "dsh/node_modules/@deepseek-ai/dsh-client-ui-conversation/lib/client.js" | grep -c recallHistory
```

---

## 手动验收（不依赖脚本自检）

脚本只证明「文件被改了」，**功能是否真的可用要人工看一眼**：

1. `open "$HOME/Applications/DeepSeek Harness Patched.app"`
2. 随便发一条消息，等它回复完
3. **① 撤回**：把光标放在输入框里（不要有文字），按 **↑** —— 应调出上一条已发送的消息
4. **② 编辑**：鼠标移到**最后一条用户消息**上 —— 应出现 **✏️ 编辑**入口，改完可重新生成
5. **③ 压缩重试**：这条不好手动造，跳过；由 `patches/compaction-basic` 的标记核对覆盖

> ⚠️ 补丁版与官方版**共用同一个 user-data 目录**（单实例锁 + 固定端口 `19387`），
> 验收前请先退出官方版。

---

## 回滚

```bash
rm -rf "$HOME/Applications/DeepSeek Harness Patched.app"
```

官方原版从未被修改。`/Applications` 里的官方版如需恢复，重装一次即可。

---

## 常见问题

| 现象 | 原因 / 处理 |
|---|---|
| `补丁未能零 fuzz 应用` | 官方桌面版升级了，代码变了。按 [`../../ADAPTING.md`](../../ADAPTING.md) 重新适配 `patches/` |
| `找不到 .../Contents/Resources/app.asar` | 官方改了 app 布局。更新脚本顶部的 `ASAR_REL` |
| `work: unbound variable` | 已在 2026-09-29 修复（`local` 多变量赋值的 bash 坑）。请更新仓库 |
| 打不开 app / 提示已损坏 | 重签名未完成。重跑一次脚本；仍失败则看第 6 步的 `codesign --verify` 输出 |
| 两个 app 不能同时开 | 设计如此（共用 user-data + 单实例锁 + 固定端口 19387） |
| 打完补丁没有编辑按钮 | 先确认第 5 步 9 个标记全绿；再确认打开的是**补丁版**而不是官方版 |
| 夜间更新后补丁消失 | 桌面版走 nightly 自动更新，**官方包每次更新后重跑本脚本**；`bash check-update.sh` 会检测 |

---

## 相关

- 上层总说明：[../README.md](../README.md)
- Windows 模块（待贡献）：[../windows/README.md](../windows/README.md)
- 适配新版流程：[../../ADAPTING.md](../../ADAPTING.md)
