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

## ⚠️ Prerequisites

- **Node.js** (18+) — only to run the patch script; the desktop app itself does not need it
- **`patch`** command — ships with Git for Windows; or point `PATCH_BIN` at it
- **DeepSeek Harness desktop app** installed

> The script auto-detects the asar: Windows `%LOCALAPPDATA%\Programs\DeepSeek Harness\resources\app.asar`,
> macOS `/Applications/DeepSeek Harness.app/Contents/Resources/app.asar`, Linux `/opt/DeepSeek Harness/resources/app.asar`.
> Elsewhere, pass `--asar <path>` (or set `DSH_DESKTOP_ASAR`).

---

## 🚀 Quick Start

**This repo targets the desktop (Electron) app only.** CLI / web / VS Code are no longer supported — those scripts were retired on 2026-10-30; checkout an older tag if you need them.

```bash
# 1) Clone
git clone https://github.com/chai1110/dsh-custom-patches.git
cd dsh-custom-patches

# 2) Dry run: check the patches still apply, touch nothing
node desktop/windows/apply-desktop-asar-patches.js --dry-run

# 3) Install: quit the app -> back up app.asar -> patch -> verify -> swap -> relaunch
node desktop/windows/apply-desktop-asar-patches.js
```

After installing, open the app and check three things:

- Pressing **↑** in the composer recalls the previous message
- Hovering the **last** user message shows an **✏️ Edit** button
- "Compaction retry" has **no UI signal** (it only kicks in on rate limits / network errors); look for `llm/retry` in the session log

**What the script does**: locate `app.asar` → list patches → reverse-dry-run to detect "already applied" (idempotent) → back up → apply → rebuild asar → full verify (every non-target file byte-identical + feature markers present) → swap. If any check fails, the original file is left untouched.

> You can also hand this repo link to your AI assistant and let it follow this section.

---

## 🔧 Notes

- **Generate without swapping**: `node desktop/windows/apply-desktop-asar-patches.js --out new.asar` writes the patched asar to a path of your choice; the running app is untouched.
- **Idempotent**: reruns detect "already applied" and skip — never double-applies.
- **Port**: the desktop host no longer uses a fixed port (older builds hard-coded `19387`); it is allocated dynamically now, so scripts that probe a fixed port will break.
- **Per-profile config**: the desktop app shares the `~/.dsh` root (credentials, sessions) with npm, but plugin config is per profile — desktop uses `~/.dsh/profiles/desktop` (see `dsh-provider-config`).
- **macOS**: `desktop/macos/dsh-desktop-patch.sh` is a separate branch (different signing flow) — see [`desktop/README.md`](desktop/README.md).

---

## ↩️ How to Restore Original

Patching creates `app.asar.bak-<timestamp>` next to the asar. Renaming it back restores the stock build:

```bash
cd "$LOCALAPPDATA/Programs/DeepSeek Harness/resources"
mv app.asar.bak-20261030060331. app.asar    # use your own timestamp
```

---

## 🔄 After an Official Update

**The desktop app auto-updates on a nightly channel, and every update overwrites `app.asar` — the patches are gone.** That is expected, not a failure.

```bash
cd dsh-custom-patches
git pull
node desktop/windows/apply-desktop-asar-patches.js --dry-run   # confirm they still apply
node desktop/windows/apply-desktop-asar-patches.js             # re-apply
```

- **`--dry-run` says "version not in supported list"**: upstream touched the anchor regions — re-adapt via [`ADAPTING.md`](ADAPTING.md) and add a row to `versions.md`.
- **`--dry-run` passes and only reports "pending"**: zero-change compatible — just run the installer.
- **Wondering whether upstream built these features in?** `versions.md` has a grep recipe; if the markers already exist, that patch can retire.

> ⚠️ The updater also **deletes the backups** (`app.asar.bak-*` vanishes), so every re-patch must regenerate one — do not count on an old rollback point.

---

## 🤝 Contributing & Feedback

Small project, **no separate contributing guide** — open an [Issue](https://github.com/chai1110/dsh-custom-patches/issues) or send a PR.

- **Reporting**: include the symptom, desktop version, OS, repro steps and expected result; a `Hunk #N failed` log helps.
- **PRs**: three hard requirements — ① minimal patch (change only what is needed); ② add a greppable **feature marker**; ③ update `tools/patch-markers.tsv` (the desktop script reads it for verification). Marker rule: **must be 0 hits in the stock build** (counter-example: `surfaceOp: "append"` already appears 8 times).
- **After editing a patch**: run `node desktop/windows/apply-desktop-asar-patches.js --dry-run --force` and confirm all 9 apply without failed hunks.
- **Full adaptation flow**: [`ADAPTING.md`](ADAPTING.md); desktop details: [`desktop/README.md`](desktop/README.md).

---

## 📄 License

MIT — see [LICENSE](LICENSE).

## 📎 Related Resources

- SSH multi-machine parallel plugin: [chai1110/dsh-ssh-remote](https://github.com/chai1110/dsh-ssh-remote)
- Provider config templates: [chai1110/dsh-provider-config](https://github.com/chai1110/dsh-provider-config)
- DeepSeek Harness (official): [deepseek-ai/deepseek-harness](https://github.com/deepseek-ai/deepseek-harness)
