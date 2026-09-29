# macOS Desktop Module

> 📖 [中文](README.md) ｜ Parent: [../README.en.md](../README.en.md)

Applies this repository's 9 feature patches to the **macOS DeepSeek Harness desktop app**.

---

## One command

```bash
# run from the repository root
bash desktop/macos/dsh-desktop-patch.sh
```

| | Default path |
|---|---|
| Source (**read-only, never modified**) | `/Applications/DeepSeek Harness.app` |
| Destination (output) | `~/Applications/DeepSeek Harness Patched.app` |

Customise:

```bash
bash desktop/macos/dsh-desktop-patch.sh "/Applications/DeepSeek Harness.app" "$HOME/Applications/DSH Patched.app"
bash desktop/macos/dsh-desktop-patch.sh --help    # print the script header
```

---

## Prerequisites

| Dependency | Note |
|---|---|
| macOS | Apple Silicon or Intel; the script is architecture-agnostic |
| Node.js | Any recent version; standard library only, no npm dependencies |
| `patch` | Bundled with macOS (`/usr/bin/patch`) |
| `codesign` | Bundled with macOS (Xcode Command Line Tools; the system copy suffices) |
| Official desktop app | Installed at `/Applications/DeepSeek Harness.app` |

---

## Inside the script (6 steps)

| Step | What it does | On failure |
|---|---|---|
| 1/6 Clone | `cp -c -R` (APFS copy-on-write: seconds, no extra disk); falls back to `cp -R` on non-APFS | An existing destination is removed first; a destination under `/Applications` is **refused** |
| 2/6 Extract | `../dsh-desktop-asar.mjs cat` pulls the 9 target files out of the asar | A missing asar path aborts with a hint that `ASAR_REL` may have changed |
| 3/6 Patch | `patch -N -F 0 -p1`, **zero fuzz**; any `.rej` aborts | Aborts — the target app is **not** touched |
| 4/6 Rewrite | Only those 9 entries are replaced; every other byte is preserved | The tool refuses to rewrite if the header's key order does not round-trip |
| 5/6 Verify | Per-entry diff plus a **9-marker feature check** | Any missing marker → **nothing is written**; the target app stays as-is |
| 6/6 Re-sign | Ad-hoc re-sign (keeping hardened runtime + original entitlements), clear quarantine | Exits with an error (the asar is already replaced — just re-run) |

**Safety design**: if step 3 or 5 fails, no half-finished app is left behind — the result is
either fully working or completely untouched.

---

## What the output looks like

Measured on 2026-09-29 against desktop `0.2.0-rc.2`:

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

- **All 12,964 untouched entries are byte-identical** — direct evidence of the minimal blast radius.
- The data region grows from 117,993,833 to 120,456,903 bytes (only the delta of the replaced files).
- The original data region is **left in place** (old content is still there, just no longer indexed),
  so the asar only grows. That is a deliberate trade-off: it buys "not a single other byte changes",
  which is far safer than repacking.

---

## Re-signing details

Changing the asar **requires** re-signing, or macOS refuses to launch (the signature seals `Resources`).

| Item | Value |
|---|---|
| Method | ad-hoc (`--sign -`) |
| Preserved | `--options runtime` (hardened runtime) + the original entitlements (4: `cs.allow-jit`, `cs.allow-unsigned-executable-memory`, `cs.disable-library-validation`, `device.audio-input`) |
| Result | `flags=0x10002(adhoc,runtime)`, `Signature=adhoc`, `TeamIdentifier=not set` |
| **No** `Info.plist` change needed | Electron's `EnableEmbeddedAsarIntegrityValidation` fuse is `0` (verified), so changed asar contents are not rejected and `ElectronAsarIntegrity` need not be updated |

> Why ad-hoc suffices: Electron validates asar integrity through that fuse, which is a separate
> mechanism from macOS code signing. With the fuse off, it is enough to make the macOS signature
> valid again (ad-hoc is fine).

---

## Feature marker check

Step 5 verifies each marker (passing means: 0 occurrences in the official build, ≥1 once patched):

| Target file | Marker | Official | Patched |
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

Check a single file by hand:

```bash
ASAR="$HOME/Applications/DeepSeek Harness Patched.app/Contents/Resources/app.asar"
node desktop/dsh-desktop-asar.mjs cat "$ASAR" "dsh/node_modules/@deepseek-ai/dsh-client-ui-conversation/lib/client.js" | grep -c recallHistory
```

---

## Manual acceptance (independent of the script's self-check)

The script only proves "the files changed"; **whether the features actually work needs a human look**:

1. `open "$HOME/Applications/DeepSeek Harness Patched.app"`
2. Send a message and let it finish replying
3. **① Recall**: put the caret in the composer (no text) and press **↑** — the last sent message should appear
4. **② Edit**: hover the **last user message** — an **✏️ Edit** entry should appear; edit and regenerate
5. **③ Compaction retry**: hard to trigger by hand; covered by the `patches/compaction-basic` marker check

> ⚠️ The patched build and the official build **share one user-data directory**
> (single-instance lock + fixed port `19387`). Quit the official app before accepting.

---

## Rollback

```bash
rm -rf "$HOME/Applications/DeepSeek Harness Patched.app"
```

The official app is never modified. To restore `/Applications` to a freshly-downloaded state,
simply reinstall it.

---

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `补丁未能零 fuzz 应用` (patch does not apply with zero fuzz) | The official desktop app was updated and the code changed. Re-adapt `patches/` per [`../../ADAPTING.md`](../../ADAPTING.md) |
| `找不到 .../Contents/Resources/app.asar` | The vendor changed the app layout. Update `ASAR_REL` at the top of the script |
| `work: unbound variable` | Fixed on 2026-09-29 (a bash `local` multi-assignment trap). Update the repo |
| App will not open / "is damaged" | Re-signing did not finish. Re-run the script; if it still fails, read the `codesign --verify` output from step 6 |
| The two apps cannot run at the same time | By design (shared user-data + single-instance lock + fixed port 19387) |
| No edit button after patching | First confirm all 9 markers are green in step 5; then confirm you opened the **patched** build, not the official one |
| Patches vanish after a nightly update | The desktop app uses nightly auto-update; **re-run this script after every official update**. `bash check-update.sh` detects this |

---

## See also

- Parent overview: [../README.en.md](../README.en.md)
- Windows module (to be contributed): [../windows/README.md](../windows/README.md)
- Adapting to a new release: [../../ADAPTING.md](../../ADAPTING.md)
