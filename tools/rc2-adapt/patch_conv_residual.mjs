// 把「编辑重发后残留」修复（deadRanges / wholeTurnShadowed）套到 rc.2 压缩版
import fs from 'node:fs';

const TARGET = 'C:/Users/86722/WorkBuddy/2026-10-28-16-36-57/_dsh_diag/r2/build/dsh-client-ui-conversation/lib/client.js';
const PATCH = 'C:/Users/86722/dsh-custom-patches/patches/client-ui-conversation/dsh-client-ui-conversation-lib-client.js.patch';

// 从补丁第 3 个 hunk 取新增块
const lines = fs.readFileSync(PATCH, 'utf8').split('\n');
let h = 0;
const adds = [];
for (const l of lines) {
  if (l.startsWith('@@')) { h++; continue; }
  if (h === 3 && l.startsWith('+')) adds.push(l.slice(1));
}
if (adds.length < 30) { console.error('hunk3 提取失败，只拿到 ' + adds.length + ' 行'); process.exit(1); }

let t = fs.readFileSync(TARGET, 'utf8');
const ANCHOR = 'this.locationIndex.rebuild(sorted);';
const n = t.split(ANCHOR).length - 1;
if (n !== 1) { console.error('锚点命中 ' + n + ' 次，放弃'); process.exit(1); }
if (t.includes('wholeTurnShadowed')) { console.error('已存在，跳过'); process.exit(1); }

t = t.replace(ANCHOR, adds.join('\n'));
fs.writeFileSync(TARGET, t);
console.log('已套用 deadRanges 修复（' + adds.length + ' 行）');
console.log('文件字符数: ' + t.length);
