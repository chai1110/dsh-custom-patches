# DSH Custom Enhancements
> 📖 [中文版](README.md)


Adds three practical improvements to the [DeepSeek Harness (DSH)](https://github.com/deepseek-ai/deepseek-harness) Web GUI that are not yet provided officially:
**① Composer ↑/↓ key send history**, **② Edit last message and regenerate**, and **③ Automatic retry for failed compaction (context summarization)**.

- Target version: see [**Releases**](https://github.com/chai1110/dsh-custom-patches/releases) — each version maps to a tag; users on older DSH versions should checkout the matching tag
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

### 2. Edit Last Message and Regenerate
- Hover over the **last user message** to see an **✏️ Edit** button
- Click to turn the message into an editable text box (pre-filled with original text)
- After editing, click **"Save & regenerate"**: the new text replaces the original, **discards all AI replies / tool calls after it**, and AI regenerates from the new content
- Earlier messages are preserved as read-only; to rewrite an earlier one, fork a new session at that message
- Editing while the AI is generating is allowed: it aborts the running turn (queued input is kept) and regenerates from the new text
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
| **macOS** | ✅ Native | Built-in `/bin/bash` (**still 3.2.57**) and `patch` are enough; `pgrep` is built-in too. **Both shell scripts were actually run on this machine under bash 3.2** |
| **Linux** | ✅ Native | `patch` built-in; some minimal distros need `sudo apt install patch` |
| **Windows** | ✅ Use the Node installer above | Pure Node — no `patch`/`pgrep`/`cp`/`find`, **no path-separator problems**. If you still use the shell version: Git for Windows supplies `bash`; restart with `taskkill /F /IM node.exe` (`pgrep` does not exist on Windows) |

**Why the Node installer is the first choice on *every* platform** (not just Windows) — it does four things the shell version does not:

1. **Zero fuzz**: `patch` defaults to fuzz=2 and silently tolerates context lines that no longer match; the Node version requires every line to match exactly.
2. **It reports hunk offsets**: `patch -F 0` disables fuzz but **not offset**, and normal output hides offsets anyway. The Node version prints `N hunk(s) matched at a different line than declared` — the key signal for catching upstream drift.
3. **`node --check` after applying**: if the result no longer parses, it rolls back from `.bak` automatically.
4. **It checks "already applied" (in reverse) before applying**: this prevents a pure-insertion patch from being **applied twice** (the shell version had exactly this incident — see "Critical bug: the shell version double-applies pure-insertion patches" in [`ADAPTING.md`](ADAPTING.md)).

**Universal prerequisites** (any platform):
- **Node.js** (with `npm`) installed
- **`@deepseek-ai/dsh`** installed globally via npm; or built from source (see "Source Build (monorepo) Users" below)

> **No CLI tools needed**: The easiest path is to send this repo link (`https://github.com/chai1110/dsh-custom-patches`) to your AI assistant and let it follow the "Quick Start" section to install and configure on your machine — it will handle Windows `taskkill` differences automatically.

---

## 🚀 Quick Start (all platforms)

Four steps total, **HTTPS clone recommended** (no SSH key needed). You can paste this whole block to an AI assistant:

```bash
# 1) Install matching DSH version (skip if already installed and correct version)
npm install -g @deepseek-ai/dsh@next
dsh --version          # confirm it installed

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
> **The shell versions still work**: `bash install-dsh-custom.sh -y` (with version diagnosis + built-in detection) and `bash apply-dsh-patches.sh` (minimal). Both apply the same patch set — pick whichever you prefer; **but the Node version is the recommended entry point** (stricter: it reports hunk offsets, has `node --check` rollback, and prevents double-application).

Then **hard-refresh** the browser page (`Cmd+Shift+R` / `Ctrl+Shift+R`):
- Press **↑** in the composer to recall history
- Hover over the **last user message** to see the **✏️ Edit** button

> You can also send this repo link `https://github.com/chai1110/dsh-custom-patches` directly to your AI assistant and let it follow the "Quick Start" steps to configure on your machine; all commands in this document are directly executable.

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
- **⚠️ The desktop app auto-updates**: an update overwrites `app.asar` and the patches are gone — rerun the script,
  or use `bash check-update.sh` to detect it.
- **Rollback**: rename `resources/app.asar.bak-<timestamp>` back to `app.asar`.
- **Port**: the desktop host no longer uses a fixed port (older builds hard-coded `19387`); it is now allocated
  dynamically, so any script that probes a fixed port or pulls the token from it will break.
- **Shares the `~/.dsh` root** (credentials, sessions) with the npm version, but plugin config is **per profile**:
  the desktop default profile is `~/.dsh/profiles/desktop`, so settings cannot be copied verbatim from the web
  profile (see `dsh-provider-config`).

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
- **Skips npm version validation** (source has no semver string), but please ensure your source checkout matches the patch version
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
# 1) Check for new official version (auto-compares local / latest / targeted; can specify version: bash check-update.sh <version>)
bash check-update.sh

# 2) Upgrade official
npm install -g @deepseek-ai/dsh@<new-version>

# 3) Re-apply (includes built-in detection; succeeds directly if official didn't change much)
bash install-dsh-custom.sh -y
```

- **Did official already bundle our features?** The one-click script auto-detects and skips built-in patches; you can also manually confirm using the grep method in [`versions.md`](versions.md).
- **Patches broke?** Follow [`ADAPTING.md`](ADAPTING.md) to re-adapt and append a new version row in `versions.md`.
- **Desktop patches overwritten?** The desktop app uses **nightly auto-update**, so an official update wipes them.
  `bash check-update.sh` compares the recorded **source fingerprint** and re-checks the feature markers, and tells
  you whether to re-run `bash desktop/macos/dsh-desktop-patch.sh`.
- **Want to confirm both surfaces are alive at once?** `bash patch-all.sh --check` — verify only, modifies nothing;
  exit code 0 means both are fully green.

> ⚠️ If `patch` errors after upgrade, the new version changed the relevant code — re-adapt per `ADAPTING.md`.

---

## 🤝 Contributing & Feedback

Small project — **there is no separate contributing guide**. Just open an [Issue](https://github.com/chai1110/dsh-custom-patches/issues) or send a PR.

- **Reporting a problem**: include the symptom, your environment (`dsh --version` / OS / Node version), reproduction steps, and the expected result; the `patch` output (`Hunk #N failed`) helps most.
- **Pull requests**: new feature patches and adaptation fixes are welcome. Only four hard rules — ① **keep patches minimal** (change only what's necessary); ② leave a greppable **feature marker**; ③ **keep all three `FILES` tables in sync**: `tools/dsh-patch.mjs`, `install-dsh-custom.sh`, and `apply-dsh-patches.sh` (the Node one is the recommended entry point; the other two are the shell versions — their fields differ, so don't update just one); ④ **update `tools/patch-markers.tsv`** — the single source of truth for feature markers, read by `patch-all.sh`, `desktop/macos/dsh-desktop-patch.sh`, and `check-update.sh`. Iron rule for picking a marker: it must have **zero** occurrences in the official build (counter-example: `surfaceOp: "append"` already appears 8 times upstream and cannot discriminate).
- **Desktop-related changes**: see [`desktop/README.en.md`](desktop/README.en.md) and
  [`desktop/windows/README.md`](desktop/windows/README.md) (Windows contribution checklist).
- **Doc changes**: always refer to the main entry point as `node tools/dsh-patch.mjs` (the shell versions are alternatives — note that when mentioning them); examples must run directly after a fresh clone.
- **After editing a patch body**: run `node tools/dsh-patch.mjs --dry-run` once and confirm there is no
  `N hunk(s) matched at a different line than declared` — ideally it should be **0**
  (see the `-F 0` vs. offset correction in [`ADAPTING.md`](ADAPTING.md)).
- The full re-adaptation workflow lives in [`ADAPTING.md`](ADAPTING.md).

---

## 📄 License

MIT — see [LICENSE](LICENSE).

## 📎 Related Resources

- SSH multi-machine parallel plugin: [chai1110/dsh-ssh-remote](https://github.com/chai1110/dsh-ssh-remote)
- Provider config templates: [chai1110/dsh-provider-config](https://github.com/chai1110/dsh-provider-config)
- DeepSeek Harness (official): [deepseek-ai/deepseek-harness](https://github.com/deepseek-ai/deepseek-harness)
