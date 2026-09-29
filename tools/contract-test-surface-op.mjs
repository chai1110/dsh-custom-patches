#!/usr/bin/env node
/**
 * surfaceOp 契约测试（两层，零副作用）
 *
 * 背景（2026-09-29）：「编辑最后一条消息」长期失败，真机报
 *   session event "user/message" carries an invalid replace surfaceOp
 * 根因是补丁把 replace op 写成 `{ op, start, end }`，
 * 而官方 `isReplaceOp` 要求**恰好三个键** `{ op, startSeq, endSeq }`。
 *
 * 本脚本用官方自己的代码验证修复，**不起 DSH、不落盘、不碰任何真实会话**。
 *
 *   阶段 1  校验层：直接喂形状给官方校验函数（快，稳，证明字段名）
 *   阶段 2  端到端：真实构造一个内存 Session，跑一次 session.append(..., { surfaceOp })
 *                  —— 这正是「编辑最后一条消息」在服务端唯一会失败的那一步
 *
 * 用法:
 *   node tools/contract-test-surface-op.mjs
 *   node tools/contract-test-surface-op.mjs /path/to/@deepseek-ai
 *   DSH_PLUGIN_ROOT=/path/to/@deepseek-ai node tools/contract-test-surface-op.mjs
 *
 * 退出码: 0 = 全部符合预期；1 = 有不符合预期的项（字段名可能又被改坏了）
 */
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const REL_SURFACE = path.join('dsh-session', 'lib', 'types', 'surface.js');
const REL_INDEX = path.join('dsh-session', 'lib', 'index.js');

/** 依次探测常见安装位置，返回第一个含 dsh-session 的 @deepseek-ai 目录。 */
function locatePluginRoot() {
  const explicit = process.argv[2] ?? process.env.DSH_PLUGIN_ROOT;
  const roots = [];
  if (explicit !== undefined && explicit !== '') {
    roots.push(explicit, path.join(explicit, 'node_modules', '@deepseek-ai'));
  }
  const home = os.homedir();
  for (const prefix of ['.local/node-v24', '.local/node', '.npm-global']) {
    const base = path.join(home, prefix, 'lib', 'node_modules', '@deepseek-ai');
    roots.push(base, path.join(base, 'dsh', 'node_modules', '@deepseek-ai'));
  }
  roots.push(path.join(home, '.dsh', 'profiles', 'web', 'node_modules', '@deepseek-ai'));

  for (const root of roots) {
    if (fs.existsSync(path.join(root, REL_SURFACE)) && fs.existsSync(path.join(root, REL_INDEX))) return root;
  }
  return undefined;
}

const pluginRoot = locatePluginRoot();
if (pluginRoot === undefined) {
  console.error('[x] 找不到官方的 dsh-session。请显式指定 @deepseek-ai 目录：');
  console.error('      node tools/contract-test-surface-op.mjs /path/to/@deepseek-ai');
  process.exit(1);
}
console.log('[i] 官方插件根: ' + pluginRoot);
console.log('');

const GOOD = { op: 'replace', startSeq: 1, endSeq: 2 }; // 修复后的形状
const BAD = { op: 'replace', start: 1, end: 2 };        // 修复前的形状（应被拒）

let failures = 0;

// ─────────────────────────── 阶段 1：校验层 ───────────────────────────
console.log('── 阶段 1：官方校验函数 ──');

const surfaceModule = await import(pathToFileURL(path.join(pluginRoot, REL_SURFACE)).href);
const { validateSurfaceMetadata } = surfaceModule;
if (typeof validateSurfaceMetadata !== 'function') {
  console.error('[x] surface.js 没有导出 validateSurfaceMetadata —— 官方版本可能已变，请人工核对。');
  process.exit(1);
}

const base = { type: 'user/message', seq: 100, data: {}, sourceEventSeqs: [1, 2] };
for (const [label, op, expectAccept] of [
  ['修复后  { op, startSeq, endSeq }', GOOD, true],
  ['修复前  { op, start, end }      ', BAD, false],
]) {
  let accepted = false;
  let detail = '';
  try {
    const result = validateSurfaceMetadata({ ...base, surfaceOp: op });
    accepted = true;
    detail = '返回 ' + JSON.stringify(result);
  } catch (error) {
    detail = error.message;
  }
  const pass = accepted === expectAccept;
  if (!pass) failures += 1;
  console.log(`  [${pass ? 'OK  ' : 'FAIL'}] ${label} -> ${accepted ? '通过官方校验' : '被拒'}  ${detail}`);
}

// ───────────────────── 阶段 2：真实 Session.append 端到端 ─────────────────────
console.log('');
console.log('── 阶段 2：真实 Session.append（内存，不落盘）──');

const indexModule = await import(pathToFileURL(path.join(pluginRoot, REL_INDEX)).href);
const { Session } = indexModule;
if (typeof Session !== 'function') {
  console.log('  [SKIP] 该版本没有导出 Session —— 跳过端到端阶段（阶段 1 已通过）。');
} else {
  const userMessage = (id, text) => ({
    id,
    content: [{ type: 'text', text }],
    source: { kind: 'user', rpcId: 'rpc-' + id },
  });

  /** 建一个含「一条提问 + 一条回复」的会话，返回 { session, lastSeq }。 */
  const seedSession = () => {
    const session = new Session('contract-test');
    session.append('user/message', userMessage('u1', '第一条提问'), { surfaceOp: 'append' });
    session.append('assistant/message', { id: 'a1', content: [{ type: 'text', text: '第一条回复' }] }, { surfaceOp: 'append' });
    return { session, lastSeq: session.surface.nodes[session.surface.nodes.length - 1] };
  };

  // 2a：修复后的形状应当被接受，且**确实替换掉**了被指向的那条
  try {
    const { session, lastSeq } = seedSession();
    const before = [...session.surface.nodes];
    session.append('user/message', userMessage('u2', '改过的提问'), {
      surfaceOp: { op: 'replace', startSeq: lastSeq, endSeq: lastSeq },
      sourceEventSeqs: [lastSeq],
    });
    const after = [...session.surface.nodes];
    const replaced = !after.includes(lastSeq) && after.length === before.length;
    if (replaced) {
      console.log(`  [OK  ] 修复后形状 append 成功，且被替换的事件已从 surface 移除  ${JSON.stringify(before)} -> ${JSON.stringify(after)}`);
    } else {
      failures += 1;
      console.log(`  [FAIL] append 未报错，但替换语义不对  ${JSON.stringify(before)} -> ${JSON.stringify(after)}`);
    }
  } catch (error) {
    failures += 1;
    console.log('  [FAIL] 修复后形状被拒: ' + error.message);
  }

  // 2b：修复前的形状应当被拒，且报错文案与真机一致
  try {
    const { session, lastSeq } = seedSession();
    session.append('user/message', userMessage('u2', '改过的提问'), {
      surfaceOp: { op: 'replace', start: lastSeq, end: lastSeq },
      sourceEventSeqs: [lastSeq],
    });
    failures += 1;
    console.log('  [FAIL] 修复前形状竟然通过了（预期被拒）');
  } catch (error) {
    const expected = error.message.includes('invalid replace surfaceOp');
    if (expected) {
      console.log('  [OK  ] 修复前形状被拒，文案与真机一致: ' + error.message);
    } else {
      failures += 1;
      console.log('  [FAIL] 被拒了，但报错文案不是预期的那条: ' + error.message);
    }
  }
}

console.log('');
if (failures === 0) {
  console.log('[OK] 契约全部符合预期 —— startSeq/endSeq 可用，start/end 被拒，替换语义正确。');
  process.exit(0);
}
console.log(`[x] ${failures} 项不符合预期 —— 补丁的 surfaceOp 字段名或替换语义可能又被改坏了。`);
process.exit(1);
