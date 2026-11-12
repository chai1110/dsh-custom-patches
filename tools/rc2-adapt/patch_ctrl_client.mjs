// 在 rc.2 压缩版 dsh-api-session-controller/lib/client.js 中插入 editLastPrompt 方法
import fs from 'node:fs';

const P = 'C:/Users/86722/WorkBuddy/2026-10-28-16-36-57/_dsh_diag/r2/build/dsh-api-session-controller/lib/client.js';
let text = fs.readFileSync(P, 'utf8');

const ANCHOR = 'async prompt(content,mode,signal,requestId){this.promptError=null;';
const INSERT = 'async editLastPrompt(text){return this.remote.session.editLastPrompt({requestId:randomUUID(),sessionId:this.sessionId,text})}';

const n = text.split(ANCHOR).length - 1;
if (n !== 1) { console.error('锚点命中 ' + n + ' 次，放弃'); process.exit(1); }
if (text.includes('editLastPrompt')) { console.error('已存在 editLastPrompt，跳过'); process.exit(1); }

text = text.replace(ANCHOR, INSERT + ANCHOR);
fs.writeFileSync(P, text);
console.log('已插入 editLastPrompt 方法');
console.log('文件大小: ' + text.length + ' 字符');
