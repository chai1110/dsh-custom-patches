#!/usr/bin/env node
// =============================================================================
// tools/dsh-patch.mjs — DSH custom patch applier (cross-platform, zero deps)
//
// WHY THIS EXISTS
//   The original shell scripts leaned on `patch`, `cp`, `find`, `pgrep`, `grep`
//   and POSIX path assumptions. On Windows (Git for Windows / PowerShell) those
//   either do not exist, behave differently, or produce mixed `\` and `/`
//   separators. Node.js is already a hard prerequisite for DSH (you installed
//   DSH with npm), so doing the work in Node removes the entire class of
//   platform problems:
//     * paths are built with path.join / path.resolve -> native separators
//     * no dependency on patch(1), cp(1), find(1), pgrep(1)
//     * no fuzz: hunks are matched EXACTLY (see "STRICT MATCHING" below)
//
// STRICT MATCHING (important)
//   `patch` defaults to a fuzz factor of 2, which silently tolerates context
//   lines that no longer match. That masks upstream drift and lets a patch
//   "succeed" onto the wrong anchor. This applier uses zero fuzz: every context
//   and deletion line must match exactly. If upstream moved the code, you get a
//   loud failure instead of a silent mis-patch.
//
// USAGE
//   node tools/dsh-patch.mjs                  # apply (interactive confirm)
//   node tools/dsh-patch.mjs -y               # apply, no confirmation
//   node tools/dsh-patch.mjs --dry-run        # check only, write nothing
//   node tools/dsh-patch.mjs --restore        # restore all targets from *.bak
//   node tools/dsh-patch.mjs --list           # show the patch set
//   node tools/dsh-patch.mjs --help
//
//   Monorepo / source layout:
//     DSH_SOURCE=/path/to/deepseek-harness node tools/dsh-patch.mjs -y
//
// Adapted version: 0.2.0-rc.2 (see versions.md for the full history)
// =============================================================================

import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';
import { execFileSync, spawnSync } from 'node:child_process';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const SCRIPT_DIR = path.dirname(__filename);
const REPO_ROOT = path.resolve(SCRIPT_DIR, '..');

// ---------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------
const TARGET_VERSION = '0.2.0-rc.2';

// rel          = path under node_modules/@deepseek-ai/  (npm layout)
// patch        = .patch file path inside this repo
// marker       = "official already ships this" detection string ('' = skip)
// sourceRel    = path under <source>/packages/          (monorepo layout)
const FILES = [
  {
    rel: 'dsh-api-session-controller/lib/index.js',
    patch: 'patches/api-session-controller/dsh-api-session-controller-lib-index.js.patch',
    marker: 'async editLastPrompt',
    sourceRel: 'api/session-controller/lib/index.js',
  },
  {
    rel: 'dsh-api-session-controller/lib/client.js',
    patch: 'patches/api-session-controller/dsh-api-session-controller-lib-client.js.patch',
    marker: 'async editLastPrompt',
    sourceRel: 'api/session-controller/lib/client.js',
  },
  {
    rel: 'dsh-api-session-controller/lib/typert.host.js',
    patch: 'patches/api-session-controller/dsh-api-session-controller-lib-typert-host.js.patch',
    marker: 'editLastPrompt',
    sourceRel: 'api/session-controller/lib/typert.host.js',
  },
  {
    rel: 'dsh-api-session-controller/lib/typert.remote-client.js',
    patch: 'patches/api-session-controller/dsh-api-session-controller-lib-typert-remote-client.js.patch',
    marker: 'editLastPrompt',
    sourceRel: 'api/session-controller/lib/typert.remote-client.js',
  },
  {
    rel: 'dsh-api-remotes/lib/client.js',
    patch: 'patches/api-remotes/dsh-api-remotes-lib-client.js.patch',
    marker: 'editLastPrompt',
    sourceRel: 'api/remotes/lib/client.js',
  },
  {
    rel: 'dsh-agent-loop/lib/index.js',
    patch: 'patches/agent-loop/dsh-agent-loop-lib-index.js.patch',
    marker: 'tailEvent?.type === "user/message"',
    sourceRel: 'core/agent-loop/lib/index.js',
  },
  {
    rel: 'dsh-compaction-basic/lib/index.js',
    patch: 'patches/compaction-basic/dsh-compaction-basic-lib-index.js.patch',
    marker: 'compactionBackoffDelay',
    sourceRel: 'core/compaction-basic/lib/index.js',
  },
  {
    rel: 'dsh-client-ui-conversation/lib/client.js',
    patch: 'patches/client-ui-conversation/dsh-client-ui-conversation-lib-client.js.patch',
    marker: 'recallHistory',
    sourceRel: 'client/ui-conversation/lib/client.js',
  },
  {
    rel: 'dsh-client-ui-chat/lib/client.js',
    patch: 'patches/client-ui-chat/dsh-client-ui-chat-lib-client.js.patch',
    marker: 'message.editPrompt',
    sourceRel: 'client/ui-chat/lib/client.js',
  },
];

// ---------------------------------------------------------------------------
// Terminal colours — disabled when not a TTY, or on NO_COLOR / dumb terminals.
// Windows 10+ consoles understand ANSI, but piping to a file must stay clean.
// ---------------------------------------------------------------------------
const COLOR =
  process.stdout.isTTY === true &&
  !process.env.NO_COLOR &&
  process.env.TERM !== 'dumb';

const c = (code, s) => (COLOR ? `\u001b[${code}m${s}\u001b[0m` : s);
const green = (s) => c('0;32', s);
const red = (s) => c('0;31', s);
const yellow = (s) => c('1;33', s);
const cyan = (s) => c('0;36', s);

const ok = (s) => console.log(`${green('[OK]')} ${s}`);
const info = (s) => console.log(`${cyan('[i]')} ${s}`);
const warn = (s) => console.log(`${yellow('[!]')} ${s}`);
const err = (s) => console.log(`${red('[x]')} ${s}`);

const IS_WINDOWS = process.platform === 'win32';

// ---------------------------------------------------------------------------
// Unified diff parsing
// ---------------------------------------------------------------------------

/**
 * Parse a unified diff into a list of hunks.
 *
 * Only the hunk bodies matter here: the FILES table already maps each patch to
 * its target file, so the `---` / `+++` headers (which carry `@deepseek-ai/`
 * prefixes and would need `-p1` stripping) are ignored entirely. That also
 * means no path parsing, hence no separator problems.
 *
 * The body length is bounded by the counts in the `@@` header — that is how
 * `patch` itself works, and it is the only reliable way to know where a hunk
 * ends. Two traps this avoids:
 *   1. `text.split('\n')` yields a final '' when the file ends with a newline;
 *      treating that as a context line would append a bogus empty line to the
 *      last hunk and break the anchor match.
 *   2. A deleted line whose content starts with `--` renders as `---...`, which
 *      a naive "skip lines starting with ---" rule would silently swallow.
 *
 * @param {string} text raw .patch contents (LF, ASCII)
 * @returns {{oldStart:number, oldCount:number, newCount:number,
 *            lines:{kind:' '|'-'|'+', text:string}[]}[]}
 */
function parsePatch(text) {
  const raw = text.split('\n');
  if (raw.length > 0 && raw[raw.length - 1] === '') raw.pop(); // trailing newline

  const hunks = [];
  let i = 0;

  while (i < raw.length) {
    const header = /^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@/.exec(raw[i]);
    if (header === null) {
      i++; // file header / preamble / blank separator
      continue;
    }

    const oldStart = Number(header[1]);
    const oldCount = header[2] === undefined ? 1 : Number(header[2]);
    const newCount = header[4] === undefined ? 1 : Number(header[4]);
    const h = { oldStart, oldCount, newCount, lines: [] };
    i++;

    let oldSeen = 0;
    let newSeen = 0;
    while (i < raw.length && (oldSeen < oldCount || newSeen < newCount)) {
      const l = raw[i];
      const kind = l.length > 0 ? l[0] : ' '; // an empty line is an empty context line
      const content = l.length > 0 ? l.slice(1) : '';

      if (kind === '\\') {
        i++; // "\ No newline at end of file" — carries no line count
        continue;
      }
      if (kind === ' ') {
        h.lines.push({ kind, text: content });
        oldSeen++;
        newSeen++;
      } else if (kind === '-') {
        h.lines.push({ kind, text: content });
        oldSeen++;
      } else if (kind === '+') {
        h.lines.push({ kind, text: content });
        newSeen++;
      } else {
        break; // malformed — let the count check below report it
      }
      i++;
    }

    if (oldSeen !== oldCount || newSeen !== newCount) {
      throw new Error(
        `hunk @@ -${oldStart} declares ${oldCount} old / ${newCount} new lines ` +
          `but only ${oldSeen} / ${newSeen} were present — patch file is malformed or truncated`,
      );
    }
    hunks.push(h);
  }

  if (hunks.length === 0) throw new Error('no hunks found in patch');
  return hunks;
}

/** Lines that must already exist at the anchor (context + deletions). */
const oldBlockOf = (h) => h.lines.filter((l) => l.kind !== '+').map((l) => l.text);
/** Lines that should exist after applying (context + additions). */
const newBlockOf = (h) => h.lines.filter((l) => l.kind !== '-').map((l) => l.text);

/** Exact, in-order match of `needle` inside `hay` starting at `at`. */
function matchesAt(hay, needle, at) {
  if (at < 0 || at + needle.length > hay.length) return false;
  for (let i = 0; i < needle.length; i++) {
    if (hay[at + i] !== needle[i]) return false;
  }
  return true;
}

/**
 * Locate a hunk's anchor.
 *
 * The declared offset is tried first (that is where upstream had it). If that
 * fails we scan the whole file — but only to produce a *better error message*:
 * a match found elsewhere means upstream moved the code, which we report as a
 * relocation rather than silently patching the wrong place.
 */
function findAnchor(hay, needle, declared) {
  if (needle.length === 0) return { at: declared, exact: true };
  if (matchesAt(hay, needle, declared)) return { at: declared, exact: true };

  const found = [];
  for (let i = 0; i + needle.length <= hay.length; i++) {
    if (matchesAt(hay, needle, i)) found.push(i);
  }
  if (found.length === 1) return { at: found[0], exact: false, movedTo: found[0] };
  if (found.length > 1) return { at: -1, exact: false, ambiguous: found };
  return { at: -1, exact: false };
}

/**
 * Apply every hunk of `patchText` to `sourceText`.
 * @returns {{ok:true, text:string, relocated:number[]} | {ok:false, reason:string, hunk:number}}
 */
function applyPatch(sourceText, patchText) {
  const hunks = parsePatch(patchText);
  const lines = sourceText.split('\n');
  const relocated = [];

  // Working offset: each applied hunk shifts everything below it.
  let delta = 0;

  for (let hi = 0; hi < hunks.length; hi++) {
    const h = hunks[hi];
    const needle = oldBlockOf(h);
    const declared = h.oldStart - 1 + delta;

    const hit = findAnchor(lines, needle, declared);

    if (hit.ambiguous !== undefined) {
      return {
        ok: false,
        hunk: hi + 1,
        reason:
          `anchor is ambiguous (matches ${hit.ambiguous.length} places at lines ` +
          hit.ambiguous.map((n) => n + 1).join(', ') +
          '); refusing to guess',
      };
    }
    if (hit.at < 0) {
      return {
        ok: false,
        hunk: hi + 1,
        reason:
          `anchor not found near line ${declared + 1} ` +
          `(hunk expects ${needle.length} exact lines; upstream likely changed this region)`,
      };
    }
    if (!hit.exact) relocated.push(hi + 1);

    const replacement = newBlockOf(h);
    lines.splice(hit.at, needle.length, ...replacement);
    delta += replacement.length - needle.length;
  }

  return { ok: true, text: lines.join('\n'), relocated };
}

/** Try the patch in reverse — used to detect an already-patched file. */
function isAlreadyApplied(sourceText, patchText) {
  const hunks = parsePatch(patchText);
  const lines = sourceText.split('\n');
  for (const h of hunks) {
    const needle = newBlockOf(h);
    const declared = h.oldStart - 1;
    if (findAnchor(lines, needle, declared).at < 0) return false;
  }
  return true;
}

// ---------------------------------------------------------------------------
// Locating the DSH install
// ---------------------------------------------------------------------------

/** Run `npm root -g`; returns '' when npm is unavailable. */
function npmGlobalRoot() {
  try {
    const out = execFileSync('npm', ['root', '-g'], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
      shell: IS_WINDOWS, // npm is npm.cmd on Windows
    });
    return out.trim();
  } catch {
    return '';
  }
}

/**
 * Find the DSH package directory.
 *
 * Order matters: `npm root -g` is authoritative on every platform, then
 * require.resolve (which handles non-standard prefixes), then a manual sweep of
 * the usual global locations — built with path.join so separators are native.
 *
 * @returns {{dir:string, how:string} | null}
 */
function locateDsh() {
  // A. npm root -g  ->  <root>/@deepseek-ai/dsh
  const root = npmGlobalRoot();
  if (root !== '') {
    const cand = path.join(root, '@deepseek-ai', 'dsh');
    if (fs.existsSync(path.join(cand, 'package.json'))) {
      return { dir: cand, how: 'npm root -g' };
    }
  }

  // B. require.resolve, anchored at this repo so node_modules lookup starts
  //    somewhere sane. Handles npm prefixes that `npm root -g` reports oddly.
  try {
    const req = createRequire(path.join(REPO_ROOT, 'package.json'));
    const pkgJson = req.resolve('@deepseek-ai/dsh/package.json');
    return { dir: path.dirname(pkgJson), how: 'require.resolve' };
  } catch {
    /* fall through */
  }

  // C. sweep the usual global node_modules locations
  const candidates = [];
  if (IS_WINDOWS) {
    if (process.env.APPDATA) candidates.push(path.join(process.env.APPDATA, 'npm', 'node_modules'));
    if (process.env.LOCALAPPDATA) {
      candidates.push(path.join(process.env.LOCALAPPDATA, 'npm', 'node_modules'));
    }
    if (process.env.ProgramFiles) {
      candidates.push(path.join(process.env.ProgramFiles, 'nodejs', 'node_modules'));
    }
  } else {
    candidates.push('/usr/local/lib/node_modules');
    candidates.push('/usr/lib/node_modules');
  }
  if (process.env.HOME) candidates.push(path.join(process.env.HOME, '.local', 'lib', 'node_modules'));
  if (process.env.npm_config_prefix) {
    candidates.push(path.join(process.env.npm_config_prefix, 'lib', 'node_modules'));
    candidates.push(path.join(process.env.npm_config_prefix, 'node_modules'));
  }

  for (const base of candidates) {
    const cand = path.join(base, '@deepseek-ai', 'dsh');
    if (fs.existsSync(path.join(cand, 'package.json'))) {
      return { dir: cand, how: `scan ${base}` };
    }
  }
  return null;
}

// ---------------------------------------------------------------------------
// Layout resolution
// ---------------------------------------------------------------------------

/**
 * Resolve the layout once, so every entry maps to an absolute native path.
 * @returns {{layout:'npm'|'source', dshDir:string, sourceRoot:string, label:string}}
 */
function resolveLayout() {
  const src = process.env.DSH_SOURCE;
  if (src !== undefined && src.trim() !== '') {
    const abs = path.resolve(src);
    if (!fs.existsSync(path.join(abs, 'packages'))) {
      err(`DSH_SOURCE=${src} is not a DSH source root (no "packages" directory).`);
      process.exit(1);
    }
    return { layout: 'source', dshDir: '', sourceRoot: abs, label: `source layout (${abs})` };
  }

  const found = locateDsh();
  if (found === null) {
    err('Cannot locate the DSH global install directory.');
    console.log('  Try:  npm install -g @deepseek-ai/dsh');
    console.log('  If you built DSH from source, point at the monorepo instead:');
    console.log(
      IS_WINDOWS
        ? '    set DSH_SOURCE=C:\\path\\to\\deepseek-harness  &&  node tools\\dsh-patch.mjs -y'
        : '    DSH_SOURCE=/path/to/deepseek-harness node tools/dsh-patch.mjs -y',
    );
    process.exit(1);
  }
  return { layout: 'npm', dshDir: found.dir, sourceRoot: '', label: `npm layout (${found.dir}) [via ${found.how}]` };
}

/**
 * Absolute target path for one entry under the active layout.
 *
 * npm has two shapes for a global install and both occur in the wild:
 *   nested   <prefix>/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/<rel>
 *   hoisted  <prefix>/lib/node_modules/@deepseek-ai/<rel>      <- npm's usual choice
 * We probe both instead of assuming, because getting this wrong silently
 * reports "target missing, skip" for every entry.
 */
function targetFor(layout, entry) {
  if (layout.layout === 'source') {
    return path.join(layout.sourceRoot, 'packages', entry.sourceRel);
  }
  const nested = path.join(layout.dshDir, 'node_modules', '@deepseek-ai', entry.rel);
  const hoisted = path.join(path.dirname(layout.dshDir), entry.rel);
  if (fs.existsSync(nested)) return nested;
  if (fs.existsSync(hoisted)) return hoisted;
  return nested; // neither exists yet — report the conventional path
}

/** Read a package version without requiring it (avoids Windows path escaping). */
function readVersion(dir) {
  try {
    return JSON.parse(fs.readFileSync(path.join(dir, 'package.json'), 'utf8')).version;
  } catch {
    return '';
  }
}

/** npm dist-tags — `version` alone only reports `latest`, which is a trap. */
function npmDistTag(tag) {
  try {
    const out = execFileSync('npm', ['view', '@deepseek-ai/dsh', `dist-tags.${tag}`], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
      shell: IS_WINDOWS,
    });
    return out.trim();
  } catch {
    return '';
  }
}

// ---------------------------------------------------------------------------
// Restart hint — the one place that is genuinely platform-specific
// ---------------------------------------------------------------------------
function printRestartHint() {
  console.log('  1. Restart DSH:');
  if (IS_WINDOWS) {
    console.log(`     ${yellow('taskkill /F /IM node.exe')}   # then: dsh web`);
    console.log('     (taskkill ends every node process; close other node work first)');
  } else {
    console.log(`     ${yellow("pkill -f 'dsh web'")} ; ${yellow('dsh web')}`);
  }
  const refresh = IS_WINDOWS ? 'Ctrl+Shift+R' : 'Cmd+Shift+R (macOS) / Ctrl+Shift+R';
  console.log(`  2. Hard-refresh the browser page (${refresh}) to pick up the new features.`);
}

// ---------------------------------------------------------------------------
// Commands
// ---------------------------------------------------------------------------

function printHelp() {
  console.log(`
DSH custom patch applier — cross-platform, zero dependencies

Usage:
  node tools/dsh-patch.mjs [options]

Options:
  -y, --yes        skip the interactive confirmation
      --dry-run    verify every patch applies, write nothing
      --restore    restore all targets from their .bak copies
      --list       list the patch set and exit
      --help       show this message

Environment:
  DSH_SOURCE       path to a deepseek-harness source tree (monorepo layout)

This build targets DSH ${TARGET_VERSION}. Other DSH versions: check out the
matching tag/branch first (see README "multi-version support").
`);
}

function cmdList() {
  console.log(`Patch set for DSH ${TARGET_VERSION} (${FILES.length} entries):\n`);
  for (const e of FILES) {
    const p = path.join(REPO_ROOT, e.patch);
    const exists = fs.existsSync(p);
    console.log(`  ${exists ? green('✓') : red('✗')} ${e.rel}`);
    console.log(`      patch : ${e.patch}`);
    if (e.marker !== '') console.log(`      marker: ${e.marker}`);
  }
}

function cmdRestore(layout) {
  console.log(`${cyan('--- restore from backups ---')}`);
  let restored = 0;
  let missing = 0;
  for (const e of FILES) {
    const target = targetFor(layout, e);
    const bak = `${target}.bak`;
    if (fs.existsSync(bak)) {
      fs.copyFileSync(bak, target);
      ok(`restored: ${e.rel}`);
      restored++;
    } else {
      missing++;
    }
  }
  console.log('');
  if (restored === 0) {
    warn(`No .bak files found — nothing was restored (${missing} targets had no backup).`);
  } else {
    ok(`Restored ${restored} file(s). ${missing} had no backup.`);
    console.log('');
    printRestartHint();
  }
}

function cmdApply(layout, { dryRun, yes }) {
  console.log(`${cyan('--- built-in detection ---')}`);

  const toApply = [];
  let skippedBuiltIn = 0;

  for (const e of FILES) {
    const target = targetFor(layout, e);
    if (!fs.existsSync(target)) {
      warn(`target missing, skip: ${e.rel}`);
      continue;
    }
    if (e.marker !== '') {
      const body = fs.readFileSync(target, 'utf8');
      if (body.includes(e.marker)) {
        warn(`official build already contains "${e.marker}" -> skip: ${e.rel}`);
        skippedBuiltIn++;
        continue;
      }
    }
    toApply.push({ entry: e, target });
  }

  if (toApply.length === 0) {
    info('Every feature is already present (built into DSH, or already patched).');
    info('Nothing to do.');
    return 0;
  }

  console.log('');
  console.log(`${cyan(`--- patches to apply (${toApply.length}) ---`)}`);
  for (const t of toApply) info(`will apply: ${t.entry.rel}`);
  console.log('');

  if (!dryRun && !yes) {
    // Synchronous stdin read — avoids depending on readline behaviour.
    const buf = Buffer.alloc(64);
    process.stdout.write('Proceed? [y/N] ');
    let n = 0;
    try {
      n = fs.readSync(0, buf, 0, buf.length, null);
    } catch {
      n = 0;
    }
    const ans = buf.subarray(0, n).toString('utf8').trim().toLowerCase();
    if (ans !== 'y' && ans !== 'yes') {
      console.log('Cancelled.');
      return 1;
    }
  }

  console.log(`${cyan('--- apply ---')}`);

  let applied = 0;
  let already = 0;
  let failed = 0;
  let totalRelocated = 0;

  for (const { entry, target } of toApply) {
    const patchPath = path.join(REPO_ROOT, entry.patch);
    if (!fs.existsSync(patchPath)) {
      err(`patch file missing: ${entry.patch}`);
      failed++;
      continue;
    }

    const source = fs.readFileSync(target, 'utf8');
    const patchText = fs.readFileSync(patchPath, 'utf8');

    // Already in the patched state? (detected by reverse-matching)
    let isApplied = false;
    try {
      isApplied = isAlreadyApplied(source, patchText);
    } catch {
      isApplied = false;
    }
    if (isApplied) {
      info(`already patched, skip: ${entry.rel}`);
      already++;
      continue;
    }

    let result;
    try {
      result = applyPatch(source, patchText);
    } catch (e) {
      err(`cannot parse patch ${entry.patch}: ${e.message}`);
      failed++;
      continue;
    }

    if (!result.ok) {
      err(`cannot apply: ${entry.rel}`);
      console.log(`      hunk #${result.hunk}: ${result.reason}`);
      failed++;
      continue;
    }

    if (dryRun) {
      ok(`would apply: ${entry.rel}${result.relocated.length > 0 ? yellow(` (hunks moved: ${result.relocated.join(',')})`) : ''}`);
      applied++;
      totalRelocated += result.relocated.length;
      continue;
    }

    // Backup once, before the first write.
    const bak = `${target}.bak`;
    if (!fs.existsSync(bak)) {
      fs.copyFileSync(target, bak);
      info(`backed up: ${entry.rel}.bak`);
    }

    fs.writeFileSync(target, result.text, 'utf8');

    // Syntax-check the result — a mis-applied patch that still parses is a
    // silent behavioural bug, but a patch that breaks parsing is caught here.
    const check = spawnSync(process.execPath, ['--check', target], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
    });
    if (check.status !== 0) {
      err(`syntax check FAILED after patching: ${entry.rel}`);
      console.log(`      ${(check.stderr || '').trim().split('\n').slice(0, 3).join('\n      ')}`);
      console.log(`      restoring from backup...`);
      fs.copyFileSync(bak, target);
      failed++;
      continue;
    }

    ok(`applied: ${entry.rel}${result.relocated.length > 0 ? yellow(` (hunks moved: ${result.relocated.join(',')})`) : ''}`);
    applied++;
    totalRelocated += result.relocated.length;
  }

  console.log('');
  console.log(`${cyan('='.repeat(60))}`);
  if (failed === 0) {
    console.log(
      green(
        `  Done — ${dryRun ? 'verified' : 'applied'} ${applied}, already patched ${already}, skipped (built-in) ${skippedBuiltIn}, failed 0.`,
      ),
    );
  } else {
    console.log(red(`  Done — success ${applied}, already patched ${already}, failed ${failed}.`));
  }
  if (totalRelocated > 0) {
    warn(
      `${totalRelocated} hunk(s) matched at a different line than declared — ` +
        'upstream moved code but the anchors were still exact. Review ADAPTING.md before release.',
    );
  }
  console.log(`${cyan('='.repeat(60))}`);
  console.log('');

  if (failed > 0) {
    console.log(`${red('Some patches failed. Restore and re-adapt:')}`);
    console.log(`  node ${path.relative(process.cwd(), __filename) || 'tools/dsh-patch.mjs'} --restore`);
    console.log('  then follow ADAPTING.md and update versions.md.');
    return 1;
  }

  if (!dryRun) {
    console.log('Next steps:');
    printRestartHint();
  }
  return 0;
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------
function main() {
  const argv = process.argv.slice(2);
  let dryRun = false;
  let restore = false;
  let yes = false;

  for (const a of argv) {
    switch (a) {
      case '-y':
      case '--yes':
        yes = true;
        break;
      case '--dry-run':
        dryRun = true;
        break;
      case '--restore':
        restore = true;
        break;
      case '--list':
        cmdList();
        return 0;
      case '-h':
      case '--help':
        printHelp();
        return 0;
      default:
        err(`unknown argument: ${a}`);
        console.log('  run with --help for usage');
        return 1;
    }
  }

  console.log(`${cyan('='.repeat(60))}`);
  console.log(`${cyan(`   DSH custom enhancements — patcher (${TARGET_VERSION})`)}`);
  console.log(`${cyan('='.repeat(60))}`);
  console.log('');

  const layout = resolveLayout();
  info(`layout: ${layout.label}`);

  if (layout.layout === 'npm') {
    const version = readVersion(layout.dshDir);
    console.log(`    local version: ${yellow(version || 'unknown')}`);
    console.log(`    target version: ${yellow(TARGET_VERSION)}`);

    if (version !== TARGET_VERSION) {
      console.log('');
      err(`Version mismatch: this patch set targets ${TARGET_VERSION}, but ${version || 'unknown'} is installed.`);
      console.log('');
      console.log('  Choose one:');
      console.log(`    a) Use the matching release of this repo:`);
      console.log(`         git checkout v${version}   # then rerun`);
      console.log(`    b) Install the target DSH version:`);
      console.log(`         npm install -g @deepseek-ai/dsh@${TARGET_VERSION}`);
      console.log('    c) Official moved past this repo — re-adapt first (see ADAPTING.md).');
      return 1;
    }

    // Advisory only. Note we read BOTH channels: a release-candidate often
    // ships on `next` only, and `npm view <pkg> version` reports `latest`.
    const latest = npmDistTag('latest');
    const next = npmDistTag('next');
    if (latest !== '' || next !== '') {
      console.log(`    npm latest: ${yellow(latest || '(none)')}    npm next: ${yellow(next || '(none)')}`);
      if (next !== '' && next === TARGET_VERSION && latest !== TARGET_VERSION) {
        info(`This build tracks the "next" channel. Plain "npm i -g @deepseek-ai/dsh" installs ${latest}.`);
      }
    }
  } else {
    warn('Source layout: skipping the npm version check.');
    warn(`Make sure the tree corresponds to ${TARGET_VERSION} and is built (lib/ artifacts).`);
  }
  console.log('');

  if (restore) return cmdRestore(layout);
  return cmdApply(layout, { dryRun, yes });
}

process.exit(main());
