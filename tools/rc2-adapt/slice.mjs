// 从文件里按锚点截取一个"以 { 开头、括号配平"的片段
import fs from 'node:fs';

export function sliceBalanced(text, startIdx) {
  // 从 startIdx 起找第一个 '{'，然后配平
  let i = text.indexOf('{', startIdx);
  if (i < 0) return null;
  const begin = i;
  let depth = 0;
  let inStr = null;      // 当前字符串引号
  let inTpl = 0;         // 模板字符串深度
  let inLineComment = false;
  let inBlockComment = false;
  for (; i < text.length; i++) {
    const c = text[i];
    const next = text[i + 1];
    if (inLineComment) { if (c === '\n') inLineComment = false; continue; }
    if (inBlockComment) { if (c === '*' && next === '/') { inBlockComment = false; i++; } continue; }
    if (inStr) {
      if (c === '\\') { i++; continue; }
      if (c === inStr) inStr = null;
      continue;
    }
    if (inTpl > 0) {
      if (c === '\\') { i++; continue; }
      if (c === '`') { inTpl--; continue; }
      continue;
    }
    if (c === '/' && next === '/') { inLineComment = true; i++; continue; }
    if (c === '/' && next === '*') { inBlockComment = true; i++; continue; }
    if (c === '"' || c === "'") { inStr = c; continue; }
    if (c === '`') { inTpl++; continue; }
    if (c === '{') depth++;
    else if (c === '}') { depth--; if (depth === 0) return { begin, end: i + 1, body: text.slice(begin, i + 1) }; }
  }
  return null;
}

if (process.argv[2] === 'probe') {
  const file = process.argv[3];
  const anchor = process.argv[4];
  const t = fs.readFileSync(file, 'utf8');
  const idx = t.indexOf(anchor);
  if (idx < 0) { console.log('锚点未找到'); process.exit(1); }
  console.log('锚点位置: ' + idx + ' / ' + t.length);
  console.log('前置 120 字符: ' + JSON.stringify(t.slice(Math.max(0, idx - 120), idx)));
  const s = sliceBalanced(t, idx);
  if (s) {
    console.log('片段长度: ' + s.body.length);
    console.log('前 200: ' + JSON.stringify(s.body.slice(0, 200)));
    console.log('后 200: ' + JSON.stringify(s.body.slice(-200)));
  } else console.log('配平失败');
}
