# DSH Custom Enhancements
> 📖 [中文版](README.md)


Adds three practical features to the [DeepSeek Harness (DSH)](https://github.com/deepseek-ai/deepseek-harness) Web GUI that are not yet provided officially:
**① Composer ↑/↓ key send history**, **② Edit last message and regenerate (Codex-style)**, and **③ Archived session recovery**.

- Target version: **`@deepseek-ai/dsh@0.1.7-rc.2`** (official latest; versions are managed by git tags — users on other DSH versions should checkout the matching tag, see "Multiple Version Support")
- License: **MIT** (see [LICENSE](LICENSE))
- Maintainer: chai1110 (<chai011379@gmail.com>)

> **What this is / isn't**: This is a set of **compiled-artifact patches**, not an official plugin, not a source fork.
> It uses `diff`/`patch` to directly modify DSH's installed npm package files (compiled JS in `node_modules`),
> adding three features that DSH doesn't have yet. **Any npm reinstall / DSH upgrade will overwrite these patches — re-apply after each upgrade.**

---

## 📌 Current support scope (which docs are "latest")

**Target version of this repo's `main` branch: `@deepseek-ai/dsh@0.1.7-rc.2` (official `latest`).**

⚠️ This is a **multi-version repo**, and **not every document has been rewritten alongside the latest version**.
The table below states each file's actual status — judge reliability by the "Status" column,
and **do not assume every doc is up to date**.

| File | Status | Notes |
|---|---|---|
| `install-dsh-custom.sh` | ✅ Adapted to 0.1.7-rc.2 | Main installer; `TARGET_VERSION=0.1.7-rc.2`, 11 patches |
| `apply-dsh-patches.sh` | ✅ Adapted to 0.1.7-rc.2 | Alternative installer (no version diagnosis / no built-in detection) |
| `check-update.sh` | ✅ Adapted to 0.1.7-rc.2 | Checks whether official has a newer version |
| `patches/**` | ✅ Re-adapted | 12 → 11 items; `client-connection` retired because official now bundles it |
| `README.md` / `README.en.md` | ✅ Adapted to 0.1.7-rc.2 | This file |
| `versions.md` | ✅ Adapted to 0.1.7-rc.2 | Version tracking table |
| `ADAPTING.md` | ✅ Includes the 0.1.7-rc.2 record | Also keeps historical records (`0.1.2-alpha.2` pre-study / `0.1.2-rc.1` / `0.1.5-rc.1`) — **intentionally preserved as archive** |
| `CONTRIBUTING.md` | ✅ Adapted to 0.1.7-rc.2 | Contribution flow |
| `POSTMORTEM.md` | 🕘 Historical (2026-08-19, rc.8 era) | Incident postmortem; **not updated for newer versions, and it doesn't need to be** |
| `SECURITY.md` / `CODE_OF_CONDUCT.md` | ➖ Version-independent | Generic statements |

**Not supported**: the official **alpha pre-release line** (e.g. `0.1.2-alpha.2`) is **not adapted** — only pre-studied (see `ADAPTING.md`).
This repo only commits to the versions marked 「✅」 above.

> "Adapted" here means: **the patches apply cleanly on that version and pass validation**.
> It does **not** mean every document in this repo has been rewritten — the table above exists precisely to draw that distinction.

---

## ✨ Features

### 1. Composer Arrow-Up/Down History (terminal-like)
- Press **↑** in the composer to recall the last sent message; keep pressing ↑ to go further back; **↓** to go forward
- History position auto-resets when editing input text
- Compatible with Chinese IME (no accidental trigger during pinyin composition), multi-line text (trigger only at first/last line), and consecutive duplicate dedup

### 2. Edit Last Message and Regenerate (Codex-style)
- Hover over the **last user message** to see an **✏️ Edit** button
- Click to turn the message into an editable text box (pre-filled with original text)
- After editing, click **"Save & regenerate"**: the new text replaces the original, **discards all AI replies / tool calls after it**, and AI regenerates from the new content
- Earlier messages are preserved as read-only; editing is blocked while AI is working (conflict prevention)
- Click **Cancel** to restore original

**How it works**: Editing uses DSH session layer's **surface replace** (append-only log + shadow replacement) — history is preserved, but the model and UI only see the replaced sequence.

### 3. Archived Session Recovery
- DSH officially supports archiving sessions (hide from sidebar), but **provides no UI to view or restore them** — archived sessions are "visible nowhere"
- This patch adds an **"Archived Sessions"** section in **Settings** (below "Right Panel Workspace")
- Lists all archived sessions with their titles
- Click a session title to open it
- Click **"Restore"** to unarchive — the session reappears in the sidebar session list
- Works by adding `unarchiveSession` API end-to-end: host workspace registry → apiproxy route + schema → client runtime + connection RPC → settings UI

---

## ⚠️ Platform & Prerequisites

The install script is written in **bash** and depends on **Unix command-line tools**:

| Platform | Supported | Notes |
|---|---|---|
| **macOS** | ✅ Native | Built-in `bash`/`patch` (`pgrep` also built-in) |
| **Linux** | ✅ Native | `patch` built-in; some minimal distros need `sudo apt install patch` |
| **Windows** | ✅ After Git for Windows | **Git for Windows includes** `bash`, `diff`, `patch`, and `git`. The only `pgrep` usage is in the restart command; Windows uses `taskkill` instead (see below). The install scripts now locate DSH via `npm root -g` first (cross-platform), then fall back to common global dirs including `%APPDATA%\npm` — no `NODE_PATH` needed |

**Universal prerequisites** (any platform):
- **Node.js** (with `npm`) installed
- **`@deepseek-ai/dsh`** installed globally via npm (this repo's main targets `0.1.7-rc.2`; users on other versions checkout the matching tag, see "Multiple Version Support" below); or built from source (see "Source Build (monorepo) Users" below)

> **No CLI tools needed**: The easiest path is to send this repo link (`https://github.com/chai1110/dsh-custom-patches`) to your AI assistant and let it follow the "Quick Start" section to install and configure on your machine — it will handle Windows `taskkill` differences automatically.

---

## 🚀 Quick Start (all platforms)

Four steps total, **HTTPS clone recommended** (no SSH key needed). You can paste this whole block to an AI assistant:

```bash
# 1) Install matching DSH version (skip if already installed and correct version)
npm install -g @deepseek-ai/dsh@0.1.7-rc.2
dsh --version          # should output 0.1.7-rc.2

# 2) Clone this repo (HTTPS, works for everyone)
git clone https://github.com/chai1110/dsh-custom-patches.git
cd dsh-custom-patches

# 3) One-click install (-y skips interactive confirm; script auto-locates DSH, validates version, detects built-ins, backs up, and applies)
bash install-dsh-custom.sh -y

# 4) Restart DSH (macOS / Linux)
kill $(pgrep -f 'dsh web') 2>/dev/null && sleep 1; dsh web
```

> **Windows restart**: replace step 4 with `taskkill //F //IM node.exe` (or kill the node process) then `dsh web`. `pgrep` is only used in the restart command.
> **Source build (monorepo) users**: replace step 3 with `DSH_SOURCE=/path/to/deepseek-harness bash install-dsh-custom.sh -y`, then rebuild/restart your dev server (see "Source Build (monorepo) Users" below).

Then **hard-refresh** the browser page (`Cmd+Shift+R` / `Ctrl+Shift+R`):
- Press **↑** in the composer to recall history
- Hover over the **last user message** to see the **✏️ Edit** button

> You can also send this repo link `https://github.com/chai1110/dsh-custom-patches` directly to your AI assistant and let it follow the "Quick Start" steps to configure on your machine; all commands in this document are directly executable.

---

## 🧩 Multiple Version Support (users on any DSH version can use this)

**Different users may run different DSH versions — this project keeps standalone patches per supported version, so older-version users get the same features WITHOUT upgrading DSH.**

| Your DSH Version | Support | One-click Command |
|---|---|---|
| **0.1.7-rc.2** (latest) | `v0.1.7-rc.2` (default main) | `git clone` then `bash install-dsh-custom.sh -y` |
| 0.1.5-rc.1 | `v0.1.5-rc.1` | `git checkout v0.1.5-rc.1` then `bash install-dsh-custom.sh -y` |
| 0.1.2-rc.1 | `v0.1.2-rc.1` | `git checkout v0.1.2-rc.1` then `bash install-dsh-custom.sh -y` |
| 0.1.1-rc.2 | `v0.1.1-rc.2` | `git checkout v0.1.1-rc.2` then `bash install-dsh-custom.sh -y` |
| 0.1.0-rc.8 | `v0.1.0-rc.8` | `git checkout v0.1.0-rc.8` then `bash install-dsh-custom.sh -y` |
| 0.1.0-rc.7 | `v0.1.0-rc.7` | `git checkout v0.1.0-rc.7` then `bash install-dsh-custom.sh -y` |
| 0.1.0-rc.6 and earlier | ❌ | No standalone patches (repo started publishing at rc.7); please upgrade DSH first |

> **Why tags instead of arguments?** Each DSH version needs different patches (0.1.2-rc.1 is an architecture rewrite).
> Tags bundle patches + install script into one version-specific snapshot — clean and hard to get wrong.
> After checkout, the script validates your local DSH version against the tag and aborts with a clear hint if they differ.

---

## 🛠 Step-by-Step Details

### Step 1: Confirm DSH Version
```bash
npm install -g @deepseek-ai/dsh@0.1.7-rc.2   # install matching version
dsh --version                                 # confirm it's 0.1.7-rc.2
```

### Step 2: Clone the Repo
HTTPS (recommended, works everywhere):
```bash
git clone https://github.com/chai1110/dsh-custom-patches.git
cd dsh-custom-patches
```
SSH (optional, requires GitHub SSH key configured):
```bash
git clone git@github.com:chai1110/dsh-custom-patches.git
cd dsh-custom-patches
```

### Step 3: Run the Install Script
Recommended: the **one-click script** with version diagnosis and built-in detection:
```bash
bash install-dsh-custom.sh -y
```
The script will automatically:
1. Locate DSH install dir (probes both system-level and user-level global paths)
2. Read local version and query npm for latest, giving a version diagnosis
3. **Validate version** (main expects `0.1.7-rc.2`; mismatch aborts and tells you to checkout the correct tag)
4. **Detect if official already has the feature** — if the target file already contains feature markers (e.g. official bundled them), automatically skip that patch
5. For patches that need applying: **backup each file (`.bak`) and apply**
6. Summary report + restart hint

> Alternative: `bash apply-dsh-patches.sh` (same functionality, but no version diagnosis or built-in detection; both apply the same patch set). Older version users should checkout the matching tag (this script takes no version argument).

### Step 4: Restart DSH
```bash
kill $(pgrep -f 'dsh web') 2>/dev/null; sleep 1; dsh web
```

### Step 5: Verify (confirm installation success)
After refreshing the page, check these **observable signals** — all met means success:
- [x] Pressing **↑** in the composer recalls the previous message
- [x] Hovering over the **last user message** shows the **✏️ Edit** button
- [x] Clicking edit → changing content → "Save & regenerate" replaces and regenerates

> Self-diagnosis via script: run `bash install-dsh-custom.sh -y` again; if it outputs *"All features already present (built-in or applied). Nothing to do."* then all features are in place.

---

## 🧩 Source Build (monorepo) Users

If you don't use `npm install -g` for DSH but instead **cloned the source** (e.g. official [deepseek-harness](https://github.com/deepseek-ai/deepseek-harness) pnpm monorepo, built with `pnpm` + `tsdown`, and serve packages directly), you can still apply these patches — **patches are fully portable**, only target file paths differ, and the script supports this layout.

### Step 1: Confirm Two Things
- You have the **DSH source repo root** (a directory containing `packages/` and `pnpm-workspace.yaml`), e.g. `/path/to/deepseek-harness`
- Each plugin package has been **built** (produced `lib/` artifacts; if only `src/` exists, there's nothing to patch)

### Step 2: Set `DSH_SOURCE` and Run the One-click Script
```bash
export DSH_SOURCE=/path/to/deepseek-harness          # point to source repo root
bash install-dsh-custom.sh -y
```
When the script detects `DSH_SOURCE`, it automatically switches to source layout:
- Locates target files under `<DSH_SOURCE>/packages/**/lib/`, backs up, and applies
- **Skips npm version validation** (source doesn't have `0.1.7-rc.2` version strings), but please ensure your source checkout matches the latest rc.2-era code
- After applying, **rebuild/restart your DSH dev server** (same as your usual restart flow), then hard-refresh the browser

### Source Layout Target File Mapping
How the current patch set (11 items) maps between the two layouts:

| Patch target (npm layout) | Source layout path |
|---|---|
| `dsh-api-session-controller/lib/index.js` | `packages/api/session-controller/lib/index.js` |
| `dsh-api-session-controller/lib/client.js` | `packages/api/session-controller/lib/client.js` |
| `dsh-api-session-controller/lib/typert.host.js` | `packages/api/session-controller/lib/typert.host.js` |
| `dsh-api-session-controller/lib/typert.remote-client.js` | `packages/api/session-controller/lib/typert.remote-client.js` |
| `dsh-api-remotes/lib/client.js` | `packages/api/remotes/lib/client.js` |
| `dsh-agent-loop/lib/index.js` | `packages/core/agent-loop/lib/index.js` |
| `dsh-workspace/lib/index.js` | `packages/core/workspace/lib/index.js` |
| `dsh-compaction-basic/lib/index.js` | `packages/core/compaction-basic/lib/index.js` |
| `dsh-client-ui-conversation/lib/client.js` | `packages/client/ui-conversation/lib/client.js` |
| `dsh-client-ui-chat/lib/client.js` | `packages/client/ui-chat/lib/client.js` |
| `dsh-client-ui-workspace/lib/client.js` | `packages/client/ui-workspace/lib/client.js` |

> In other words: a patch path like `dsh-xxx/lib/file.js` maps to `<DSH_SOURCE>/packages/<corresponding-dir>/lib/file.js` in source layout — same content, different root. That's why source-build users can use the exact same patch set.
> The table above is the mapping between fields 1 and 4 of the script's `FILES` array; when the patch set changes, the script is authoritative.

### How to Restore (source layout)
```bash
# run from the repo directory; the list is taken from field 4 of the script's FILES, so it always matches the current patch set
for e in $(sed -n '/^FILES=(/,/^)/p' install-dsh-custom.sh | grep '^  "' | sed 's/.*|\([^|]*\)"$/\1/'); do
  [ -f "$DSH_SOURCE/packages/$e.bak" ] && cp "$DSH_SOURCE/packages/$e.bak" "$DSH_SOURCE/packages/$e" && echo "restored $e"
done
```

> For more source-layout details or how to re-adapt a broken patch, see [ADAPTING.md](ADAPTING.md).

---

## ↩️ How to Restore Original (uninstall patches)

The install script backs up each modified file as `.bak`. To restore, copy those backups back (path is dynamically obtained via `npm root -g`, works with any global install layout; **the file list is derived from the script's `FILES`, so it always matches the current patch set**):

```bash
# run from the repo directory
PLUGIN="$(npm root -g)/@deepseek-ai/dsh/node_modules/@deepseek-ai"
for e in $(grep -oE '"dsh-[a-z-]+/lib/[a-z.-]+\.js' install-dsh-custom.sh | tr -d '"'); do
  [ -f "$PLUGIN/$e.bak" ] && cp "$PLUGIN/$e.bak" "$PLUGIN/$e" && echo "restored $e"
done
```

---

## 🔄 Keeping Up with Official Updates

Official upgrades overwrite these patches (because they modify `node_modules` compiled artifacts). Recommended workflow:

```bash
# 1) Check for new official version (auto-compares local/latest/targeted; can specify version: bash check-update.sh 0.1.0-rc.8)
bash check-update.sh

# 2) Upgrade official
npm install -g @deepseek-ai/dsh@<new-version>

# 3) Re-apply (includes built-in detection; succeeds directly if official didn't change much)
bash install-dsh-custom.sh -y
```

- **Did official already bundle our features?** The one-click script auto-detects and skips built-in patches; you can also manually confirm using the grep method in [`versions.md`](versions.md).
- **Patches broke?** Follow [`ADAPTING.md`](ADAPTING.md) to re-adapt and append a new version row in `versions.md`.

> ⚠️ If `patch` errors after upgrade, the new version changed the relevant code — re-adapt per `ADAPTING.md`.

---

## 📦 Project Structure

```
dsh-custom-patches/
├── install-dsh-custom.sh   # One-click install (recommended)
├── apply-dsh-patches.sh    # Alternative install (no version diagnosis/built-in detection)
├── check-update.sh         # Check if official has a new version
├── versions.md             # Version tracking table
├── ADAPTING.md             # How to adapt to new official versions
├── patches/                # Patch files (organized by package)
└── LICENSE                 # MIT
```

---

## 📄 License

MIT — see [LICENSE](LICENSE).

## 📎 Related Resources

- SSH 多机并行插件: [chai1110/dsh-ssh-remote](https://github.com/chai1110/dsh-ssh-remote)
- 供应商配置模板: [chai1110/dsh-provider-config](https://github.com/chai1110/dsh-provider-config)
- DeepSeek Harness 官方: [deepseek-ai/deepseek-harness](https://github.com/deepseek-ai/deepseek-harness)
