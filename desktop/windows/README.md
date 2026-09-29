# Windows 桌面版模块

> 📖 [English](#english-version) ｜ 上层说明：[../README.md](../README.md)

**状态：✅ 已实测。** 本模块的驱动脚本 `apply-desktop-asar-patches.js` 在
**Windows 桌面版 `0.2.0-rc.1` / `0.2.0-rc.2`** 上验证通过；
**2026-09-29 又在 macOS 真机跑通了它的 macOS 分支**（见下方「macOS 上跑本脚本」）。

与 macOS 模块的关系：**两个模块并存、互不覆盖**，遵循「先分开、后合并」的策略
（合并判据见下）。`../dsh-desktop-asar.mjs` 是两者共享的、平台无关的 asar 读写层。

---

## 这个模块里有什么

```
desktop/windows/
├── README.md                          # 本文件
└── apply-desktop-asar-patches.js      # 跨平台驱动脚本（纯 Node，零依赖，460 行）
```

驱动脚本做的事，与 macOS 版**流程一一对应**：

```
1. 解析 asar header，读出 9 个目标文件
2. 用仓库 patches/ 下的 9 个 .patch 打补丁（反向试套判幂等 + -F 0 零 fuzz）
3. 外科式改写 asar（只替换这 9 个条目，其余条目一字节不动）
4. 全量逐字节校验 + 9 个功能标记核对（任一不过 → 放弃替换，自动回滚）
5. 退出应用 → 备份 → 替换 → 重启 → 健康检查
```

用法（在仓库根目录执行）：

```bash
node desktop/windows/apply-desktop-asar-patches.js                # 自动探测 app.asar，打补丁并替换（会先退出应用）
node desktop/windows/apply-desktop-asar-patches.js --dry-run      # 只试套补丁，不生成、不替换
node desktop/windows/apply-desktop-asar-patches.js --out new.asar # 生成新 asar 到指定路径，不替换原文件（应用可继续运行）
node desktop/windows/apply-desktop-asar-patches.js --asar /path/to/app.asar --force
```

| 选项 | 作用 |
|---|---|
| `--asar <path>` | app.asar 路径（默认按平台自动探测，也可用环境变量 `DSH_DESKTOP_ASAR`） |
| `--patches <dir>` | 补丁目录（默认仓库根的 `patches/`，自动向上定位） |
| `--out <path>` | 输出新 asar 到该路径，跳过 退出/备份/替换/重启 |
| `--dry-run` | 只做补丁试套（已应用的补丁会报「已应用」） |
| `--force` | 桌面版版本不在支持列表时仍继续 |
| `--no-backup` / `--no-restart` / `--no-quit` | 分别关闭备份 / 替换后自动重启 / 替换前主动退出应用 |
| `--help` | 显示帮助 |

依赖：Node（读写 asar 由脚本自带）+ `patch` 命令（Windows 装 Git for Windows 即有，也可用 `PATCH_BIN` 指定）。

**回滚**：把 `resources/app.asar.bak-<时间戳>` 改名回 `app.asar` 即可（替换前一定有备份，除非 `--no-backup`）。

---

## 为什么单独一个目录，而不是把 macOS 脚本改成跨平台

因为**两平台的桌面版可能不一样**，而现在没有证据说明它们一致：

| 维度 | macOS | Windows |
|---|---|---|
| app 内 asar 路径 | `Contents/Resources/app.asar`（✅ 实测） | `resources/app.asar`（✅ 实测） |
| asar 内包前缀 | `dsh/node_modules/@deepseek-ai`（✅ 实测） | 同左（✅ 实测） |
| 是否需要重签名 | **必须**（改动 asar 会使签名失效，macOS 拒绝启动） | 不需要（Electron 不校验 Authenticode） |
| 克隆方式 | `cp -c -R`（APFS 写时复制） | `robocopy /E` 或 `xcopy /E /I` |
| `patch` 实现 | **BSD patch**（⚠️ 与 GNU 行为有实质差异） | Git for Windows 的 **GNU patch** |
| **9 个目标文件是否逐字节一致** | — | **未验证**（见下文「合并判据」） |

如果现在就把 `macos/dsh-desktop-patch.sh` 改成跨平台脚本，等于在**没有验证**的前提下
同时改动 macOS 的路径逻辑 —— 一旦 Windows 侧对不上，就分不清是哪边的锅。

---

## ⚠️ macOS 上跑本脚本（2026-09-29 实测补充）

本脚本是跨平台的，macOS 分支已经跑通，但有**两点必须知道**：

### 1. `patch` 必须带 `-N`（脚本已内置，勿删）

这是**本次实测发现的最关键的坑**，也是「平台差异」里预判的 BSD/GNU 差异的实证：

| 调用方式 | macOS（BSD patch）结果 |
|---|---|
| `patch --dry-run --reverse -p1` | **卡死** → 被环境的命令守卫 SIGTERM 掉，退出码 **137、零输出** |
| `patch --dry-run -N -F 0 --reverse -p1` | exit 1，干净输出 `5 out of 5 hunks ignored` ✅ |

**根因**：BSD `patch` 在「反向试套不干净」时会**交互式追问**
`Unreversed patch detected! Ignore -R? [n]`。stdin 不是终端时它等不到回答，进程卡住。
**GNU patch（Windows）不会这样** —— 所以这个问题**只在 macOS 上暴露**，Windows 上测不出来。

脚本里所有 dry-run 与 apply 调用都已带 `-N`（`--forward`）与 `-F 0`，源码中有详细注释说明原因。

### 2. 本脚本**不重签名** —— macOS 上直接替换 `/Applications` 里的官方 app 会启动失败

Windows 不需要签名，所以脚本没有这段逻辑。在 macOS 上：

- 用 `--out` 生成新 asar 是**安全**的（不改动任何已安装的 app）；
- 但若让它直接替换 `/Applications/DeepSeek Harness.app` 里的 asar，签名失效 → Gatekeeper 可能拒绝启动。

**两条出路**：

- 改用 [`../macos/dsh-desktop-patch.sh`](../macos/dsh-desktop-patch.sh) —— 它把「克隆 → 打补丁 → 重签名」串好了；
- 或者自己补一步 ad-hoc 重签：
  ```bash
  codesign --force --sign - --options runtime --entitlements <原 entitlements> "/Applications/DeepSeek Harness.app"
  xattr -dr com.apple.quarantine "/Applications/DeepSeek Harness.app"
  ```

### 3. 来源指纹 ✅ 已支持（2026-09-29 补上）

脚本会在替换完成后，往 asar 同目录写一份 `.dsh-desktop-patch.json`，供 `check-update.sh`
判断「官方是否已更新、补丁是否被覆盖」：

```json
{ "patchedAt": "...", "platform": "macos",
  "sourceApp": "/Users/…/DSH FpProbe.app",
  "sourceAsarSha256": "18d5036b…", "sourceAsarSize": 121387457,
  "patchedAsarSha256": "5360c9e5…", "patchedAsarSize": 121441457,
  "targets": [ "dsh-api-session-controller/lib/index.js", … ] }
```

> ⚠️ 指纹**必须在重签名之前**写入（往已签名的 app 里加文件会让签名失效）。
> 本脚本不做重签；若你在 macOS 上要补重签，请放在替换之后。

### 4. 两种打包策略：产出**不**与 macOS 模块逐字节相同（但等价）

见 [`../README.md`](../README.md) 的「两种打包策略」。摘要：本脚本**就地紧凑重排**数据区
（产出 121,441,457 字节 / `5360c9e5…`），macOS 脚本**追加到数据区末尾**
（123,850,535 字节 / `4286629a…`）。实测从两份产出各抽 9 个目标文件比对，**9/9 逐字节相同**，
两份都通过全量校验与功能标记核对 ⇒ 等价。判断「有没有被改坏」请看目标文件内容，不要看整包 sha256。

---

## 合并判据

这是**决定两个模块能否合并**的唯一依据：

```powershell
# Windows：对 9 个目标文件各跑一次，把 9 个 sha256 贴进 PR
node desktop/dsh-desktop-asar.mjs cat "<Windows app.asar>" "dsh/node_modules/@deepseek-ai/<相对路径>" | Get-FileHash -Algorithm SHA256
```

```bash
# macOS 侧对应命令（对照用）
node desktop/dsh-desktop-asar.mjs cat "<macOS app.asar>" "dsh/node_modules/@deepseek-ai/<相对路径>" | shasum -a 256
```

| 实测结果 | 结论 |
|---|---|
| **9 个 sha256 全部相同** | 载荷一致 → 两份驱动脚本可合并成一份（只保留平台分支），`patches/**` 继续共用 |
| **有任何一个不同** | 必须保持分开，且需要新增 `patches/windows/**`（同一份补丁在两平台可能锚点不同） |

合并之前**不要**动 macOS 模块。

9 个目标文件（相对 `@deepseek-ai/`）：

```
dsh-api-session-controller/lib/index.js
dsh-api-session-controller/lib/client.js
dsh-api-session-controller/lib/typert.host.js
dsh-api-session-controller/lib/typert.remote-client.js
dsh-api-remotes/lib/client.js
dsh-agent-loop/lib/index.js
dsh-compaction-basic/lib/index.js
dsh-client-ui-conversation/lib/client.js
dsh-client-ui-chat/lib/client.js
```

---

## 写脚本时的注意事项（踩坑清单）

| 坑 | 说明 |
|---|---|
| ⭐ **BSD patch 不加 `-N` 会交互式挂起** | 见上文。表现为**零输出 + 退出码 137**，极难排查。跨平台脚本里 `-N` 与 `-F 0` 必须同时给 |
| **`offset` 必须是字符串** | asar 头部 JSON 里 `offset` 是**字符串**、`size` 是数字。写成数字会被 `@electron/asar` 拒绝：`Invalid archive header ... "offset" must be a string, got number`。本仓库的 `dsh-desktop-asar.mjs` 已处理，直接用即可 |
| **必须重算 `integrity`** | 每个条目带 `integrity`（分块 sha256，4 MiB 块）。替换内容后不重算会导致完整性校验失败。工具已处理 |
| **临时文件别用 `.asar` 后缀** | 某些环境（含自动化沙箱）会拒绝「新建 `.asar` 文件」。macOS 版的做法是写 `.app.asar.new` 再 `mv` 覆盖。Windows 上同理，注意先关掉占用该文件的进程 |
| **零 fuzz 才可信** | `patch -F 0` 才能真正证明锚点没被上游改过。默认 `fuzz=2` 会容忍上下文不匹配，可能在错误位置「成功」 |
| **标记必须是原版 0 次** | 判别标记要用「官方原版里 0 次命中」的字符串。反例：`surfaceOp: "append"` 在官方 `dsh-agent-loop` 里已出现 8 次，完全不能用来判别。**标记统一维护在 `tools/patch-markers.tsv`**，脚本从该表读取，不要各写一套 |
| **app 正在运行时别改** | 改 asar 前先退出桌面版（文件被占用会失败）；Windows 上还要注意文件锁 |
| **别改官方安装目录** | 克隆一份再改，原版保持原样 —— 这是整个方案的底线 |

---

## English version

**Status: ✅ Verified.** The driver script `apply-desktop-asar-patches.js` is verified on the
**Windows desktop build `0.2.0-rc.1` / `0.2.0-rc.2`**, and **its macOS branch was verified on real
hardware on 2026-09-29** (see "Running this script on macOS"). It now also writes the
`.dsh-desktop-patch.json` source fingerprint, so `check-update.sh` works for installs made with it.

Relationship to the macOS module: **the two modules coexist and never overwrite each other**, following
a "separate first, merge later" strategy (merge criterion below). `../dsh-desktop-asar.mjs` is the
shared, platform-independent asar read/write layer used by both.

### Why a separate directory instead of one cross-platform script

Because the two platforms' desktop builds **may differ**, and we have no evidence yet that they don't:

| Dimension | macOS | Windows |
|---|---|---|
| asar path inside the bundle | `Contents/Resources/app.asar` (✅ measured) | `resources/app.asar` (✅ measured) |
| package prefix inside the asar | `dsh/node_modules/@deepseek-ai` (✅ measured) | same (✅ measured) |
| Re-signing required? | **Yes** (changing the asar invalidates the signature; macOS refuses to launch) | No (Electron does not verify Authenticode) |
| Clone method | `cp -c -R` (APFS copy-on-write) | `robocopy /E` or `xcopy /E /I` |
| `patch` implementation | **BSD patch** (⚠️ materially different from GNU) | Git for Windows' **GNU patch** |
| **Are the 9 target files byte-identical?** | — | **Unverified** (see "Merge criterion") |

### ⚠️ Running this script on macOS (measured 2026-09-29)

The script is cross-platform and its macOS branch works, but two things must be known:

1. **`patch` must be given `-N`** (already built in — do not remove it).
   Without `-N`, BSD `patch` **interactively prompts** `Unreversed patch detected! Ignore -R? [n]`
   when the reverse dry-run does not apply cleanly. With no terminal on stdin it blocks forever, and
   the process group gets SIGTERM'd — the symptom is **zero output and exit code 137**, which is very
   hard to diagnose. GNU patch (Windows) behaves differently, so **this only surfaces on macOS**.
   All dry-run and apply invocations in the script pass `-N` (`--forward`) together with `-F 0`.

2. **This script does not re-sign.** Windows needs no signature, so that step is absent. On macOS,
   using `--out` is safe, but replacing the asar inside `/Applications/DeepSeek Harness.app` will
   invalidate the signature and Gatekeeper may refuse to launch it. Either use
   [`../macos/dsh-desktop-patch.sh`](../macos/dsh-desktop-patch.sh) (which clones and re-signs), or add
   an ad-hoc re-sign step yourself:
   `codesign --force --sign - --options runtime --entitlements <plist> <app>` + `xattr -dr com.apple.quarantine <app>`.

3. **No source fingerprint is written.** The macOS module drops a `.dsh-desktop-patch.json` into the
   target app so `check-update.sh` can tell whether an official update overwrote the patches. This
   script does not write it, so `check-update.sh` reports "no source fingerprint" for installs made
   with this script — only the feature markers can be checked. PRs welcome.

### Merge criterion

```powershell
node desktop/dsh-desktop-asar.mjs cat "<Windows app.asar>" "dsh/node_modules/@deepseek-ai/<relpath>" | Get-FileHash -Algorithm SHA256
```

| Result | Conclusion |
|---|---|
| **All 9 sha256 values match** | Payloads agree → the two drivers can be merged into one (keeping only platform branches); `patches/**` stays shared |
| **Any value differs** | They must stay separate, and a `patches/windows/**` set becomes necessary (the same patch may have different anchors per platform) |

Do not modify the macOS module before merging.

### Pitfalls worth knowing

- ⭐ **BSD patch hangs without `-N`** — see above. Zero output plus exit 137. Always pass `-N` *and* `-F 0`.
- **`offset` must be a string** in the asar header JSON (`size` is a number); writing a number makes
  `@electron/asar` reject the archive. `dsh-desktop-asar.mjs` already handles this.
- **`integrity` must be recomputed** per entry (chunked sha256, 4 MiB blocks) after replacing content.
- **Do not use a `.asar` suffix for temporary files** — some environments refuse to create new `.asar`
  files. Write `.app.asar.new` and `mv` it over. *(2026-09-29: this script used `app.patched.asar`
  and failed on macOS with `Brokered file token refused`; fixed to `app.patched.asar.new`.)* On Windows, make sure no process holds the file open.
- **Zero fuzz is the only trustworthy check** — `patch -F 0`.
- **Markers must have 0 occurrences upstream.** Counter-example: `surfaceOp: "append"` already appears
  8 times in the official `dsh-agent-loop`. Markers live in `tools/patch-markers.tsv` — a single source
  of truth; do not duplicate them per script.
- **Never patch a running app** — quit the desktop app first.
- **Never modify the official installation** — clone first. That is the bottom line of this whole approach.

---

## 相关 / See also

- 上层总说明 / Parent: [../README.md](../README.md) ｜ [../README.en.md](../README.en.md)
- macOS 模块 / macOS module: [../macos/README.md](../macos/README.md)
- 功能标记单一数据源 / Marker single source of truth: [../../tools/patch-markers.tsv](../../tools/patch-markers.tsv)
- 适配新版流程 / Adapting to a new release: [../../ADAPTING.md](../../ADAPTING.md)
