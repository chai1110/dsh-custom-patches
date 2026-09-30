# 桌面版（DeepSeek Harness Desktop）适配指南

> 📖 [English](README.en.md)

本目录负责把本仓库的功能补丁（**撤回上一条消息**、**编辑上一条消息并重新生成**、**压缩失败自动重试**）
打进 **DeepSeek Harness 桌面版**（Electron 应用）。

CLI / 浏览器 / VS Code 三个界面走的是 `node_modules` 里的 npm 包，直接 `patch` 就行（见仓库根目录的
`apply-dsh-patches.sh` / `tools/dsh-patch.mjs`）。**桌面版不一样** —— 它的 dsh 运行时被封在一个
**签名过的 `app.asar`** 里，必须做「asar 外科手术」。这就是本目录存在的原因。

---

## 📊 平台状态

| 平台 | 状态 | 说明 |
|---|---|---|
| **Windows** | ✅ 已实测（2026-09-29，桌面版 `0.2.0-rc.2`） | 源码：`desktop/windows/apply-desktop-asar-patches.js`（跨平台，纯 Node，零依赖） |
| **macOS** | ✅ 已实测（2026-09-29，桌面版 `0.2.0-rc.2`） | 源码：`desktop/macos/dsh-desktop-patch.sh`。**另外，上面那份跨平台脚本的 macOS 分支也已在真机跑通** —— 两套实现独立写，产出的 **9 个目标文件逐字节一致**（整包字节不同，见「两种打包策略」） |
| Linux | ⏳ 待实测 | 尚无贡献者；asar 容器格式与校验逻辑可直接复用 |

> 两个平台**各有一份驱动脚本、暂时分开放置**（理由与合并判据见下文）。
> `desktop/dsh-desktop-asar.mjs` 是两者共享的、**平台无关**的 asar 读写层。

---

## 📌 一句话结论

| 问题 | 答案 |
|---|---|
| 桌面版能靠 profile 目录 / 插件 / 环境变量注入补丁吗？ | **不能**。五条路都试过，全部走不通（见下）。 |
| 那怎么办？ | 复制一份官方 app，**只改 `app.asar` 里的 9 个文件**，然后 ad-hoc 重签名（macOS）/ 直接替换（Windows）。 |
| 官方 app 会被改坏吗？ | **不会**。原版一个字节都不动，补丁打在一个独立的副本上。 |
| 需要新增补丁文件吗？ | **不需要**。复用仓库 `patches/**` 里已有的 9 个 `.patch`。 |
| 会随官方更新失效吗？ | **会**。桌面版走 nightly 自动更新，每次更新后要重跑一次本目录的脚本。 |

---

## ⛔ 为什么只能改 `app.asar`（五条死路，全部实测过）

桌面版把运行时封在 `Contents/Resources/app.asar` 的 `dsh/` 目录下，安装锚点硬指向 asar 内部。
下面五条「更干净」的思路都试过，逐条记录失败原因，免得后人重走：

| 思路 | 为什么走不通 |
|---|---|
| **① profile 目录遮蔽核心包**<br>把改好的包放进 `~/.dsh/profiles/*/node_modules/` | `collectProfileScopePackages` 会把**安装包名本身**作为 `reserved` 传进 `dependencyClosure` —— profile 级包永远无法覆盖核心包，加载器直接忽略。 |
| **② 环境变量改安装锚点**<br>设 `DSH_DESKTOP_DSH_DIR` 指向外部目录 | 该变量被 `development = !app.isPackaged` 门控。**打包版里 `app.isPackaged === true`，分支根本不执行。** |
| **③ 让 Electron 加载外部 app 目录**<br>把 app 目录解出来，用 argv 指过去 | 打包版 `process.defaultApp === false`，argv 里的路径被忽略。 |
| **④ 替换 `.asar.unpacked` 里的副本** | `app.asar.unpacked` 里**只有原生/平台相关包**（`node-pty`、`@img`、`fontkit`、`sherpa-onnx`、`libreoffice-kit`、`@koromix/koffi`）。我们的 9 个目标文件**全都在 asar 内部**，没有 unpacked 副本可替换。 |
| **⑤ 纯客户端插件**（`dsh.client` 插件） | `editLastPrompt` / `recallHistory` 是**客户端 → 服务端的 RPC**。只改前端没有用：host 侧的 `dsh-api-session-controller/lib/index.js`、`dsh-agent-loop`、`dsh-compaction-basic` 也必须一起改，否则请求打到服务端无人应答。 |

> ⚠️ **排查这类问题时的一个坑**：如果工具环境里**已经设了 `ELECTRON_RUN_AS_NODE=1`**，
> Electron 二进制会以 **Node 模式**启动，报出 `Cannot find module 'electron'` ——
> 那是假象，不是真实行为。要看到真 Electron 行为，请用 `env -u ELECTRON_RUN_AS_NODE ...`。

---

## 🔀 桌面版 vs npm 版：两条路，同一套补丁

| | npm 版（网页 / VSCode 插件） | 桌面版（Electron） |
|---|---|---|
| 安装方式 | `npm i -g @deepseek-ai/dsh` | 官方安装包 / 自动更新 |
| 补丁目标位置 | `node_modules/@deepseek-ai/*/lib/*.js` | **`resources/app.asar`（内部打包）** |
| 安装命令 | `node tools/dsh-patch.mjs -y` | `bash desktop/macos/dsh-desktop-patch.sh`（macOS）<br>`node desktop/windows/apply-desktop-asar-patches.js`（Windows） |
| 补丁文件 | 同一份 `patches/**`（9 个，仓库根） | 同一份 `patches/**`（9 个，仓库根） |
| 配置文件 | `~/.dsh/profiles/web/cordis.patch.yml` | `~/.dsh/profiles/desktop/cordis.patch.yml` |
| 端口 | `3080`（launchd 常驻，浏览器与 VSCode 面板共用同一实例；插件无实例时也默认 3080 自起） | `127.0.0.1:19387`（硬编码） |
| 谁在用 | 浏览器、**VSCode 插件**（硬编码 `dsh web`，无法复用桌面版） | 人（桌面 UI） |

**关键**：补丁内容只有一套（`patches/**`），适配官方新版时**只需修一次锚点**；
但**安装要跑两条命令、配置要维护两份**，而且每版两边都要各自 `--dry-run` —— 因为 **asar 内容 ≠ npm tarball**
（CSS 模块类名哈希、构建机绝对路径不同），一边通过不代表另一边也通过。

---

## 🗂 平台分目录策略（macOS 与 Windows **先分开**）

### 为什么分开

两个平台的桌面版**可能不一样**，现在没有证据说明它们一致：

1. **宿主差异**（确定不同）：app 包布局（`Contents/Resources/app.asar` vs `resources/app.asar`）、
   签名机制（macOS 必须重签、Windows 不必）、重启方式（`kill -TERM` vs `taskkill`）、
   `patch` 实现（BSD vs GNU，行为有实质差异 —— 见「平台差异」）。
2. **载荷差异**（待验证）：两平台 `app.asar` 里那 9 个目标文件是否**逐字节一致**，
   目前**尚未验证**。如果官方对两平台打了不同的补丁，同一个 `.patch` 可能在一边零 fuzz、
   在另一边失败。

所以本目录按平台分：

```
desktop/
├── README.md / README.en.md   ← 本文件（总入口）
├── dsh-desktop-asar.mjs       ← 【共享】asar 读取 / 外科式改写 / 逐条目校验（纯 Node，跨平台）
├── macos/                     ← macOS 模块（已实测）
│   ├── README.md / README.en.md
│   └── dsh-desktop-patch.sh   ← 驱动：克隆 → 抽文件 → 打补丁 → 改写 asar → 校验 → 重签名
└── windows/                   ← Windows 模块（他人贡献）
    ├── README.md              ← 交付清单 + 合并判据 + 踩坑清单
    └── apply-desktop-asar-patches.js  ← 跨平台驱动：改 asar + 全量逐字节校验（macOS 分支已实测）
```

### 已经共享的部分

`desktop/dsh-desktop-asar.mjs` 是**平台无关**的 —— asar 容器格式两个平台完全一样。
它承担了最麻烦、最容易写错的部分：

- 解析 asar 头部（`[u32 4][u32 headerBufLen][u32 headerBufLen-4][u32 jsonLen][json][pad][data]`）
- 只把被替换的文件**追加到数据区末尾**，只改这几个条目的 `size` / `offset` / `integrity`，
  其余条目一个字节都不动（最小爆炸半径）
- 逐条目比对改写前后：**未改动的条目必须逐字节相同，改动的条目必须精确替换**

`macos/dsh-desktop-patch.sh` 里则把「平台相关」的部分**集中隔离成一段**（脚本顶部有醒目分隔线）：

```bash
# ══════════════════ 平台相关：Windows 版若复用本脚本，只需改这一段 ══════════════════
PLATFORM="macos"
ASAR_REL="Contents/Resources/app.asar"     # Windows: resources/app.asar
INNER_PREFIX="dsh/node_modules/@deepseek-ai"
clone_app() { cp -c -R "$1" "$2" ... ; }   # Windows: xcopy / robocopy
sign_app()  { codesign ... ; }             # Windows: 无需（Electron 不校验 Authenticode）
# ══════════════════════════════════════════════════════════════════════════════
```

---

## 🔁 合并判据（什么时候可以合并成一份）

**判据：两平台 `app.asar` 里这 9 个目标文件是否逐字节一致。** 验证方法：

```bash
# 在 macOS 与 Windows 上各跑一次，把结果贴到同一个 Issue 里比对
node desktop/dsh-desktop-asar.mjs cat <app.asar> "dsh/node_modules/@deepseek-ai/<相对路径>" | shasum -a 256
```

- **9 个 sha256 全部相同** → 载荷一致，两份驱动脚本可以合并成一份（只保留平台分支），
  `patches/**` 继续共用。
- **有任何一个不同** → 必须保持分开，并且要为不同平台**各自适配 `patches/**`**
  （即需要一套 `patches/windows/**`）。

合并之前，**不要把两个平台的脚本改成一份** —— 那只会让「到底是哪边坏了」更难查。

---

## 🚀 快速开始

### macOS

**前置**：macOS（Apple Silicon / Intel 均可，脚本不区分架构）、Node.js（仅用标准库）、
`patch`（系统自带）、官方桌面版已安装（`/Applications/DeepSeek Harness.app`）。

```bash
# 从仓库根目录执行
bash desktop/macos/dsh-desktop-patch.sh
```

默认行为：

| | 路径 |
|---|---|
| 源（**只读，不动**） | `/Applications/DeepSeek Harness.app` |
| 目标（产出） | `~/Applications/DeepSeek Harness Patched.app` |

也可以显式指定：

```bash
bash desktop/macos/dsh-desktop-patch.sh "/Applications/DeepSeek Harness.app" "$HOME/Applications/DSH Patched.app"
```

脚本做了什么（6 步）：

1. **克隆**官方 app —— APFS 写时复制（`cp -c -R`），秒级完成、**不占额外磁盘**，原版完全不动
2. **抽出** asar 里的 9 个目标文件
3. **打补丁** —— `patch -N -F 0 -p1`，**零 fuzz**（`-F 0` 才能真正证明锚点没被上游改过）
4. **外科式改写 asar** —— 只替换这 9 个条目
5. **校验** —— 逐条目比对 + **功能标记核对**（标记不命中就放弃写入，目标 app 保持原样）
6. **重签名** —— ad-hoc 重签，保留 hardened runtime 与原 entitlements；再去掉 quarantine

启动：

```bash
open "$HOME/Applications/DeepSeek Harness Patched.app"
```

### Windows

```bash
# 在仓库根目录执行

# 1) 试套：只看补丁能否套上，不改动任何文件
node desktop/windows/apply-desktop-asar-patches.js --dry-run

# 2) 正式安装：退出应用 → 备份 app.asar → 打补丁 → 全量校验 → 替换 → 重启
node desktop/windows/apply-desktop-asar-patches.js

# 3) 只生成新 asar 到指定路径，先验证再决定（应用可继续运行）
node desktop/windows/apply-desktop-asar-patches.js --out new.asar
```

| 选项 | 作用 |
|---|---|
| `--asar <path>` | 指定 asar 路径（默认按平台探测；也可用环境变量 `DSH_DESKTOP_ASAR`） |
| `--patches <dir>` | 指定补丁目录（默认自动定位到仓库根 `patches/`） |
| `--out <path>` | 只生成新 asar，不退出/备份/替换/重启 |
| `--dry-run` | 只试套；已应用的补丁会报「已应用」并跳过 |
| `--force` | 桌面版版本不在支持列表时仍继续 |
| `--no-backup` / `--no-restart` / `--no-quit` | 分别关闭备份 / 替换后自动重启 / 替换前主动退出应用 |

依赖：Node（读写 asar 由脚本自带）+ `patch` 命令（Windows 装 Git for Windows 即有，也可用 `PATCH_BIN` 指定）。

> 该脚本是**跨平台**的，`--asar` 默认路径按平台探测，macOS 分支已于 2026-09-29 在真机实测通过。

### 两面一起

```bash
bash patch-all.sh          # CLI 侧（浏览器 + VS Code）+ 桌面版，并交叉核对功能标记
bash patch-all.sh --check  # 只核对，不修改任何东西
```

---

## 🔧 工作原理（为什么敢直接改 asar）

1. **解析 asar header**
   ```
   [0..7]      uint32(4) + uint32(headerSize)
   [8..8+hs]   header pickle: uint32(strLen+4) + uint32(strLen) + JSON
   [8+hs...]   文件内容区；条目绝对偏移 = 8 + hs + Number(entry.offset)
   ```
   `entry.offset` 是**字符串**必须 `Number()`；`entry.integrity` 是整体 SHA256 + 4 MiB 分块哈希；
   `unpacked: true` 的条目内容在 `app.asar.unpacked/`，只更新 offset 不写内容。
2. **套补丁**：把 `patches/**` 的 `.patch` 用系统 `patch` 套到从 asar 抽出的目标文件上。
3. **幂等靠反向 dry-run**：`patch --dry-run -N` 对**已打过补丁**的文件仍可能报成功，直接 apply 会
   **二次叠加**（实测 144754 → 145128 字节，静默损坏）。所以先 `patch --dry-run -R -p1`：
   成功且无 `Unreversed` → 已应用，跳过；失败且提示 `Unreversed patch detected!` → 待应用，再正向套。
4. **重建 asar**：按 header 深度优先顺序重写（先断言 offset 单调递增）。
5. **替换前全量校验（任一不过就不替换，出错自动回滚）**：
   - header 可解析、条目数与 unpacked 条目数不变、offset 单调；
   - 版本在支持列表 `0.2.0-rc.1` / `0.2.0-rc.2`（否则 `--force`）；
   - 9 个目标 dry-run 全部可套；
   - 补丁后目标命中功能标记（见下方核对表）；
   - **新旧 asar 除 9 个目标外全部文件逐字节一致**（Windows 侧本机 11461/11461 通过；
     macOS 侧本机 12964/12964 个未目标条目通过）；
   - 新 asar 再解析一次，标记仍在。
6. **退出 → 备份 → 替换 → 重启 → 健康检查**（探测端口是否监听，HTTP 401 属正常待鉴权）。

> 关于 0 字节文件：asar 里若干 `size: 0` 的文件，官方 header 的 `integrity.blocks` 是 1 块而按内容算 0 块，
> 这是**原包自带的口径差异**，不是损坏 —— 这些文件我们不改，`integrity` 原样保留。

**可复现证据**：从 pristine 备份重建出的 asar 与手工安装到线上的 asar **SHA256 完全一致**
（Windows 侧 `F24882B003814BE33FDEA47E761553DD45EAAB9E7B7856CBCB07A492CEE036FD`；
macOS 侧 `4286629a…`，连跑两次字节完全相同）。

### ⚠️ 两种打包策略：产出**不**逐字节相同（但等价）

两个模块的驱动脚本独立写成，**对 asar 的改写策略不同**，所以整包 SHA256 不一样：

| | `macos/dsh-desktop-patch.sh` | `windows/apply-desktop-asar-patches.js` |
|---|---|---|
| 策略 | 保留原数据区，**把 9 个新文件追加到末尾**，只改这 9 个条目的 `offset`/`size`/`integrity` | 按 header 顺序**就地紧凑重排**整个数据区 |
| 产出大小 | 123,850,535 字节（原 121,387,457） | 121,441,457 字节 |
| 整包 sha256 | `4286629a…` | `5360c9e5…` |

**两者等价**：2026-09-29 实测，从两份产出里各抽出 9 个目标文件比对，
**9/9 逐字节相同**（`127574` / `144754` / `192222` / `67241` / `514452` / `73293` / `51438` / `721850` / `570246` 字节），
且两份都能通过全量校验（非目标文件逐字节一致 + 9 个功能标记命中）。

> **所以**：「可复现」指的是**同一脚本重复运行结果一致**，不是两个脚本产出同一串字节。
> 做「有没有被改坏」的判断时，请比对**目标文件内容**或**功能标记**，不要比对整包 sha256。

---

## 🧭 平台差异（两个平台都已实测）

| 环节 | Windows（✅ 已实测） | macOS（✅ 已实测） |
|---|---|---|
| asar 默认路径 | `%LOCALAPPDATA%\Programs\DeepSeek Harness\resources\app.asar` | `/Applications/DeepSeek Harness.app/Contents/Resources/app.asar` |
| 退出应用 | `taskkill /IM "DeepSeek Harness.exe"`（只杀这一个，绝不 `taskkill /IM node.exe`） | `pkill -f "DeepSeek Harness"`（沙箱里 `osascript ... to quit` 会报 `-10004`，不可用） |
| 启动应用 | 直接执行 `<root>\DeepSeek Harness.exe` | `open -a <找到的 .app>`（脚本向上层目录查找 `.app` 结尾的目录） |
| `patch` 命令 | Git for Windows 的 `patch.exe`（**GNU patch**） | 系统自带 **BSD `patch`** —— ⚠️ 行为有实质差异，见下 |
| 代码签名 | 无需处理（Electron 不校验 Authenticode） | **必须 ad-hoc 重签** + 去 quarantine |
| 路径分隔符 | `\` | `/`（脚本内部统一用 `path.join`） |

### macOS 实测回填的坑（原先只是「预期」，现已有结论）

1. ⭐ **BSD `patch` 不加 `-N` 会交互式挂起，脚本被 SIGTERM 杀死（exit 137、零输出）**
   - **现象**：脚本一声不响就死，退出码 137，没有任何输出。
   - **根因**：BSD `patch` 在「反向试套不干净」时会**交互式提问**
     `Unreversed patch detected! Ignore -R? [n]`。stdin 不是终端时它等不到回答，
     进程卡住 → 被环境的命令守卫按进程组 SIGTERM 掉。
   - **修复**：所有 dry-run 与 apply 都加 `-N`（`--forward`）。加上后 BSD `patch` 会干净地打印
     `Ignoring previously applied (or reversed) patch.` / `5 out of 5 hunks ignored` 并以 exit 1 结束，
     不再提问。
   - **GNU patch（Git for Windows）不会这样** —— 所以这个坑**只在 macOS 上出现**，
     Windows 上测不出。
   - **教训**：跨平台脚本里凡是要判「是否已应用」，`-N` 和 `-F 0` 必须同时给。
2. **代码签名**：改完 asar 签名必然失效 → 可能被 Gatekeeper 拒绝启动。
   用 `codesign --force --sign - --options runtime --entitlements <plist> <app>` ad-hoc 重签；
   重签后 `codesign --verify` 报 `valid on disk` + `satisfies its Designated Requirement`，
   `flags=0x10002(adhoc,runtime)`、`Signature=adhoc`。
3. **quarantine 属性**：`xattr -dr com.apple.quarantine <app>`。
4. **不需要改 `Info.plist`**：Electron 保险丝 `EnableEmbeddedAsarIntegrityValidation = 0`（实测确认），
   asar 内容变了也不会被拒绝，无需同步 `ElectronAsarIntegrity`。
5. **自动更新**：macOS 侧同样带 `app-update.yml`，更新会覆盖 asar、补丁全丢。

---

## ✅ 功能标记核对表

补丁是否真的生效，用「官方原版里不存在、打过补丁才出现」的字符串来判定。
下表已实测（`patches/` 版本对应 DSH `0.2.0-rc.2` 桌面版 / `0.2.0-rc.1` CLI 侧）：

| 目标文件（相对 `@deepseek-ai/`） | 功能标记 | 官方原版 | 打过补丁 |
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

> 这张表存在 `tools/patch-markers.tsv`（**单一数据源**）—— `patch-all.sh`、桌面版脚本、
> `check-update.sh` 都读同一份，避免三处各写一套标记而漂移。
>
> 选标记时的教训：一开始给 `dsh-agent-loop` 选的是 `surfaceOp: "append"`，
> 但它在官方原版里**已经出现 8 次** —— 完全不能用来判别。标记必须是「原版 0 次」的字符串。
> `bash check-update.sh` 会重新跑这张表，官方更新后标记消失即说明补丁被覆盖。

---

## ⚖️ 代价与限制（用之前请知悉）

| 项 | 说明 |
|---|---|
| **签名变成 ad-hoc（仅 macOS）** | 重签后 `Signature=adhoc`、`TeamIdentifier=not set`、`flags=0x10002(adhoc,runtime)`。功能不受影响；若你有依赖「官方签名」的合规要求，请勿使用。Windows 无此问题。 |
| **不需要改 `Info.plist`** | Electron 的保险丝 `EnableEmbeddedAsarIntegrityValidation = 0`（实测确认），所以 asar 内容变了也不会被拒绝，无需同步 `ElectronAsarIntegrity`。 |
| **nightly 自动更新会覆盖** | 官方包更新后，补丁版需要**重新执行脚本**。`bash check-update.sh` 会检测并提示。 |
| **与官方版不能同时运行** | 两者**共用同一个 user-data 目录**，加上单实例锁与固定端口 `19387`，同时启动会失败。用之前请先退出另一个。 |
| **端口 19387 是硬编码的** | 桌面版不像 CLI 那样可以 `--port` 指定，冲突时只能让别的程序让路。 |
| **不改官方 app** | macOS 侧所有产出都在 `~/Applications/` 下，`/Applications/DeepSeek Harness.app` 始终保持官方原样。 |

---

## 🔄 每版更新清单（桌面侧）

完整清单（npm + 桌面 + 配置 + 插件）见仓库根 [`ADAPTING.md`](../ADAPTING.md) 的「新版适配总清单」。
桌面侧就 4 步：

1. 先 `--dry-run`（macOS：`bash desktop/macos/dsh-desktop-patch.sh` 的试跑模式；
   Windows：`node desktop/windows/apply-desktop-asar-patches.js --dry-run`）
   —— 看 9 个补丁还能不能套、是否已被自动更新冲掉；
2. 有「待应用」→ 正式安装（脚本自动校验 + 备份 + 重启）；
3. 若官方改了目标文件结构 → 修 `patches/**` 里的锚点（**这一步 npm 版和桌面版共用，修一次两边受益**）；
4. 桌面版版本号若变了 → 把它加进脚本的支持列表（否则要用 `--force`）。

配置侧（模型、重试策略、主题）改动，见 [`dsh-provider-config`](https://github.com/chai1110/dsh-provider-config)
的 `desktop/` 目录：桌面 profile 与网页 profile **互相独立，改一边不会影响另一边**。

---

## ↩️ 回滚

**macOS**：补丁版是**独立的一份 app**，回滚就是删掉它：

```bash
rm -rf "$HOME/Applications/DeepSeek Harness Patched.app"
```

官方原版从未被修改，删完即恢复原状。

**Windows**：把 `resources/app.asar.bak-<时间戳>` 改名回 `app.asar` 即可
（替换前一定有备份，除非用了 `--no-backup`）。

若想把官方版恢复成「刚下载」的状态，重新从官方渠道安装一次即可（本仓库不会碰它）。

---

## 🔗 与 CLI 侧补丁的关系

- **补丁文件是同一套**：`patches/**` 下的 9 个 `.patch`，CLI 侧与桌面版共用，不重复维护。
- **目标不同**：CLI 侧打在 `node_modules/@deepseek-ai/**`，桌面版打在 `app.asar` 内部。
- **一键打两面**：仓库根目录的 `patch-all.sh` 会依次处理两面，并对**两面都做功能标记交叉核对**，
  输出一张矩阵 —— 这是确认「浏览器 / VS Code / 桌面版三个界面功能一致」最快的方法。

---

## 🤝 协作约定（两个模块如何共存）

1. **不要把 `macos/dsh-desktop-patch.sh` 直接改成跨平台脚本再提交**（会同时改坏 macOS 路径）；
   Windows 那份跨平台脚本保留在 `desktop/windows/`，两者互不覆盖。
2. 复用 `desktop/dsh-desktop-asar.mjs`（它是跨平台的，不用改）。
3. 把平台相关部分写在脚本顶部的「平台相关」段落里，方便日后比对与合并。
4. 改标记时**只改 `tools/patch-markers.tsv`**，三个脚本自动跟随。
5. 想让两份合并成一份时，先在 PR 里附上**9 个目标文件的 sha256**（见「合并判据」），
   证明载荷一致再合并；否则继续分开维护。

---

## 📎 相关

- 仓库主 README：[../README.md](../README.md)
- 适配官方新版的完整流程：[../ADAPTING.md](../ADAPTING.md)
- Windows 模块交付清单与踩坑：[windows/README.md](windows/README.md)
- macOS 模块详细步骤：[macos/README.md](macos/README.md)
- 桌面版适配的调研与踩坑记录：[../ADAPTING.md](../ADAPTING.md) 与 [`versions.md`](../versions.md)
