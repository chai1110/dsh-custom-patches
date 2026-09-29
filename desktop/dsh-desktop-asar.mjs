// dsh-desktop-asar.mjs — 针对 Electron 桌面版 app.asar 的读取 / 外科式改写 / 校验工具。
//
// 为什么需要它：桌面版（DeepSeek Harness.app）的 dsh 运行时被封在 **签名过的 app.asar** 里，
// 不受 profile 目录或任何环境变量影响（安装锚点硬指向 asar 内部）。要给它打补丁，只能改 asar。
//
// 改写策略（最小爆炸半径）：
//   原数据区原样保留、逐字节不动；只把被替换的文件追加到数据区末尾，
//   并只修改这几个条目的 size/offset/integrity。其余条目一个字节都不动。
//
// 两个必须遵守的格式细节（踩过坑）：
//   1. 头部 JSON 里 offset 是**字符串**（size 是数字）。写成数字会被 @electron/asar 拒绝：
//      `Invalid archive header ... "offset" must be a string, got number`。
//   2. 每个条目带 integrity 元数据，替换内容后必须重算，否则完整性校验会失败。
//
// 用法：
//   node dsh-desktop-asar.mjs cat    <asar> <内部路径>            # 输出文件内容到 stdout
//   node dsh-desktop-asar.mjs rewrite <源asar> <目标asar> <map.json>
//   node dsh-desktop-asar.mjs verify  <旧asar> <新asar> <map.json> # 逐条目比对
//   node dsh-desktop-asar.mjs list    <asar> [前缀]                # 列出条目
//
// map.json 形如 { "<asar 内相对路径>": "<新内容文件绝对路径>", ... }

import fs from 'node:fs';
import crypto from 'node:crypto';

const INTEGRITY_BLOCK_SIZE = 4 * 1024 * 1024;

/** 与 @electron/asar 的 lib/integrity 一致：分块 sha256，再对各块哈希的原始字节做一次 sha256。 */
function computeIntegrity(buf) {
  const blocks = [];
  for (let i = 0; i < buf.length; i += INTEGRITY_BLOCK_SIZE) {
    const slice = buf.subarray(i, Math.min(i + INTEGRITY_BLOCK_SIZE, buf.length));
    blocks.push(crypto.createHash('sha256').update(slice).digest('hex'));
  }
  const h = crypto.createHash('sha256');
  for (const b of blocks) h.update(Buffer.from(b, 'hex'));
  return { algorithm: 'SHA256', hash: h.digest('hex'), blockSize: INTEGRITY_BLOCK_SIZE, blocks };
}

function readHeader(fd) {
  const head = Buffer.alloc(16);
  fs.readSync(fd, head, 0, 16, 0);
  const magic = head.readUInt32LE(0);
  if (magic !== 4) throw new Error('非法 asar 头: head[0..3]=' + magic);
  const headerBufLen = head.readUInt32LE(4);
  const jsonLen = head.readUInt32LE(12);
  const jb = Buffer.alloc(jsonLen);
  fs.readSync(fd, jb, 0, jsonLen, 16);
  const jsonText = jb.toString('utf8');
  const header = JSON.parse(jsonText);
  // 键序安全检查：只有往返完全一致才允许重建头部
  if (JSON.stringify(header) !== jsonText) {
    throw new Error('头部 JSON 往返不一致（可能存在纯数字键），放弃改写');
  }
  return { header, headerBufLen, jsonLen, jsonText, dataStart: 8 + headerBufLen };
}

function walk(node, prefix, out) {
  for (const [name, val] of Object.entries(node.files || {})) {
    const p = prefix ? prefix + '/' + name : name;
    if (val.files) walk(val, p, out);
    else out.set(p, val);
  }
  return out;
}

function openAsar(p) {
  const fd = fs.openSync(p, 'r');
  const { header, headerBufLen, jsonLen, jsonText, dataStart } = readHeader(fd);
  const entries = walk(header, '', new Map());
  return { fd, header, headerBufLen, jsonLen, jsonText, dataStart, entries, size: fs.fstatSync(fd).size };
}

function hashEntry(a, e) {
  if (e.unpacked) return 'UNPACKED';
  if (Number(e.size) === 0) return crypto.createHash('sha256').update(Buffer.alloc(0)).digest('hex');
  const b = Buffer.alloc(Number(e.size));
  fs.readSync(a.fd, b, 0, b.length, a.dataStart + Number(e.offset));
  return crypto.createHash('sha256').update(b).digest('hex');
}

const [, , mode, ...args] = process.argv;

if (mode === 'cat') {
  const [asarPath, inner] = args;
  const a = openAsar(asarPath);
  const e = a.entries.get(inner);
  if (!e) { console.error('找不到条目: ' + inner); process.exit(1); }
  if (e.unpacked) { console.error('条目是 unpacked，内容在 .asar.unpacked 下: ' + inner); process.exit(1); }
  const b = Buffer.alloc(Number(e.size));
  fs.readSync(a.fd, b, 0, b.length, a.dataStart + Number(e.offset));
  process.stdout.write(b);
  fs.closeSync(a.fd);
} else if (mode === 'list') {
  const [asarPath, prefix = ''] = args;
  const a = openAsar(asarPath);
  const hits = [...a.entries.keys()].filter((p) => p.startsWith(prefix));
  console.log('条目总数: ' + a.entries.size + '  匹配前缀 "' + prefix + '": ' + hits.length);
  for (const p of hits.slice(0, 200)) console.log('  ' + p);
  fs.closeSync(a.fd);
} else if (mode === 'rewrite') {
  const [srcPath, dstPath, mapPath] = args;
  const replaceMap = JSON.parse(fs.readFileSync(mapPath, 'utf8'));
  const a = openAsar(srcPath);
  const dataRegionSize = a.size - a.dataStart;

  console.log('源: ' + srcPath);
  console.log('  大小 ' + a.size + '  headerBufLen ' + a.headerBufLen + '  dataStart ' + a.dataStart + '  数据区 ' + dataRegionSize);

  let cursor = dataRegionSize;
  const blobs = [];
  for (const [p, file] of Object.entries(replaceMap)) {
    const node = a.entries.get(p);
    if (!node) throw new Error('asar 中找不到条目: ' + p);
    if (node.unpacked) throw new Error('条目是 unpacked，不能内联替换: ' + p);
    if (node.link !== undefined) throw new Error('条目是 link: ' + p);
    const buf = fs.readFileSync(file);
    const oldOffset = Number(node.offset), oldSize = Number(node.size);
    node.offset = String(cursor);        // 必须字符串
    node.size = buf.length;              // 数字
    node.integrity = computeIntegrity(buf);
    blobs.push({ p, buf });
    console.log('  ' + p.replace('dsh/node_modules/@deepseek-ai/', '') +
      '   offset ' + oldOffset + ' -> ' + cursor + '   size ' + oldSize + ' -> ' + buf.length);
    cursor += buf.length;
  }

  const jsonText = JSON.stringify(a.header);
  const jsonLen = Buffer.byteLength(jsonText, 'utf8');
  const pad = (4 - (jsonLen % 4)) % 4;
  const headerBufLen = 8 + jsonLen + pad;
  const head = Buffer.alloc(16);
  head.writeUInt32LE(4, 0);
  head.writeUInt32LE(headerBufLen, 4);
  head.writeUInt32LE(headerBufLen - 4, 8);
  head.writeUInt32LE(jsonLen, 12);

  const out = fs.openSync(dstPath, 'w');
  fs.writeSync(out, head, 0, 16);
  const jsonOut = Buffer.alloc(headerBufLen - 8);
  jsonOut.write(jsonText, 0, 'utf8');
  fs.writeSync(out, jsonOut, 0, jsonOut.length);

  const newDataStart = 8 + headerBufLen;
  const CHUNK = 4 * 1024 * 1024;
  const buf = Buffer.alloc(CHUNK);
  let copied = 0, pos = a.dataStart;
  while (copied < dataRegionSize) {
    const n = Math.min(CHUNK, dataRegionSize - copied);
    fs.readSync(a.fd, buf, 0, n, pos);
    fs.writeSync(out, buf, 0, n);
    copied += n; pos += n;
  }
  let appended = 0;
  for (const b of blobs) { fs.writeSync(out, b.buf, 0, b.buf.length); appended += b.buf.length; }
  fs.closeSync(out);
  fs.closeSync(a.fd);

  const outSize = fs.statSync(dstPath).size;
  const expect = newDataStart + dataRegionSize + appended;
  console.log('新 dataStart ' + newDataStart + '（偏移 ' + (newDataStart - a.dataStart) + '），追加 ' + appended + ' 字节');
  console.log('输出 ' + dstPath + '  ' + outSize + ' 字节' + (outSize === expect ? '  ✓' : '  ✗ 期望 ' + expect));
  if (outSize !== expect) process.exit(1);
} else if (mode === 'verify') {
  const [oldPath, newPath, mapPath] = args;
  const replaced = new Set(Object.keys(JSON.parse(fs.readFileSync(mapPath, 'utf8'))));
  const A = openAsar(oldPath), B = openAsar(newPath);
  if (A.entries.size !== B.entries.size) {
    console.log('❌ 条目数不一致: ' + A.entries.size + ' vs ' + B.entries.size); process.exit(1);
  }
  let same = 0, targetOk = 0;
  const missing = [], unexpected = [], targetBad = [];
  for (const [p, ea] of A.entries) {
    const eb = B.entries.get(p);
    if (!eb) { missing.push(p); continue; }
    const ha = hashEntry(A, ea), hb = hashEntry(B, eb);
    if (replaced.has(p)) {
      if (ha === hb) targetBad.push(p); else targetOk++;
    } else if (ha === hb && Number(ea.size) === Number(eb.size)) same++;
    else unexpected.push(p);
  }
  for (const p of B.entries.keys()) if (!A.entries.has(p)) unexpected.push('新增: ' + p);
  console.log('未改动且哈希一致: ' + same + ' / ' + (A.entries.size - replaced.size));
  console.log('预期替换: ' + targetOk + ' / ' + replaced.size);
  console.log('缺失: ' + missing.length + '   意外变化: ' + unexpected.length);
  for (const x of [...missing, ...unexpected, ...targetBad].slice(0, 10)) console.log('   ' + x);
  fs.closeSync(A.fd); fs.closeSync(B.fd);
  const ok = same === A.entries.size - replaced.size && targetOk === replaced.size &&
    missing.length === 0 && unexpected.length === 0;
  console.log(ok ? '\n✅ 通过：只有预期条目被替换，其余全部字节一致' : '\n❌ 未通过');
  process.exit(ok ? 0 : 1);
} else {
  console.error('用法: node dsh-desktop-asar.mjs <cat|list|rewrite|verify> ...');
  process.exit(2);
}
