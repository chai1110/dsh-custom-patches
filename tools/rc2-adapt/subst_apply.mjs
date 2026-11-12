// 用「去空白映射」把行级补丁自动套到压缩单行文件上
// 原理：把目标文件的空白全部去掉并记录原始偏移；锚点用补丁里的上下文行（去空白后）定位，
//       命中唯一时映射回原始偏移再插入/替换。
import fs from 'node:fs';

const PATCH = process.argv[2];
const TARGET = process.argv[3];

const raw = fs.readFileSync(TARGET, 'utf8');

// —— 去空白 + 偏移映射 ——
const map = [];            // stripped[i] 对应 raw 的下标
let stripped = '';
for (let i = 0; i < raw.length; i++) {
  const c = raw[i];
  if (c === ' ' || c === '\t' || c === '\n' || c === '\r') continue;
  stripped += c;
  map.push(i);
}
const toRaw = (si) => (si >= map.length ? raw.length : map[si]);
const strip = (s) => s.replace(/[ \t\r\n]+/g, '');

function countOcc(hay, needle) {
  if (needle === '') return 0;
  let n = 0, i = 0;
  while ((i = hay.indexOf(needle, i)) !== -1) { n++; i += 1; }
  return n;
}

// —— 解析补丁 ——
const lines = fs.readFileSync(PATCH, 'utf8').split('\n');
const hunks = [];
let cur = null;
for (const l of lines) {
  if (l.startsWith('@@')) { cur = { lines: [], added: 0, removed: 0 }; hunks.push(cur); continue; }
  if (!cur) continue;
  if (l.startsWith('---') || l.startsWith('+++') || l.startsWith('\\')) continue;
  const tag = l[0];
  const body = l.slice(1);
  cur.lines.push({ tag, body });
  if (tag === '+') cur.added++;
  if (tag === '-') cur.removed++;
}

let ops = [];   // {atStripped, delLen, text}
let failed = [];

hunks.forEach((h, idx) => {
  const adds = h.lines.filter((x) => x.tag === '+').map((x) => x.body).join('\n');
  const dels = h.lines.filter((x) => x.tag === '-').map((x) => x.body).join('\n');

  // 找上下文锚点：优先用「插入块之前的最后一行上下文」，否则用第一行上下文
  const firstAdd = h.lines.findIndex((x) => x.tag === '+');
  let before = null;
  for (let i = firstAdd - 1; i >= 0; i--) if (h.lines[i].tag === ' ') { before = h.lines[i].body; break; }
  let after = null;
  for (let i = h.lines.findIndex((x) => x.tag === '+'); i < h.lines.length; i++) {
    if (h.lines[i].tag === ' ') { after = h.lines[i].body; break; }
  }

  if (dels !== '') {
    // 替换型：定位被删代码（去空白），整体替换成新代码
    const d = strip(dels);
    const n = countOcc(stripped, d);
    if (n !== 1) { failed.push({ idx, reason: '删除块命中 ' + n + ' 次' }); return; }
    const at = stripped.indexOf(d);
    ops.push({ atStripped: at, delLen: d.length, text: adds, idx });
    return;
  }

  // 插入型
  for (const cand of [before, after]) {
    if (!cand) continue;
    const c = strip(cand);
    if (c.length < 8) continue;
    const n = countOcc(stripped, c);
    if (n !== 1) continue;
    const at = stripped.indexOf(c);
    const anchorEnd = cand === before ? at + c.length : at;
    ops.push({ atStripped: anchorEnd, delLen: 0, text: adds, idx });
    return;
  }
  failed.push({ idx, reason: '上下文锚点不唯一或过短' });
});

console.log('hunk 共 ' + hunks.length + ' 个；可自动定位 ' + ops.length + ' 个；失败 ' + failed.length);
for (const f of failed) console.log('  hunk #' + (f.idx + 1) + ' 失败: ' + f.reason);

if (process.argv[4] === '--apply') {
  ops.sort((a, b) => b.atStripped - a.atStripped);   // 从后往前改，避免偏移失效
  let out = raw;
  for (const op of ops) {
    const s = toRaw(op.atStripped);
    const delRawLen = op.delLen === 0 ? 0 : toRaw(op.atStripped + op.delLen) - s;
    out = out.slice(0, s) + op.text + out.slice(s + delRawLen);
  }
  fs.writeFileSync(TARGET, out);
  console.log('已写入，字符数 ' + out.length);
}
