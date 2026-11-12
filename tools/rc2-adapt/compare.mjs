// 对比 rc.1 与 rc.2 官方文件：去掉所有空白后长度、随机片段命中率
import fs from 'node:fs';

const FILES = [
  'dsh-client-ui-chat/lib/client.js',
  'dsh-client-ui-conversation/lib/client.js',
  'dsh-api-remotes/lib/client.js',
  'dsh-api-session-controller/lib/client.js',
  'dsh-api-session-controller/lib/index.js',
  'dsh-agent-loop/lib/index.js',
];

const R1 = 'C:/Users/86722/WorkBuddy/2026-10-28-16-36-57/_dsh_diag/r1/work/';
const R2 = 'C:/Users/86722/WorkBuddy/2026-10-28-16-36-57/_dsh_diag/r2/work/';

const strip = (s) => s.replace(/\s+/g, '');

for (const rel of FILES) {
  const a = fs.readFileSync(R1 + rel, 'utf8');
  const b = fs.readFileSync(R2 + rel, 'utf8');
  const sa = strip(a), sb = strip(b);

  // 随机取 30 个 60 字符片段，看有多少能在另一边找到
  let hits = 0;
  const N = 30;
  for (let i = 0; i < N; i++) {
    const start = Math.floor(Math.random() * Math.max(1, sa.length - 60));
    const piece = sa.substr(start, 60);
    if (sb.includes(piece)) hits++;
  }

  const la = a.split('\n').length, lb = b.split('\n').length;
  console.log(
    rel.replace('/lib/client.js', '').replace('/lib/index.js', '') +
    ' | 行数 ' + la + '→' + lb +
    ' | 去空白字节 ' + sa.length + '→' + sb.length +
    ' | 变化 ' + (100 * (sb.length - sa.length) / sa.length).toFixed(1) + '%' +
    ' | 片段命中 ' + hits + '/' + N
  );
}
