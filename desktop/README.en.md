# Desktop (Electron) Adaptation

> 📖 [中文](README.md)

This directory applies this repository's feature patches — **recall the last message**,
**edit the last message and regenerate**, and **automatic retry for failed compaction** —
to the **DeepSeek Harness desktop app** (Electron).

The CLI / browser / VS Code surfaces load dsh from `node_modules` as ordinary npm packages,
so patching them is a plain `patch` run (see `apply-dsh-patches.sh` / `tools/dsh-patch.mjs`
at the repository root). **The desktop app is different** — its dsh runtime is sealed inside a
**code-signed `app.asar`**, which requires actual asar surgery. That is why this directory exists.

---

## 📌 The short version

| Question | Answer |
|---|---|
| Can the desktop app be patched via profile dirs / plugins / env vars? | **No.** Five approaches were tried; all dead ends (below). |
| Then how? | Clone the official app, **replace exactly 9 files inside `app.asar`**, then ad-hoc re-sign. |
| Will the official app get damaged? | **No.** It is never touched — patches land on a separate copy. |
| Do we need new patch files? | **No.** The 9 existing `.patch` files under `patches/**` are reused. |
| Will official updates break it? | **Yes.** The desktop app uses nightly auto-update; re-run this directory's script after each update. |

---

## ⛔ Why `app.asar` surgery is the only route (five dead ends, all empirically tested)

The desktop app seals its runtime under `dsh/` inside `Contents/Resources/app.asar`, and the
install anchor points hard at the asar interior. Every "cleaner" approach was tried:

| Approach | Why it fails |
|---|---|
| **① Shadow core packages via the profile dir**<br>Drop patched packages into `~/.dsh/profiles/*/node_modules/` | `collectProfileScopePackages` passes the **installation names themselves** as `reserved` into `dependencyClosure` — profile-scoped packages can never shadow core packages; the loader ignores them. |
| **② Point the install anchor elsewhere via env var**<br>Set `DSH_DESKTOP_DSH_DIR` to an external dir | The variable is gated on `development = !app.isPackaged`. **In a packaged build `app.isPackaged === true`, so the branch never runs.** |
| **③ Make Electron load an external app dir**<br>Unpack the app and pass the path via argv | In a packaged build `process.defaultApp === false`; the argv path is ignored. |
| **④ Replace the copies in `.asar.unpacked`** | `app.asar.unpacked` holds **only native / platform packages** (`node-pty`, `@img`, `fontkit`, `sherpa-onnx`, `libreoffice-kit`, `@koromix/koffi`). All 9 of our targets live **inside** the asar — there is no unpacked copy to swap. |
| **⑤ A pure client plugin** (`dsh.client`) | `editLastPrompt` / `recallHistory` are **client → server RPCs**. Front-end-only changes do nothing: the host side (`dsh-api-session-controller/lib/index.js`, `dsh-agent-loop`, `dsh-compaction-basic`) must change too, or the request reaches the server with nobody answering. |

> ⚠️ **One trap when debugging this**: if your tool environment already sets
> `ELECTRON_RUN_AS_NODE=1`, the Electron binary starts in **Node mode** and reports
> `Cannot find module 'electron'` — a false positive, not real behaviour. Use
> `env -u ELECTRON_RUN_AS_NODE ...` to observe the actual Electron path.

---

## 🗂 Per-platform layout (macOS and Windows are kept **separate**)

### Why separate

The two platforms' desktop builds **may differ**, and we currently have no evidence that they don't:

1. **Host differences** (definitely different): bundle layout
   (`Contents/Resources/app.asar` vs `resources/app.asar`), signing (macOS must re-sign,
   Windows need not), restart mechanism (`kill -TERM` vs `taskkill`).
2. **Payload differences** (unverified): whether the 9 target files inside `app.asar` are
   **byte-identical** across platforms is **not yet verified**. If the vendor ships different
   code per platform, the same `.patch` may apply with zero fuzz on one side and fail on the other.

Hence:

```
desktop/
├── README.md / README.en.md   ← this file (entry point)
├── dsh-desktop-asar.mjs       ← [SHARED] asar read / surgical rewrite / per-entry verify (pure Node, cross-platform)
├── macos/                     ← macOS module
│   ├── README.md
│   └── dsh-desktop-patch.sh   ← driver: clone → extract → patch → rewrite asar → verify → re-sign
└── windows/                   ← Windows module (to be contributed, see windows/README.md)
    └── README.md
```

### What is already shared

`desktop/dsh-desktop-asar.mjs` is **platform-independent** — the asar container format is
identical on both platforms. It carries the fiddly, error-prone part:

- Parses the asar header (`[u32 4][u32 headerBufLen][u32 headerBufLen-4][u32 jsonLen][json][pad][data]`)
- **Appends** replaced files at the end of the data region and touches only those entries'
  `size` / `offset` / `integrity` — every other byte is preserved (minimal blast radius)
- Verifies per entry: **untouched entries must be byte-identical; replaced entries must match exactly**

The macOS driver isolates everything platform-specific into **one clearly delimited block**
(marked with a banner at the top of the script):

```bash
# ══════════════ Platform-specific: a Windows port only needs to change this block ══════════════
ASAR_REL="Contents/Resources/app.asar"     # Windows: resources/app.asar
INNER_PREFIX="dsh/node_modules/@deepseek-ai"
clone_app() { cp -c -R "$1" "$2" ... ; }   # Windows: xcopy / robocopy
sign_app()  { codesign ... ; }             # Windows: not needed (Electron does not verify Authenticode)
# ══════════════════════════════════════════════════════════════════════════════════════════════
```

### Merge criterion (when the two can become one)

**Criterion: are the 9 target files inside `app.asar` byte-identical across platforms?** To check:

```bash
# Run once on macOS and once on Windows; compare the output in a single issue
node desktop/dsh-desktop-asar.mjs cat <app.asar> "dsh/node_modules/@deepseek-ai/<relpath>" | shasum -a 256
```

- **All 9 sha256 values match** → payloads agree; the two drivers can be merged into one
  (keeping only the platform branches), and `patches/**` stays shared.
- **Any value differs** → they must stay separate, and `patches/**` must be adapted
  **per platform** (i.e. a `patches/windows/**` set becomes necessary).

Until then, **do not** collapse the two platform scripts into one — it only makes
"which side broke" harder to diagnose.

---

## 🚀 Quick start (macOS)

### Prerequisites

- macOS (Apple Silicon; Intel works the same — the script is architecture-agnostic)
- Node.js (any recent version; standard library only)
- The `patch` command (bundled with macOS)
- The official desktop app installed at `/Applications/DeepSeek Harness.app`

### One command

```bash
# run from the repository root
bash desktop/macos/dsh-desktop-patch.sh
```

Defaults:

| | Path |
|---|---|
| Source (**read-only, never modified**) | `/Applications/DeepSeek Harness.app` |
| Destination (output) | `~/Applications/DeepSeek Harness Patched.app` |

Or specify explicitly:

```bash
bash desktop/macos/dsh-desktop-patch.sh "/Applications/DeepSeek Harness.app" "$HOME/Applications/DSH Patched.app"
```

### What the script does (6 steps)

1. **Clone** the official app — APFS copy-on-write (`cp -c -R`), takes seconds and uses **no extra disk**; the original is untouched
2. **Extract** the 9 target files from the asar
3. **Apply patches** — `patch -N -F 0 -p1`, **zero fuzz** (`-F 0` is what actually proves the anchors were not changed upstream)
4. **Surgically rewrite** the asar — only those 9 entries are replaced
5. **Verify** — per-entry diff plus a **feature-marker check** (if any marker is missing, nothing is written and the target app stays as-is)
6. **Re-sign** — ad-hoc, preserving hardened runtime and the original entitlements; then clear quarantine

### Launch

```bash
open "$HOME/Applications/DeepSeek Harness Patched.app"
```

---

## ✅ Feature marker table

Whether a patch actually took effect is decided by strings that **do not exist in the official
build and only appear once patched**. Measured (patches target desktop `0.2.0-rc.2` / CLI `0.2.0-rc.1`):

| Target file (relative to `@deepseek-ai/`) | Feature marker | Official | Patched |
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

> Lesson learned while picking markers: `surfaceOp: "append"` was first chosen for
> `dsh-agent-loop`, but it **already appears 8 times** in the official build — useless as a
> discriminator. A marker must be a string with **zero** occurrences upstream.
> `bash check-update.sh` re-runs this table; a marker disappearing means the patch was overwritten.

---

## ⚖️ Costs and limitations

| Item | Note |
|---|---|
| **Signature becomes ad-hoc** | After re-signing: `Signature=adhoc`, `TeamIdentifier=not set`, `flags=0x10002(adhoc,runtime)`. Functionality is unaffected; if you have compliance requirements that depend on the vendor signature, do not use this. |
| **`Info.plist` needs no update** | Electron's `EnableEmbeddedAsarIntegrityValidation` fuse is `0` (verified), so changed asar contents are not rejected and `ElectronAsarIntegrity` need not be updated. |
| **Nightly auto-update overwrites it** | After the official app updates, re-run the script. `bash check-update.sh` detects and warns about this. |
| **Cannot run alongside the official app** | They **share the same user-data directory**, plus a single-instance lock and the fixed port `19387` — starting both fails. Quit one first. |
| **Port 19387 is hard-coded** | Unlike the CLI, the desktop app takes no `--port`; on a conflict, the other program must move. |
| **The official app is never modified** | All output lives under `~/Applications/`; `/Applications/DeepSeek Harness.app` stays pristine. |

---

## ↩️ Rollback

The patched build is a **separate app**; rollback is just deleting it:

```bash
rm -rf "$HOME/Applications/DeepSeek Harness Patched.app"
```

The official app was never modified, so deleting the copy restores the original state.
To return `/Applications` to a freshly-downloaded state, simply reinstall from the vendor
(this repository never touches it).

---

## 🔗 Relationship to the CLI-side patches

- **Same patch files**: the 9 `.patch` files under `patches/**` are shared between the CLI
  surfaces and the desktop app — no duplicate maintenance.
- **Different targets**: the CLI side patches `node_modules/@deepseek-ai/**`; the desktop
  side patches inside `app.asar`.
- **Patch both at once**: `patch-all.sh` at the repository root handles both surfaces in turn
  and **cross-checks feature markers on each**, printing a matrix — the fastest way to confirm
  that the browser / VS Code / desktop surfaces are functionally in sync.

```bash
bash patch-all.sh          # CLI side + desktop, with cross-check
bash patch-all.sh --check  # verify only; modifies nothing
```

---

## 🤝 Contributing the Windows module

See [`windows/README.md`](windows/README.md) — it lists what to deliver and the
"separate first, merge later" criterion. Core principles:

1. **Do not** turn `macos/dsh-desktop-patch.sh` into a cross-platform script and commit it
   (that would break the macOS paths at the same time);
2. Create `desktop/windows/` and reuse `desktop/dsh-desktop-asar.mjs` (it is cross-platform
   and needs no changes);
3. Keep platform-specific code inside the "platform-specific" block at the top of the script,
   so it can be compared and merged later;
4. Include the **sha256 of the 9 target files** in your PR (see "Merge criterion" above),
   so we know whether merging is possible.

---

## 📎 See also

- Main README: [../README.en.md](../README.en.md)
- Full procedure for adapting to a new official release: [../ADAPTING.md](../ADAPTING.md)
- Research notes and pitfalls for the desktop adaptation: [../ADAPTING.md](../ADAPTING.md) and `versions.md`
