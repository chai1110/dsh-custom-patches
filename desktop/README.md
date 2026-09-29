# 桌面版（DeepSeek Harness Desktop）适配指南

> **平台状态**
>
> | 平台 | 状态 | 说明 |
> |---|---|---|
> | **Windows** | ✅ 已实测（2026-09-29，`0.2.0-rc.2`） | 源码与教程见 `desktop/windows/` |
> | **macOS** | ⏳ 待实测 | 脚本已内置 darwin 分支与路径探测，但**未在真机跑过**，见「平台差异」 |
> | Linux | ⏳ 待实测 | 脚本已写探测路径，未验证 |

桌面版是 **Electron 应用**，**不走 npm 全局安装**：安装目录、进程、端口、profile 全部与 npm 版独立，
只有 `~/.dsh` 根目录共享（凭据、会话数据）。所以它有**自己的一套适配方式** —— 本目录就是这套方式的源码与教程。

---

## 一、桌面版 vs npm 版：两条路，同一套补丁

| | npm 版（网页 / VSCode 插件） | 桌面版（Electron） |
|---|---|---|
| 安装方式 | `npm i -g @deepseek-ai/dsh` | 官方安装包 / 自动更新 |
| 补丁目标位置 | `node_modules/@deepseek-ai/*/lib/*.js` | **`resources/app.asar`（内部打包）** |
| 安装命令 | `node tools/dsh-patch.mjs -y` | `node desktop/windows/apply-desktop-asar-patches.js` |
| 补丁文件 | 同一份 `patches/**`（9 个，仓库根） | 同一份 `patches/**`（9 个，仓库根） |
| 配置文件 | `~/.dsh/profiles/web/cordis.patch.yml` | `~/.dsh/profiles/desktop/cordis.patch.yml` |
| 端口 | `8080`（我们常驻）/ `3080`（VSCode 插件自起） | `127.0.0.1:19387` |
| 谁在用 | 浏览器、**VSCode 插件**（硬编码 `dsh web`，无法复用桌面版） | 人（桌面 UI） |

**关键**：补丁内容只有一套（`patches/**`），适配官方新版时**只需修一次锚点**；
但**安装要跑两条命令、配置要维护两份**，而且每版两边都要各自 `--dry-run` —— 因为 **asar 内容 ≠ npm tarball**
（CSS 模块类名哈希、构建机绝对路径不同），一边通过不代表另一边也通过。

---

## 二、30 秒上手

```bash
# 在仓库根目录执行

# 1) 试套：只看补丁能否套上，不改动任何文件
node desktop/windows/apply-desktop-asar-patches.js --dry-run

# 2) 正式安装：退出应用 → 备份 app.asar → 打补丁 → 全量校验 → 替换 → 重启
node desktop/windows/apply-desktop-asar-patches.js

# 3) 只生成新 asar 到指定路径，先验证再决定（应用可继续运行）
node desktop/windows/apply-desktop-asar-patches.js --out new.asar
```

**回滚**：把 `resources/app.asar.bak-<时间戳>` 改名回 `app.asar` 即可（替换前一定有备份，除非 `--no-backup`）。

**⚠️ 自动更新**：桌面版带 `resources/app-update.yml`，**升级会覆盖 asar、9 个补丁全部丢失**。
每次更新后先跑 `--dry-run`：9 个都「已应用」就没事，出现「待应用」就正式安装一次。

### 选项

| 选项 | 作用 |
|---|---|
| `--asar <path>` | 指定 asar 路径（默认按平台探测；也可用环境变量 `DSH_DESKTOP_ASAR`） |
| `--patches <dir>` | 指定补丁目录（默认自动定位到仓库根 `patches/`） |
| `--out <path>` | 只生成新 asar，不退出/备份/替换/重启 |
| `--dry-run` | 只试套；已应用的补丁会报「已应用」并跳过 |
| `--force` | 桌面版版本不在支持列表时仍继续 |
| `--no-backup` / `--no-restart` / `--no-quit` | 分别关闭备份 / 替换后自动重启 / 替换前主动退出应用 |

依赖：Node（读写 asar 由脚本自带）+ `patch` 命令（Windows 装 Git for Windows 即有，也可用 `PATCH_BIN` 指定）。

---

## 三、工作原理（为什么敢直接改 asar）

1. **解析 asar header**
   ```
   [0..7]      uint32(4) + uint32(headerSize)
   [8..8+hs]   header pickle: uint32(strLen+4) + uint32(strLen) + JSON
   [8+hs...]   文件内容区；条目绝对偏移 = 8 + hs + Number(entry.offset)
   ```
   `entry.offset` 是**字符串**必须 `Number()`；`entry.integrity` 是整体 SHA256 + 4 MiB 分块哈希；
   `unpacked: true` 的条目内容在 `app.asar.unpacked/`，只更新 offset 不写内容。
2. **套补丁**：把 `patches/**` 的 .patch 用系统 `patch` 套到从 asar 抽出的目标文件上。
3. **幂等靠反向 dry-run**：`patch --dry-run -N` 对**已打过补丁**的文件仍可能报成功，直接 apply 会
   **二次叠加**（实测 144754 → 145128 字节，静默损坏）。所以先 `patch --dry-run -R -p1`：
   成功且无 `Unreversed` → 已应用，跳过；失败且提示 `Unreversed patch detected!` → 待应用，再正向套。
4. **重建 asar**：按 header 深度优先顺序重写（先断言 offset 单调递增）。
5. **替换前全量校验（任一不过就不替换，出错自动回滚）**：
   - header 可解析、条目数与 unpacked 条目数不变、offset 单调；
   - 版本在支持列表 `0.2.0-rc.1` / `0.2.0-rc.2`（否则 `--force`）；
   - 9 个目标 dry-run 全部可套；
   - 补丁后目标命中功能标记（`editLastPrompt` / `recallHistory` / `compactionBackoffDelay`）；
   - **新旧 asar 除 9 个目标外全部文件逐字节一致**（本机 11461/11461 通过）；
   - 新 asar 再解析一次，标记仍在。
6. **退出 → 备份 → 替换 → 重启 → 健康检查**（探测端口是否监听，HTTP 401 属正常待鉴权）。

> 关于 0 字节文件：asar 里若干 `size: 0` 的文件，官方 header 的 `integrity.blocks` 是 1 块而按内容算 0 块，
> 这是**原包自带的口径差异**，不是损坏 —— 这些文件我们不改，`integrity` 原样保留。

**可复现证据**：从 pristine 备份重建出的 asar 与手工安装到线上的 asar **SHA256 完全一致**
（`F24882B003814BE33FDEA47E761553DD45EAAB9E7B7856CBCB07A492CEE036FD`）。

---

## 四、平台差异（macOS 还没跑，先记下来）

脚本**已按平台分支**，下面是已写好但只有 Windows 被验证过的部分：

| 环节 | Windows（✅ 已验证） | macOS（⏳ 代码已写，待实测） |
|---|---|---|
| asar 默认路径 | `%LOCALAPPDATA%\Programs\DeepSeek Harness\resources\app.asar` | `~/Applications/DeepSeek Harness.app/Contents/Resources/app.asar` |
| 退出应用 | `taskkill /IM "DeepSeek Harness.exe"`（只杀这一个，绝不 `taskkill /IM node.exe`） | `pkill -f "DeepSeek Harness"` |
| 启动应用 | 直接执行 `<root>\DeepSeek Harness.exe` | `open -a <找到的 .app>`（脚本向上层目录查找 `.app` 结尾的目录） |
| `patch` 命令 | Git for Windows 的 `patch.exe`（或 PATH / `PATCH_BIN`） | 系统自带 BSD `patch`（**与 GNU patch 行为略有差异，需验证 `-R`/`-N` 输出**） |
| 路径分隔符 | `\` | `/`（脚本内部统一用 `path.join`） |

**macOS 上预期会踩的坑（都要真机确认）**：

1. **代码签名**：`.app` 若是签发签名的，改完 asar 后签名失效 → 可能被 Gatekeeper 拒绝启动，
   需要 `codesign --force --deep -s - <app>`（ad-hoc 重签）或按发行方式调整。**Windows 上没有这个问题。**
2. **quarantine 属性**：从网上下载的包带 `com.apple.quarantine`，可能需要 `xattr -dr com.apple.quarantine <app>`。
3. **BSD vs GNU patch**：`--dry-run -R` 判定「已应用」依赖输出里没有 `Unreversed patch detected!`，
   BSD patch 措辞不同的话要改判定逻辑（脚本用 exit code + 输出关键字双判，需实测确认）。
4. **自动更新**：macOS 侧更新覆盖行为可能不同（是否保留 asar、是否重签名）。

> 计划：在 mac 真机跑通后，把实测结论回填到这张表；若两平台流程**基本一致**，
> 就把 `desktop/windows/` 上提为 `desktop/` 共用，仅保留平台分支差异；若差异大，则 `desktop/macos/` 独立维护。

---

## 五、每版更新清单（桌面侧）

完整清单（npm + 桌面 + 配置 + 插件）见仓库根 [`ADAPTING.md`](../ADAPTING.md) 的「新版适配总清单」。
桌面侧就 4 步：

1. `node desktop/windows/apply-desktop-asar-patches.js --dry-run` —— 看 9 个补丁还能不能套、是否已被自动更新冲掉；
2. 有「待应用」→ 正式安装（脚本自动校验 + 备份 + 重启）；
3. 若官方改了目标文件结构 → 修 `patches/**` 里的锚点（**这一步 npm 版和桌面版共用，修一次两边受益**）；
4. 桌面版版本号若变了 → 把它加进脚本顶部的 `SUPPORTED` 数组（否则要用 `--force`）。

配置侧（模型、重试策略、主题）改动，见 [`dsh-provider-config`](https://github.com/chai1110/dsh-provider-config)
的 `desktop/` 目录：桌面 profile 与网页 profile **互相独立，改一边不会影响另一边**。

---

## 六、目录

```
desktop/
├── README.md                                # 本文件：平台状态、教程、平台差异、更新清单
└── windows/
    └── apply-desktop-asar-patches.js        # Windows 实测过的源码（纯 Node，零依赖）
```

补丁文件本身仍在仓库根 `patches/**` —— npm 版与桌面版**共用同一套**，不存在两份。
