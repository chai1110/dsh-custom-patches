#!/usr/bin/env node
/**
 * 桌面版（DeepSeek Harness Desktop）app.asar 补丁脚本
 *
 * 桌面版不走 npm 全局安装：补丁目标 9 个包都打在 Electron 的 resources/app.asar 里。
 * 本脚本把仓库 patches/ 下的 .patch 直接套到 asar 内的文件上，重建 asar，全量校验后替换。
 *
 * 用法（在仓库根目录执行）:
 *   node desktop/windows/apply-desktop-asar-patches.js                # 自动探测 app.asar，打补丁并替换（会先退出应用）
 *   node desktop/windows/apply-desktop-asar-patches.js --dry-run      # 只试套补丁，不生成、不替换
 *   node desktop/windows/apply-desktop-asar-patches.js --out new.asar # 生成新 asar 到指定路径，不替换原文件（应用可继续运行）
 *   node desktop/windows/apply-desktop-asar-patches.js --asar /path/to/app.asar --force
 *
 * 选项:
 *   --asar <path>    app.asar 路径（默认按平台自动探测，也可用环境变量 DSH_DESKTOP_ASAR）
 *   --patches <dir>  补丁目录（默认仓库根的 patches/，自动向上定位）
 *   --out <path>     输出新 asar 到该路径，跳过 退出/备份/替换/重启
 *   --dry-run        只做补丁试套（已应用的补丁会报「已应用」）
 *   --force          桌面版版本不在支持列表时仍继续
 *   --no-backup      替换时不生成 .bak-<时间戳> 备份
 *   --no-restart     替换后不自动重启应用
 *   --no-quit        不主动退出应用（文件被占用时替换会失败，慎用）
 *   --help           显示帮助
 *
 * 回滚: 把 resources/app.asar.bak-<时间戳> 改名回 app.asar 即可。
 * 注意: 桌面版带自动更新，更新会覆盖 asar，需要重跑本脚本。
 */
'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const crypto = require('crypto');
const { spawnSync, spawn } = require('child_process');

// 补丁集已验证适配的 DSH 版本（npm 包与桌面版同为这个版本号）
const SUPPORTED = ['0.2.0-rc.1', '0.2.0-rc.2'];
const APP_NAME = 'DeepSeek Harness';
const DEFAULT_PORT = 19387;

// 补丁应用成功的功能标记（校验新 asar 必须命中）
const MARKERS = [
  ['dsh-api-session-controller/lib/index.js', 'editLastPrompt'],
  ['dsh-client-ui-conversation/lib/client.js', 'recallHistory'],
  ['dsh-compaction-basic/lib/index.js', 'compactionBackoffDelay'],
];

const PKG_PREFIX = '/dsh/node_modules/@deepseek-ai/';

// 本脚本位于 <repo>/desktop/windows/，补丁集在仓库根的 patches/
const REPO_ROOT = path.resolve(__dirname, '..', '..');

/* ---------------- 小工具 ---------------- */
const RED = '\x1b[0;31m', GREEN = '\x1b[0;32m', YELLOW = '\x1b[1;33m', NC = '\x1b[0m';
const ok = m => console.log(`${GREEN}[ok]${NC} ${m}`);
const info = m => console.log(`     ${m}`);
const warn = m => console.log(`${YELLOW}[!!]${NC} ${m}`);
const die = m => { console.error(`${RED}[失败]${NC} ${m}`); process.exit(1); };

const sha = buf => crypto.createHash('sha256').update(buf).digest('hex');

function integrityOf(buf) {
  const blocks = [], BS = 4 * 1024 * 1024;
  for (let i = 0; i < buf.length; i += BS) blocks.push(sha(buf.slice(i, i + BS)));
  return { algorithm: 'SHA256', hash: sha(buf), blockSize: BS, blocks };
}

function parseArgs(argv) {
  const opts = { patches: path.join(REPO_ROOT, 'patches'), dryRun: false, force: false,
                 backup: true, restart: true, quit: true, out: null, asar: null };
  for (let i = 2; i < argv.length; i++) {
    const a = argv[i];
    switch (a) {
      case '--asar': opts.asar = argv[++i]; break;
      case '--patches': opts.patches = path.resolve(argv[++i]); break;
      case '--out': opts.out = path.resolve(argv[++i]); break;
      case '--dry-run': opts.dryRun = true; break;
      case '--force': opts.force = true; break;
      case '--no-backup': opts.backup = false; break;
      case '--no-restart': opts.restart = false; break;
      case '--no-quit': opts.quit = false; break;
      case '--help': case '-h': console.log(fs.readFileSync(__filename, 'utf8').split('*/')[0].replace(/^\/\*\*?/, '')); process.exit(0); break;
      default: die(`未知参数: ${a}（--help 查看用法）`);
    }
  }
  return opts;
}

function defaultAsarPath() {
  if (process.env.DSH_DESKTOP_ASAR) return process.env.DSH_DESKTOP_ASAR;
  const cands = [];
  if (process.platform === 'win32') {
    const la = process.env.LOCALAPPDATA || path.join(os.homedir(), 'AppData', 'Local');
    cands.push(path.join(la, 'Programs', APP_NAME, 'resources', 'app.asar'));
  } else if (process.platform === 'darwin') {
    cands.push(`/Applications/${APP_NAME}.app/Contents/Resources/app.asar`);
    cands.push(path.join(os.homedir(), 'Applications', `${APP_NAME}.app`, 'Contents', 'Resources', 'app.asar'));
  } else {
    cands.push(`/opt/${APP_NAME}/resources/app.asar`);
    cands.push(path.join(os.homedir(), '.local', 'opt', APP_NAME, 'resources', 'app.asar'));
  }
  for (const c of cands) if (fs.existsSync(c)) return c;
  return null;
}

function findPatchBin() {
  const cands = [];
  if (process.env.PATCH_BIN) cands.push(process.env.PATCH_BIN);
  cands.push('patch');
  if (process.platform === 'win32') {
    cands.push('C:\\Program Files\\Git\\usr\\bin\\patch.exe');
    cands.push('C:\\Program Files (x86)\\Git\\usr\\bin\\patch.exe');
    if (process.env.LOCALAPPDATA) cands.push(path.join(process.env.LOCALAPPDATA, 'Programs', 'Git', 'usr', 'bin', 'patch.exe'));
  } else cands.push('/usr/bin/patch', '/opt/homebrew/bin/patch');
  for (const c of cands) {
    const r = spawnSync(c, ['--version'], { encoding: 'utf8' });
    if (!r.error && r.status === 0) return c;
  }
  die('找不到 patch 命令。Windows 可装 Git for Windows，或用环境变量 PATCH_BIN 指定 patch 可执行文件。');
}

/* ---------------- asar 读写 ---------------- */
function readAsar(file) {
  const fd = fs.openSync(file, 'r');
  const pre = Buffer.alloc(8);
  fs.readSync(fd, pre, 0, 8, 0);
  if (pre.readUInt32LE(0) !== 4) { fs.closeSync(fd); die(`${file} 不是合法的 asar（头部 magic 不对）`); }
  const hs = pre.readUInt32LE(4);
  const hb = Buffer.alloc(hs);
  fs.readSync(fd, hb, 0, hs, 8);
  const strLen = hb.readUInt32LE(4);
  const header = JSON.parse(hb.slice(8, 8 + strLen).toString('utf8'));
  return { file, fd, hs, strLen, header, bodyStart: 8 + hs, size: fs.statSync(file).size };
}

function walk(node, prefix, acc) {
  if (node.files) { for (const k of Object.keys(node.files)) walk(node.files[k], prefix + '/' + k, acc); }
  else acc.push({ path: prefix, node });
  return acc;
}

function readEntry(asar, entry) {
  const b = Buffer.alloc(Number(entry.node.size));
  fs.readSync(asar.fd, b, 0, Number(entry.node.size), asar.bodyStart + Number(entry.node.offset));
  return b;
}

function headerOrderMonotonic(list) {
  let last = -1;
  for (const f of list) { const o = Number(f.node.offset); if (!Number.isFinite(o) || o < last) return false; last = o; }
  return true;
}

/* ---------------- 退出 / 重启应用 ---------------- */
function isRunning() {
  if (process.platform === 'win32') {
    const r = spawnSync('tasklist', ['/FI', `IMAGENAME eq ${APP_NAME}.exe`], { encoding: 'utf8' });
    return !!r.stdout && r.stdout.includes(`${APP_NAME}.exe`);
  }
  const r = spawnSync('pgrep', ['-f', APP_NAME], { encoding: 'utf8' });
  return r.status === 0;
}

function quitApp() {
  info(`退出 ${APP_NAME} ...`);
  if (process.platform === 'win32') {
    spawnSync('taskkill', ['/IM', `${APP_NAME}.exe`], { encoding: 'utf8' });
    for (let i = 0; i < 10 && isRunning(); i++) spawnSync('ping', ['-n', '2', '127.0.0.1'], { stdio: 'ignore' });
    if (isRunning()) spawnSync('taskkill', ['/F', '/IM', `${APP_NAME}.exe`], { encoding: 'utf8' });
  } else if (process.platform === 'darwin') {
    spawnSync('osascript', ['-e', `quit app "${APP_NAME}"`], { stdio: 'ignore' });
    for (let i = 0; i < 8 && isRunning(); i++) spawnSync('ping', ['-c', '2', '127.0.0.1'], { stdio: 'ignore' });
    if (isRunning()) spawnSync('pkill', ['-f', APP_NAME], { stdio: 'ignore' });
  } else {
    spawnSync('pkill', ['-f', APP_NAME], { stdio: 'ignore' });
    for (let i = 0; i < 8 && isRunning(); i++) spawnSync('sleep', ['2'], { stdio: 'ignore' });
  }
  if (isRunning()) warn('应用仍在运行，替换可能因文件占用失败');
}

function startApp(asarPath) {
  const resources = path.dirname(asarPath);
  const root = path.dirname(resources);
  if (process.platform === 'win32') {
    const exe = path.join(root, `${APP_NAME}.exe`);
    if (fs.existsSync(exe)) { spawn(exe, [], { detached: true, stdio: 'ignore' }).unref(); return; }
  } else if (process.platform === 'darwin') {
    // resources = <Foo>.app/Contents/Resources → 向上找到 .app 本身
    let p = resources;
    while (p && path.dirname(p) !== p) {
      if (p.endsWith('.app')) { spawn('open', ['-a', p], { stdio: 'ignore' }); return; }
      p = path.dirname(p);
    }
  }
  warn('未能自动定位可执行文件，请手动启动应用');
}

function healthCheck(port) {
  try {
    require('http').get({ host: '127.0.0.1', port, path: '/', timeout: 4000 }, res => {
      res.resume();
      console.log(`${GREEN}[ok]${NC} 端口 ${port} 已监听（HTTP ${res.statusCode}${res.statusCode === 401 ? '，正常待鉴权' : ''}）`);
    }).on('error', e => warn(`端口 ${port} 探测失败: ${e.code || e.message}`)).on('timeout', function () { this.destroy(); });
  } catch (e) { warn('健康检查跳过: ' + e.message); }
}

/* ---------------- 主流程 ---------------- */
function main() {
  const opts = parseArgs(process.argv);

  // 1. 定位 asar
  const asarPath = opts.asar ? path.resolve(opts.asar) : defaultAsarPath();
  if (!asarPath) die('未找到 app.asar，请用 --asar <path> 指定（或设置环境变量 DSH_DESKTOP_ASAR）');
  if (!fs.existsSync(asarPath)) die(`文件不存在: ${asarPath}`);
  ok(`app.asar: ${asarPath}`);
  info(`${(fs.statSync(asarPath).size / 1024 / 1024).toFixed(2)} MB`);

  // 2. 读 header，定位补丁目标
  const A = readAsar(asarPath);
  const all = walk(A.header, '', []);
  const packed = all.filter(f => !f.node.unpacked && !f.node.link);
  info(`条目 ${all.length}，其中包内文件 ${packed.length}、unpacked ${all.filter(f => f.node.unpacked).length}`);
  if (!headerOrderMonotonic(packed)) die('asar 内 offset 非单调，与本脚本「按 header 顺序重写」的假设不符，已中止');

  // 3. 版本校验
  let version = null;
  for (const p of ['dsh/node_modules/@deepseek-ai/dsh/package.json', 'package.json']) {
    const e = all.find(f => f.path === '/' + p);
    if (e) { try { version = JSON.parse(readEntry(A, e).toString('utf8')).version; break; } catch (e2) { /* 继续 */ } }
  }
  if (!version) warn('未能读取桌面版版本号');
  else {
    ok(`桌面版版本: ${version}（补丁集支持: ${SUPPORTED.join(' / ')}）`);
    if (!SUPPORTED.includes(version)) {
      if (!opts.force) die(`版本 ${version} 未在支持列表里，可能套不上。确认后用 --force 继续（或先看 ADAPTING.md）`);
      warn('--force 已指定，继续');
    }
  }

  // 4. 收集补丁，映射到 asar 内路径
  const patchFiles = [];
  (function rec(d) {
    if (!fs.existsSync(d)) return;
    for (const e of fs.readdirSync(d, { withFileTypes: true })) {
      const p = path.join(d, e.name);
      if (e.isDirectory()) rec(p); else if (e.name.endsWith('.patch')) patchFiles.push(p);
    }
  })(opts.patches);
  if (!patchFiles.length) die(`补丁目录里没有 .patch 文件: ${opts.patches}`);
  patchFiles.sort();

  const jobs = patchFiles.map(pf => {
    const first = fs.readFileSync(pf, 'utf8').split(/\r?\n/)[0];
    const rel = first.replace(/^---\s+/, '').replace(/^\.\//, '').replace(/^@deepseek-ai\//, '');
    const asarRel = PKG_PREFIX + rel;
    const entry = all.find(f => f.path === asarRel);
    if (!entry) die(`asar 内找不到补丁目标: ${asarRel}（补丁来自 ${path.basename(pf)}）`);
    if (entry.node.unpacked) die(`${asarRel} 是 unpacked 文件（在 app.asar.unpacked 目录），本脚本只处理包内文件`);
    return { patch: pf, rel, asarRel, entry, patched: pf };
  });
  ok(`补丁 ${jobs.length} 个，目标全部在 asar 内`);

  // 5. 解出目标文件到临时目录
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'dsh-asar-'));
  try {
    for (const j of jobs) {
      const buf = readEntry(A, j.entry);
      j.orig = buf;
      const local = path.join(tmp, j.rel);
      fs.mkdirSync(path.dirname(local), { recursive: true });
      fs.writeFileSync(local, buf);
    }

    const patchBin = findPatchBin();
    info(`patch: ${patchBin}`);

    // 幂等判断：先反向 dry-run。已打过补丁的文件反向试套会成功（exit 0 且无 Unreversed），
    // 原始文件则报 "Unreversed patch detected" 且 exit 1 —— 据此区分「已应用 / 待应用」。
    // （正向 dry-run 不能用来判断：本仓库有补丁在已应用的文件上仍能正向套上，会重复叠加。）
    const classify = j => {
      const run = args => {
        const r = spawnSync(patchBin, args, { cwd: tmp, input: fs.readFileSync(j.patch), encoding: 'utf8' });
        return { status: r.status, out: (r.stdout || '') + (r.stderr || '') };
      };
      const rev = run(['--dry-run', '-R', '-p1', j.rel]);
      if (rev.status === 0 && !/Unreversed|FAILED|Skipping|ignored/i.test(rev.out)) return 'applied';
      const fwd = run(['--dry-run', '-N', '-p1', j.rel]);
      if (fwd.status !== 0 || /FAILED|Unreversed|ignored/i.test(fwd.out)) { console.error(fwd.out); return 'fail'; }
      return 'pending';
    };

    info('[识别补丁状态]');
    const state = {};
    for (const j of jobs) {
      state[j.rel] = classify(j);
      if (state[j.rel] === 'fail') die(`${path.basename(j.patch)} 试套失败（见上方 patch 输出）—— 版本可能不匹配`);
      info(`${j.rel.padEnd(52)} ${state[j.rel] === 'applied' ? '已应用' : '待应用'}`);
    }
    const pending = jobs.filter(j => state[j.rel] === 'pending');
    const already = jobs.length - pending.length;
    if (opts.dryRun) {
      if (pending.length === 0) ok(`9 个补丁全部已应用在当前 asar 中，无需重复`);
      else ok(`试套通过 ${pending.length} / ${jobs.length}（已应用 ${already}）`);
      return;
    }
    if (pending.length === 0) warn('补丁全部处于「已应用」状态，生成的 asar 将与原文件内容一致');

    for (const j of pending) {
      const r = spawnSync(patchBin, ['-N', '-p1', j.rel], { cwd: tmp, input: fs.readFileSync(j.patch), encoding: 'utf8' });
      const out = (r.stdout || '') + (r.stderr || '');
      if (r.status !== 0 || /FAILED|Rejected|ignored/i.test(out)) { console.error(out); die(`${path.basename(j.patch)} 应用失败`); }
      info(`${j.rel.padEnd(52)} 已应用`);
    }
    for (const j of jobs) if (fs.existsSync(path.join(tmp, j.rel + '.rej'))) die(`产生了 .rej: ${j.rel}`);

    // 6. 读回补丁后内容 + 标记自检
    for (const j of jobs) {
      j.newBuf = fs.readFileSync(path.join(tmp, j.rel));
      j.alreadyApplied = state[j.rel] === 'applied';
      info(`${j.rel.padEnd(52)} ${j.orig.length} -> ${j.newBuf.length} 字节${j.alreadyApplied ? '（原本已应用，未改动）' : ''}`);
      if (!j.alreadyApplied && sha(j.orig) === sha(j.newBuf)) warn('该文件内容未变化，补丁可能没起作用');
    }
    for (const [rel, marker] of MARKERS) {
      const j = jobs.find(x => x.rel === rel);
      if (!j) { warn(`标记校验跳过（无对应补丁文件）: ${rel}`); continue; }
      if (!j.newBuf.toString('utf8').includes(marker)) die(`${rel} 未包含标记 ${marker}，补丁可能没生效`);
    }
    ok('功能标记校验通过');

    // 7. 重建 asar
    const newHeader = JSON.parse(JSON.stringify(A.header));
    const nAll = walk(newHeader, '', []);
    const nPacked = nAll.filter(f => !f.node.unpacked && !f.node.link);
    if (nAll.length !== all.length || nPacked.length !== packed.length) die('重建后条目数变化，中止');

    for (const j of jobs) {
      const e = nAll.find(f => f.path === j.asarRel);
      if (!e) die('新 header 找不到 ' + j.asarRel);
      e.node.size = j.newBuf.length;
      e.node.integrity = integrityOf(j.newBuf);
    }

    const bodyParts = [];
    let pos = 0;
    for (let i = 0; i < nPacked.length; i++) {
      const e = nPacked[i];
      const j = jobs.find(x => x.asarRel === e.path);
      const buf = j ? j.newBuf : readEntry(A, packed[i]);
      e.node.offset = String(pos);
      bodyParts.push(buf);
      pos += buf.length;
    }
    for (const e of nAll) if (e.node.unpacked || e.node.link) e.node.offset = String(pos);

    const json = JSON.stringify(newHeader);
    const strLen = Buffer.byteLength(json, 'utf8');
    const hs = 8 + strLen;
    const pre = Buffer.alloc(8);
    pre.writeUInt32LE(4, 0);
    pre.writeUInt32LE(hs, 4);
    const hb = Buffer.alloc(hs);
    hb.writeUInt32LE(strLen + 4, 0);
    hb.writeUInt32LE(strLen, 4);
    hb.write(json, 8, strLen, 'utf8');

    const target = opts.out || path.join(tmp, 'app.patched.asar');
    const outFd = fs.openSync(target, 'w');
    fs.writeSync(outFd, pre); fs.writeSync(outFd, hb);
    for (const b of bodyParts) fs.writeSync(outFd, b);
    fs.fsyncSync(outFd); fs.closeSync(outFd);
    ok(`生成 ${target} (${(fs.statSync(target).size / 1024 / 1024).toFixed(2)} MB)，新 body ${pos} 字节`);

    // 8. 全量校验：新 asar 可解析、路径顺序一致、除目标外逐字节相同、目标为补丁后内容
    const B = readAsar(target);
    const bAll = walk(B.header, '', []);
    const bPacked = bAll.filter(f => !f.node.unpacked && !f.node.link);
    if (bAll.length !== all.length || !headerOrderMonotonic(bPacked)) { fs.closeSync(B.fd); die('新 asar 解析/顺序校验失败'); }
    let same = 0, diff = 0, bad = [];
    for (let i = 0; i < bPacked.length; i++) {
      if (bPacked[i].path !== packed[i].path) { fs.closeSync(B.fd); die('新旧 asar 路径顺序不一致 @' + i); }
      const a = readEntry(A, packed[i]), b = readEntry(B, bPacked[i]);
      const j = jobs.find(x => x.asarRel === packed[i].path);
      if (j) {
        if (sha(b) !== sha(j.newBuf)) bad.push('目标未生效: ' + packed[i].path); else diff++;
      } else if (sha(a) === sha(b)) same++; else bad.push('非目标文件被动过: ' + packed[i].path);
    }
    fs.closeSync(B.fd);
    if (bad.length) { bad.slice(0, 8).forEach(m => console.error('   ' + m)); die(`校验失败 ${bad.length} 项，未替换原文件`); }
    ok(`全量校验通过：${same} 个非目标文件逐字节一致，${diff} 个补丁文件已更新`);
    for (const [rel, marker] of MARKERS) {
      if (!fs.readFileSync(target).includes(Buffer.from(marker))) die('新 asar 中找不到标记 ' + marker);
    }

    // 9. 替换
    if (opts.out) { ok(`已输出到 ${opts.out}（未改动原文件，应用可继续运行）`); return; }

    if (opts.quit && isRunning()) quitApp();
    if (isRunning() && process.platform === 'win32') die('应用仍占用 asar，请先完全退出再重跑');

    let bak = null;
    if (opts.backup) {
      bak = `${asarPath}.bak-${new Date().toISOString().replace(/[-:T]/g, '').slice(0, 15)}`;
      fs.renameSync(asarPath, bak);
      info(`备份: ${bak}`);
    } else {
      fs.unlinkSync(asarPath);
    }
    try { fs.renameSync(target, asarPath); }
    catch (e) {
      if (bak) { fs.renameSync(bak, asarPath); }
      die(`替换失败已回滚: ${e.message}`);
    }
    ok('已替换 app.asar');

    // 10. 重启 + 健康检查
    if (opts.restart) {
      startApp(asarPath);
      setTimeout(() => {
        healthCheck(Number(process.env.DSH_DESKTOP_PORT) || DEFAULT_PORT);
        console.log(`${GREEN}[完成]${NC} 桌面版补丁已安装。回滚: 把 ${path.basename(bak || '<备份>')} 改名回 app.asar`);
      }, 6000);
    } else {
      ok(`补丁已安装（未自动重启）。备份: ${bak || '无'}`);
    }
  } finally {
    try { fs.rmSync(tmp, { recursive: true, force: true }); } catch (e) { /* 忽略 */ }
  }
}

main();
