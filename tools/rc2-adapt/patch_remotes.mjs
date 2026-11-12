// 把 rc.1 补丁里新增的代码块，按锚点插入 rc.2 的压缩版 api-remotes/client.js
import fs from 'node:fs';

const PATCH = 'C:/Users/86722/dsh-custom-patches/patches/api-remotes/dsh-api-remotes-lib-client.js.patch';
const TARGET = 'C:/Users/86722/WorkBuddy/2026-10-28-16-36-57/_dsh_diag/r2/build/dsh-api-remotes/lib/client.js';

// 每个 hunk 的插入锚点（插在该字符串之前）
const ANCHORS = [
  'let _deepseek_ai_dsh_api_session_controller_session_rename_parameter_0$schema$value;',
  'let _deepseek_ai_dsh_api_session_controller_session_rename_parameter_0_strict$schema$value;',
  '"session/rename":{',
];

const patch = fs.readFileSync(PATCH, 'utf8').split('\n');
const hunks = [];
let cur = null;
for (const line of patch) {
  if (line.startsWith('@@')) { cur = []; hunks.push(cur); continue; }
  if (cur && line.startsWith('+')) cur.push(line.slice(1));
}
if (hunks.length !== ANCHORS.length) {
  console.error('hunk 数 ' + hunks.length + ' 与锚点数 ' + ANCHORS.length + ' 不符');
  process.exit(1);
}

let text = fs.readFileSync(TARGET, 'utf8');
if (text.includes('session/editLastPrompt')) { console.error('已存在，跳过'); process.exit(1); }

for (let i = 0; i < ANCHORS.length; i++) {
  const anchor = ANCHORS[i];
  const n = text.split(anchor).length - 1;
  if (n !== 1) { console.error('锚点 ' + i + ' 命中 ' + n + ' 次，放弃'); process.exit(1); }
  const block = hunks[i].join('\n');
  text = text.replace(anchor, block + '\n' + anchor);
  console.log('hunk ' + (i + 1) + ' 插入 ' + hunks[i].length + ' 行');
}

fs.writeFileSync(TARGET, text);
console.log('完成，文件字符数: ' + text.length);
