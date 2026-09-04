# DSH Custom Enhancements
> 📖 [中文版](README.md)


Adds three practical features to the [DeepSeek Harness (DSH)](https://github.com/deepseek-ai/deepseek-harness) Web GUI that are not yet provided officially:
**① Composer ↑/↓ key send history**, **② Edit last message and regenerate (Codex-style)**, and **③ Archived session recovery**.

- Target version: **`@deepseek-ai/dsh@0.1.2-rc.1`** (versions are managed by git tags — users on other DSH versions should checkout the matching tag, see "Multiple Version Support")
- License: **MIT** (see [LICENSE](LICENSE))
- Maintainer: chai1110 (<chai011379@gmail.com>)

> **What this is / isn't**: This is a set of **compiled-artifact patches**, not an official plugin, not a source fork.
> It uses `diff`/`patch` to directly modify DSH's installed npm package files (compiled JS in `node_modules`),
> adding three features that DSH doesn't have yet. **Any npm reinstall / DSH upgrade will overwrite these patches — re-apply after each upgrade.**

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
- **`@deepseek-ai/dsh`** installed globally via npm (this repo's main targets `0.1.2-rc.1`; users on other versions checkout the matching tag, see "Multiple Version Support" below); or built from source (see "Source Build (monorepo) Users" below)

> **No CLI tools needed**: The easiest path is to send this repo link (`https://github.com/chai1110/dsh-custom-patches`) to your AI assistant and let it follow the "Quick Start" section to install and configure on your machine — it will handle Windows `taskkill` differences automatically.

---

## 🚀 Quick Start (all platforms)

Four steps total, **HTTPS clone recommended** (no SSH key needed). You can paste this whole block to an AI assistant:

```bash
# 1) Install matching DSH version (skip if already installed and correct version)
npm install -g @deepseek-ai/dsh@0.1.2-rc.1
dsh --version          # should output 0.1.2-rc.1

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
| **0.1.2-rc.1** (latest) | `v0.1.2-rc.1` (default main) | `git clone` then `bash install-dsh-custom.sh -y` |
| **0.1.1-rc.2** | `v0.1.1-rc.2` | `git checkout v0.1.1-rc.2` then `bash install-dsh-custom.sh -y` |
| **0.1.0-rc.8** | `v0.1.0-rc.8` | `git checkout v0.1.0-rc.8` then `bash install-dsh-custom.sh -y` |
| **0.1.0-rc.7** | `v0.1.0-rc.7` | `git checkout v0.1.0-rc.7` then `bash install-dsh-custom.sh -y` |
| 0.1.0-rc.6 and earlier | ❌ | No standalone patches (repo started publishing at rc.7); please upgrade DSH first |

> **Why tags instead of arguments?** Each DSH version needs different patches (0.1.2-rc.1 is an architecture rewrite).
> Tags bundle patches + install script into one version-specific snapshot — clean and hard to get wrong.
> After checkout, the script validates your local DSH version against the tag and aborts with a clear hint if they differ.

---

## 🛠 Step-by-Step Details

### Step 1: Confirm DSH Version
```bash
npm install -g @deepseek-ai/dsh@0.1.2-rc.1   # install matching version (older users install their own)
dsh --version                                 # confirm it's 0.1.2-rc.1
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
3. **Validate version** (main expects `0.1.2-rc.1`; mismatch aborts and tells you to checkout the correct tag)
4. **Detect if official already has the feature** — if the target file already contains feature markers (e.g. official bundled them), automatically skip that patch
5. For patches that need applying: **backup each file (`.bak`) and apply**
6. Summary report + restart hint

> Alternative: `bash apply-dsh-patches.sh` (same functionality, but no version diagnosis or built-in detection; both apply the same patch set). Older version users also add version arg: `bash apply-dsh-patches.sh 0.1.0-rc.8`.

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
- **Skips npm version validation** (source doesn't have `0.1.2-rc.1` version strings), but please ensure your source checkout matches the latest rc.1-era code
- After applying, **rebuild/restart your DSH dev server** (same as your usual restart flow), then hard-refresh the browser

### Source Layout Target File Mapping
| npm Package | Source Package Dir | Patch Target File (built) |
|---|---|---|
| `@deepseek-ai/dsh-host-apiproxy` | `packages/host/apiproxy` | `lib/index.js` |
| `@deepseek-ai/dsh-agent-loop` | `packages/core/agent-loop` | `lib/index.js` |
| `@deepseek-ai/dsh-client-connection` | `packages/client/connection` | `lib/client.js` |
| `@deepseek-ai/dsh-client-runtime` | `packages/client/runtime` | `lib/client.js` |
| `@deepseek-ai/dsh-client-ui-conversation` | `packages/client/ui-conversation` | `lib/client.js` |

> In other words: a patch path like `dsh-xxx/lib/file.js` maps to `<DSH_SOURCE>/packages/<corresponding-dir>/lib/file.js` in source layout — same content, different root. That's why source-build users can use the exact same patch set.

### How to Restore (source layout)
```bash
for e in \
  host/apiproxy/lib/index.js \
  core/agent-loop/lib/index.js \
  client/connection/lib/client.js \
  client/runtime/lib/client.js \
  client/ui-conversation/lib/client.js; do
  cp "$DSH_SOURCE/packages/$e.bak" "$DSH_SOURCE/packages/$e"
done
```

> For more source-layout details or how to re-adapt a broken patch, see [ADAPTING.md](ADAPTING.md).

---

## ↩️ How to Restore Original (uninstall patches)

The install script backs up each modified file as `.bak`. To restore, copy those backups back (path is dynamically obtained via `npm root -g`, works with any global install layout):

```bash
PLUGIN="$(npm root -g)/@deepseek-ai/dsh/node_modules/@deepseek-ai"
for e in \
  dsh-host-apiproxy/lib/index.js \
  dsh-agent-loop/lib/index.js \
  dsh-client-connection/lib/client.js \
  dsh-client-runtime/lib/client.js \
  dsh-client-ui-conversation/lib/client.js; do
  cp "$PLUGIN/$e.bak" "$PLUGIN/$e"
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
├── apply-dsh-patches.sh    # Basic install (supports older version args)
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
