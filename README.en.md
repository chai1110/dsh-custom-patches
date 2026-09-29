# DSH Custom Enhancements
> 📖 [中文版](README.md)


Adds three practical improvements to the [DeepSeek Harness (DSH)](https://github.com/deepseek-ai/deepseek-harness) Web GUI that are not yet provided officially:
**① Composer ↑/↓ key send history**, **② Edit last message and regenerate**, and **③ Automatic retry for failed compaction (context summarization)**.

- Target version: **`@deepseek-ai/dsh@0.2.0-rc.1`** (official `next`; versions are managed by git tags — users on other DSH versions should checkout the matching tag, see "Multiple Version Support")
- License: **MIT** (see [LICENSE](LICENSE))
- Maintainer: chai1110 (<chai011379@gmail.com>)

> **What this is / isn't**: This is a set of **compiled-artifact patches**, not an official plugin, not a source fork.
> It uses `diff`/`patch` to directly modify DSH's installed npm package files (compiled JS in `node_modules`),
> adding three features that DSH doesn't have yet. **Any npm reinstall / DSH upgrade will overwrite these patches — re-apply after each upgrade.**

---

## 📌 Current support scope (which docs are "latest")

**Target version of this repo's `main` branch: `@deepseek-ai/dsh@0.2.0-rc.1` (official `next` channel).**

> ⚠️ `0.2.0-rc.1` is on the official **`next`** channel — **`latest` is still `0.1.7-rc.2`**.
> A plain `npm install -g @deepseek-ai/dsh` gives you `0.1.7-rc.2`; in that case **checkout `v0.1.7-rc.2`**,
> or install the new version explicitly: `npm install -g @deepseek-ai/dsh@0.2.0-rc.1`.

⚠️ This is a **multi-version repo**, and **not every document has been rewritten alongside the latest version**.
The table below states each file's actual status — judge reliability by the "Status" column,
and **do not assume every doc is up to date**.

| File | Status | Notes |
|---|---|---|
| `tools/dsh-patch.mjs` | ✅ Adapted to 0.2.0-rc.1 | **Recommended installer (all platforms)**; dependency-free Node — no `patch`/`cp`/`find`/`pgrep`, exact (zero-fuzz) matching + `node --check` validation + auto-rollback |
| `install-dsh-custom.sh` | ✅ Adapted to 0.2.0-rc.1 | shell-based main installer; `TARGET_VERSION=0.2.0-rc.1`, 9 patches |
| `apply-dsh-patches.sh` | ✅ Adapted to 0.2.0-rc.1 | shell-based alternative installer (no version diagnosis / no built-in detection) |
| `desktop/windows/apply-desktop-asar-patches.js` | ✅ Verified on 0.2.0-rc.1 / 0.2.0-rc.2 | **Desktop (Electron) installer**: rewrites `resources/app.asar`, reverse dry-run for idempotency + full byte-for-byte verification — see "🖥️ Desktop App Support" below |
| `check-update.sh` | ✅ Adapted to 0.2.0-rc.1 | Checks whether official has a newer version |
| `patches/**` | ✅ Re-adapted | 11 → 9 items; all archive-related patches (`client-connection` / `workspace` / `client-ui-workspace`) **retired** — official now ships the complete chain (archive + unarchive + sidebar filter + inline restore + search restore). Against the previous release `v0.1.5-rc.1` (12 items) it is **12 → 9** (`client-connection` was retired early in the 0.1.7-rc.2 adaptation, 12→11; `workspace` + `client-ui-workspace` were retired on 2026-09-28, 11→9) |
| `README.md` / `README.en.md` | ✅ Adapted to 0.2.0-rc.1 | This file |
| `versions.md` | ✅ Adapted to 0.2.0-rc.1 | Version tracking table |
| `ADAPTING.md` | ✅ Includes the 0.2.0-rc.1 record | Also keeps historical records (`0.1.2-alpha.2` pre-study / `0.1.2-rc.1` / `0.1.5-rc.1`) — **intentionally preserved as archive** |
| `POSTMORTEM.md` | 🕘 Historical (2026-08-19, rc.8 era) | Incident postmortem; **not updated for newer versions, and it doesn't need to be** |
| `docs/SSH-REMOTE.md` | 🕘 Pointer only | The SSH plugin itself lives in the separate repo [dsh-ssh-remote](https://github.com/chai1110/dsh-ssh-remote); **maintenance is paused and it no longer follows 0.1.5+** |
| `SECURITY.md` | ➖ Version-independent | How to report vulnerabilities |

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

### 2. Edit Last Message and Regenerate
- Hover over the **last user message** to see an **✏️ Edit** button
- Click to turn the message into an editable text box (pre-filled with original text)
- After editing, click **"Save & regenerate"**: the new text replaces the original, **discards all AI replies / tool calls after it**, and AI regenerates from the new content
- Earlier messages are preserved as read-only; editing is blocked while AI is working (conflict prevention)
- Click **Cancel** to restore original

**How it works**: Editing uses DSH session layer's **surface replace** (append-only log + shadow replacement) — history is preserved, but the model and UI only see the replaced sequence.

> ✅ **Fixed 2026-09-29**: previously, after re-sending, the old turn stayed in the transcript — a bug in this very patch.
> The shadow fold read the wrong `surfaceOp` keys (`op.start` / `op.end` instead of `op.startSeq` / `op.endSeq`),
> so the `shadowed` set stayed empty and replaced events were never skipped.
> After the fix the rewrite is immediate: **the old prompt and its reply disappear at once**, leaving only the new turn.

### 3. Automatic Retry for Failed Compaction (Context Summarization)
- When the context is nearly full, DSH auto-"compacts" it — asking the model to summarize the history. But **that compaction LLM call does not go through the official retry mechanism** (`dsh-llm-retry` only hooks the normal conversation request's `agent/request-error`, while compaction calls `ctx.llm.stream()` directly), so a **429 / rate limit fails it outright and the whole compaction is wasted**
- This patch wraps the summarization call in a **retry loop** that reuses the provider's `retryPolicy` (`retryableCodes` / `maxRetries` / `initialDelayMs` / `maxDelayMs` / `jitterRatio` — the same one already configured in `settings.yaml`)
- Backoff is **exponential with jitter**, and is **abortable** — pressing stop will not leave you stuck waiting
- Every retry appends `llm/retry` / `llm/retry-started` events to the session, so you can see it directly in the session log
- In one line: **a network hiccup won't waste an entire compaction**

> This one has **no UI** — it is a "silent" reliability improvement that only kicks in on rate limits or network errors, but you will appreciate it over time.

---

## ⚠️ Platform & Prerequisites

### Recommended: the Node installer (identical on every platform, no separator or tool dependencies)

```bash
node tools/dsh-patch.mjs -y
```

`tools/dsh-patch.mjs` is a **zero-dependency Node script**. Node is already a hard prerequisite for DSH (you installed DSH with npm), so it needs **none** of `patch` / `cp` / `find` / `pgrep`, and every path is built with `path.join` — so **Windows backslash problems cannot occur in the first place**. It also does two things the shell version does not:

- **Zero-fuzz matching**: `patch` defaults to a fuzz factor of 2, silently tolerating context lines that no longer match (i.e. it can "succeed" onto the wrong anchor). This installer requires every context line to match exactly — if upstream moved the code you get a **loud failure** instead of a silent mis-patch.
- **`node --check` validation after applying**: if the result does not parse, it automatically rolls back from the `.bak` copy.

| Platform | Supported | Notes |
|---|---|---|
| **macOS** | ✅ Native | Built-in `bash`/`patch` (`pgrep` also built-in) |
| **Linux** | ✅ Native | `patch` built-in; some minimal distros need `sudo apt install patch` |
| **Windows** | ✅ Use the Node installer above | Pure Node — no `patch`/`pgrep`/`cp`/`find`, **no path-separator problems**. If you still use the shell version: Git for Windows supplies `bash`; restart with `taskkill /F /IM node.exe` (`pgrep` does not exist on Windows) |

**Universal prerequisites** (any platform):
- **Node.js** (with `npm`) installed
- **`@deepseek-ai/dsh`** installed globally via npm (this repo's main targets `0.2.0-rc.1`; users on other DSH versions checkout the matching tag, see "Multiple Version Support" below); or built from source (see "Source Build (monorepo) Users" below)

> **No CLI tools needed**: The easiest path is to send this repo link (`https://github.com/chai1110/dsh-custom-patches`) to your AI assistant and let it follow the "Quick Start" section to install and configure on your machine — it will handle Windows `taskkill` differences automatically.

---

## 🚀 Quick Start (all platforms)

Four steps total, **HTTPS clone recommended** (no SSH key needed). You can paste this whole block to an AI assistant:

```bash
# 1) Install matching DSH version (skip if already installed and correct version)
npm install -g @deepseek-ai/dsh@0.2.0-rc.1
dsh --version          # should output 0.2.0-rc.1

# 2) Clone this repo (HTTPS, works for everyone)
git clone https://github.com/chai1110/dsh-custom-patches.git
cd dsh-custom-patches

# 3) One-click install (-y skips interactive confirm; script auto-locates DSH, validates version, detects built-ins, backs up, and applies)
node tools/dsh-patch.mjs -y

# 4) Restart DSH — macOS / Linux
pkill -f 'dsh web'; dsh web
```

> **Windows restart**: replace step 4 with `taskkill /F /IM node.exe` (or kill the node process) then `dsh web`.
> **Source build (monorepo) users**: replace step 3 with `DSH_SOURCE=/path/to/deepseek-harness node tools/dsh-patch.mjs -y`, then rebuild/restart your dev server (see "Source Build (monorepo) Users" below).
> **The shell version still works**: `bash install-dsh-custom.sh -y` (main installer) and `bash apply-dsh-patches.sh` (alternative). Both apply the same patch set — pick whichever you prefer.

Then **hard-refresh** the browser page (`Cmd+Shift+R` / `Ctrl+Shift+R`):
- Press **↑** in the composer to recall history
- Hover over the **last user message** to see the **✏️ Edit** button

> You can also send this repo link `https://github.com/chai1110/dsh-custom-patches` directly to your AI assistant and let it follow the "Quick Start" steps to configure on your machine; all commands in this document are directly executable.

---

## 🧩 Multiple Version Support (users on any DSH version can use this)

**Different users may run different DSH versions — this project keeps standalone patches per supported version, so older-version users get the same features WITHOUT upgrading DSH.**

| Your DSH Version | Support | One-click Command |
|---|---|---|
| **0.2.0-rc.1** (official `next`) | `v0.2.0-rc.1` (default main) | `git clone` then `bash install-dsh-custom.sh -y` |
| 0.1.7-rc.2 (official `latest`) | `v0.1.7-rc.2` | `git checkout v0.1.7-rc.2` then `bash install-dsh-custom.sh -y` |
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

## 🖥️ Desktop App Support (DeepSeek Harness Desktop)

**The desktop app is an Electron application — it is NOT installed via npm**, so all 9 patch targets live inside
`resources/app.asar`. Use `desktop/windows/apply-desktop-asar-patches.js` (pure Node, no third-party dependencies).
**Full tutorial, platform differences and the macOS plan: [`desktop/README.md`](desktop/README.md)**:

```bash
# 1) Dry-run first: check whether the patches fit, changes nothing
node desktop/windows/apply-desktop-asar-patches.js --dry-run

# 2) Install: quit app -> back up app.asar -> patch -> full verify -> swap -> relaunch
node desktop/windows/apply-desktop-asar-patches.js

# Only produce a new asar at a given path (original untouched; app keeps running)
node desktop/windows/apply-desktop-asar-patches.js --out new.asar
```

- **Requirements**: Node (asar read/write is built into the script) + the `patch` command — on Windows that comes
  with Git for Windows; point `PATCH_BIN` at the executable if it is somewhere else.
- **Auto-detected paths**: Windows `%LOCALAPPDATA%\Programs\DeepSeek Harness\resources\app.asar`,
  macOS `/Applications/DeepSeek Harness.app/Contents/Resources/app.asar`,
  Linux `/opt/DeepSeek Harness/resources/app.asar`; otherwise pass `--asar <path>` (or env `DSH_DESKTOP_ASAR`).
- **Idempotent**: reruns reverse-dry-run each target, skip anything already applied — never double-applies.
- **Every swap is fully verified first**: the new asar must parse, keep the same path order, have **every file
  except the 9 targets byte-identical**, and the targets must contain the feature markers. If any check fails
  the original file is left untouched (and a failure during swap is rolled back).
- **⚠️ The desktop app auto-updates**, which overwrites `app.asar` — rerun the script afterwards
  (`--dry-run` first to confirm).
- **Rollback**: rename `resources/app.asar.bak-<timestamp>` back to `app.asar`.
- **Verified on**: desktop `0.2.0-rc.2` (the same patch set works unchanged on npm `0.2.0-rc.1`;
  `0.2.0-rc.1` is accepted too). The desktop app shares the `~/.dsh` root (credentials, `settings.yaml`,
  sessions) with the npm version, but plugin config is **per profile** — the desktop default profile is
  `~/.dsh/profiles/desktop`, so settings cannot be copied verbatim from the web profile (see `dsh-provider-config`).

---

## 🛠 Step-by-Step Details

### Step 1: Confirm DSH Version
```bash
npm install -g @deepseek-ai/dsh@0.2.0-rc.1   # install matching version
dsh --version                                 # confirm it's 0.2.0-rc.1
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
3. **Validate version** (main expects `0.2.0-rc.1`; mismatch aborts and tells you to checkout the correct tag)
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

> Item 3 (compaction retry) has **no observable UI signal** — it only takes effect in the background on rate limits / network errors, so no manual verification is needed; to confirm it works, look for `llm/retry` events in the session log.

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
- **Skips npm version validation** (source doesn't have `0.2.0-rc.1` version strings), but please ensure your source checkout matches the latest rc-era code
- After applying, **rebuild/restart your DSH dev server** (same as your usual restart flow), then hard-refresh the browser

### Source Layout Target File Mapping
How the current patch set (9 items) maps between the two layouts:

| Patch target (npm layout) | Source layout path |
|---|---|
| `dsh-api-session-controller/lib/index.js` | `packages/api/session-controller/lib/index.js` |
| `dsh-api-session-controller/lib/client.js` | `packages/api/session-controller/lib/client.js` |
| `dsh-api-session-controller/lib/typert.host.js` | `packages/api/session-controller/lib/typert.host.js` |
| `dsh-api-session-controller/lib/typert.remote-client.js` | `packages/api/session-controller/lib/typert.remote-client.js` |
| `dsh-api-remotes/lib/client.js` | `packages/api/remotes/lib/client.js` |
| `dsh-agent-loop/lib/index.js` | `packages/core/agent-loop/lib/index.js` |
| `dsh-compaction-basic/lib/index.js` | `packages/core/compaction-basic/lib/index.js` |
| `dsh-client-ui-conversation/lib/client.js` | `packages/client/ui-conversation/lib/client.js` |
| `dsh-client-ui-chat/lib/client.js` | `packages/client/ui-chat/lib/client.js` |

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
├── install-dsh-custom.sh         # One-click install (recommended)
├── apply-dsh-patches.sh          # Alternative install (no version diagnosis/built-in detection)
├── check-update.sh               # Check if official has a new version
├── tools/dsh-patch.mjs           # Recommended installer (zero-dependency Node)
├── desktop/                      # Desktop (Electron) adaptation
│   ├── README.md                 #   Desktop guide (tutorial / platform differences / update checklist)
│   └── windows/
│       └── apply-desktop-asar-patches.js  #   app.asar installer (verified on Windows, macOS TBD)
├── versions.md                   # Version tracking table
├── ADAPTING.md                   # How to adapt to new official versions
├── patches/                      # Patch files (organized by package)
├── docs/SSH-REMOTE.md            # Pointer to the separate dsh-ssh-remote repo (maintenance paused)
├── POSTMORTEM.md                 # Historical incident postmortem (rc.8 era)
├── SECURITY.md                   # How to report vulnerabilities
└── LICENSE                       # MIT
```

---

## 🤝 Contributing & Feedback

Small project — **there is no separate contributing guide**. Just open an [Issue](https://github.com/chai1110/dsh-custom-patches/issues) or send a PR.

- **Reporting a problem**: include the symptom, your environment (`dsh --version` / OS / Node version), reproduction steps, and the expected result; the `patch` output (`Hunk #N failed`) helps most.
- **Pull requests**: new feature patches and adaptation fixes are welcome. Only three hard rules — ① **keep patches minimal** (change only what's necessary); ② leave a greppable **feature marker**; ③ keep the `FILES` arrays in `install-dsh-custom.sh` and `apply-dsh-patches.sh` in sync.
- **Doc changes**: always refer to the main entry script as `install-dsh-custom.sh` (`apply-dsh-patches.sh` is the alternative — note that when mentioning it); examples must run directly after a fresh clone.
- The full re-adaptation workflow lives in [`ADAPTING.md`](ADAPTING.md).

---

## 📄 License

MIT — see [LICENSE](LICENSE).

## 📎 Related Resources

- SSH multi-machine parallel plugin: [chai1110/dsh-ssh-remote](https://github.com/chai1110/dsh-ssh-remote)
- Provider config templates: [chai1110/dsh-provider-config](https://github.com/chai1110/dsh-provider-config)
- DeepSeek Harness (official): [deepseek-ai/deepseek-harness](https://github.com/deepseek-ai/deepseek-harness)
