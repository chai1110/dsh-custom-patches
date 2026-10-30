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

> This section is a **file-level** check (it proves the bytes inside the asar were changed).
> To see whether the runtime actually serves those changes, use the next section.

---

## Headless runtime verification (recommended, scriptable)

The previous section only proves "the **files** inside the asar changed"; it does **not** prove
the runtime actually serves them. The flow below extracts the patched asar, boots the desktop
host for real against an isolated `DSH_HOME` and a spare port, then inspects the client bundles
it **actually serves** — no GUI needed, and the running official app is never touched.

### 1. Extract the asar

The asar header layout is `[UInt32 4][UInt32 headerSize][UInt32 jsonSize][JSON…]`, and the data
region starts at `8 + headerSize`. `dsh-desktop-asar.mjs cat` only reads one file at a time,
while booting the host needs the whole tree, so you have to extract it yourself. Two traps:

- **The JSON header starts at offset 16, not 12** (there is another Pickle length field before it)
- Entries flagged `"unpacked": true` in the header are **not inside the asar** and must be copied
  in separately from `app.asar.unpacked/`. All the native `.node` bindings live there; without them
  boot fails with `No usable native binding found for node-addon-require-builtin-…`

### 2. Run the host

The Electron main process spawns it with fixed arguments (see `lib/main.js` inside the asar):

```bash
node --expose-internals \
  <runtimeDir>/node_modules/@deepseek-ai/dsh-desktop-host/lib/index.js \
  <runtimeDir> <profileDir> <app>/Contents/Resources/runtime/primary-runtime
```

- `runtimeDir` = the extracted `dsh/` directory; `profileDir` = `<DSH_HOME>/profiles/desktop`
- **0.2.0 and earlier**: the port is **hard-coded to 19387** inside the host, which collides with the
  running official build — change that one spot in the extracted copy when accepting (the copy only, never the asar)
- **Since 0.2.1 (measured 2026-10-17)**: the port is **no longer hard-coded** — the `dsh-desktop-host/lib/index.js`
  args are now `["--no-open","--host","127.0.0.1","--port","0"]` (dynamic allocation), and `19387` appears
  **0 times** in the new host file. On this machine the running host landed on `127.0.0.1:55218`. **Do not patch the
  port during acceptance any more**; read the real port from stdout (`dsh web: http://127.0.0.1:<port>/?token=…`).
  Any script that probes 19387 or pulls the token from it will fail outright.
  Bonus: it no longer fights the official build for the port — only the user-data single-instance lock remains.
- You **must** use an isolated `DSH_HOME`, otherwise it writes to your real desktop profile
- ⚠️ The desktop profile is exclusive to Electron: `dsh --profile desktop` fails outright with
  `profile "desktop" is managed exclusively by the Electron application`, so the host is the only way

### 3. Inspect the served bundles

On startup stdout prints `dsh web: http://127.0.0.1:<port>/?token=…`. The index HTML contains **73**
URLs shaped like `plugins/??<pkg>/client.js,…&rev=<hash>` — request them **verbatim**: the server
looks up `pathname + search` exactly, so **adding any parameter at all (even just `&token=`) 404s**:

```bash
curl -s "http://127.0.0.1:<port>/plugins/??@deepseek-ai/dsh-client-ui-chat/client.js,…&rev=<hash>" \
  | grep -c editLastPrompt
```

Two traps:

- **Decode the HTML entity `&amp;` back to `&` first.** 3 of the 73 are written escaped
  (`…client.js&amp;rev=…`) and 404 if requested as-is; once decoded those 3 turn out to be the
  **same URLs** as 3 others, so the distinct count is **70**.
- The index needs `?token=` **and a kept cookie** (the first request 303-redirects to a token-less
  path; without the cookie you get 401).

Measured (2026-10-16, DSH `0.2.0-rc.2`, patched asar):

- **70 distinct URLs, 70/70 HTTP 200, 22,887,506 bytes combined**
- Only 6 bundles carry patch markers:

| # | Size | Packages | First package | `recallHistory` | `editLastPrompt` | `session/editLastPrompt` |
|---|---|---|---|---|---|---|
| 1 | 10,472,541 | 57 | `dsh-client-product-analytics` | 3 | 16 | 0 |
| 2 | 929,602 | 9 | `dsh-session-log-export` | 0 | 12 | 1 |
| 33 | 721,911 | 1 | `dsh-client-ui-conversation` | 3 | 4 | 0 |
| 35 | 570,299 | 1 | `dsh-client-ui-chat` | 0 | 12 | 0 |
| 64 | 514,502 | 1 | `dsh-api-remotes` | 0 | 10 | 1 |
| 67 | 144,815 | 1 | `dsh-api-session-controller` | 0 | 2 | 0 |
| | | | **Total** | **6** | **56** | **2** |

The other two markers score 0 in client bundles — that is **expected**:

| Marker | Hits | Why zero |
|---|---|---|
| `editLastPromptOnce` | 0 | lives only in the **host-side** `dsh-api-session-controller/lib/index.js` |
| `compactionBackoffDelay` | 0 | lives only in the **host-side** `dsh-compaction-basic/lib/index.js` |

> Do not read those zeroes as a failed patch — they are simply not supposed to be in client bundles.

> 📌 This section first recorded "73 URLs / 34,329,979 bytes / 9 / 72 / 3". That counted the 3
> HTML-escaped copies above as separate URLs and **fetched them twice** (the extra
> 10,472,541 + 929,602 + 40,330 = 11,442,473 bytes). The table above is the deduplicated figure.

### 4. Confirm the provider config takes effect

Verify the SenseNova block in the desktop profile's `cordis.patch.yml` by dumping the composed config:

```bash
mkdir -p /tmp/probe/profiles/deskcheck
cp ~/.dsh/profiles/desktop/package.json ~/.dsh/profiles/desktop/cordis.patch.yml /tmp/probe/profiles/deskcheck/
DSH_HOME=/tmp/probe node <runtimeDir>/node_modules/@deepseek-ai/dsh/lib/bin.js \
  --profile deskcheck --dump-config | grep -A12 'sensenova'
```

You should see `llm-pi-ai.providers.sensenova` (with the two `compat` corrections and `retryPolicy`),
plus `agent-default-model` set to `provider: sensenova` / `model: deepseek-v4-flash`.

---

## Manual acceptance (GUI, the last line of defence)

With the headless check green, one human pass over the interaction is still worth it:

1. `open "$HOME/Applications/DeepSeek Harness Patched.app"`
2. Send a message and let it finish replying
3. **① Recall**: put the caret in the composer (no text) and press **↑** — the last sent message should appear
4. **② Edit**: hover the **last user message** — an **✏️ Edit** entry should appear; edit and regenerate
5. **③ Compaction retry**: hard to trigger by hand; covered by the `patches/compaction-basic` marker check

> ⚠️ The patched build and the official build **share one user-data directory**
> (single-instance lock; 0.2.0 and earlier also had a fixed port `19387`). Quit the official app before accepting.

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
| The two apps cannot run at the same time | By design (shared user-data + single-instance lock; 0.2.0 and earlier also had a fixed port 19387) |
| No edit button after patching | First confirm all 9 markers are green in step 5; then confirm you opened the **patched** build, not the official one |
| Patches vanish after a nightly update | The desktop app uses nightly auto-update; **re-run this script after every official update**. a `--dry-run` run shows it |
| The `ElectronAsarIntegrity` hash in `Info.plist` does not match the actual asar | **Not a problem, nothing to fix** — that fuse measures `0`, so Electron does not validate. See "Re-signing details" above |

---

## See also

- Parent overview: [../README.en.md](../README.en.md)
- Windows module (to be contributed): [../windows/README.md](../windows/README.md)
- Adapting to a new release: [../../ADAPTING.md](../../ADAPTING.md)
