// 把 rc.2 压缩版 dsh-client-ui-chat/lib/client.js 改造成「带编辑按钮」的版本
// 大段代码直接从 rc.1 已适配版本(r1/build)搬运，避免手写出错
import fs from 'node:fs';

const SRC = 'C:/Users/86722/WorkBuddy/2026-10-28-16-36-57/_dsh_diag/r1/build/dsh-client-ui-chat/lib/client.js';
const DST = 'C:/Users/86722/WorkBuddy/2026-10-28-16-36-57/_dsh_diag/r2/build/dsh-client-ui-chat/lib/client.js';

const r1 = fs.readFileSync(SRC, 'utf8');
let t = fs.readFileSync(DST, 'utf8');

function sliceBetween(text, startAnchor, endAnchor) {
  const a = text.indexOf(startAnchor);
  const b = text.indexOf(endAnchor, a + 1);
  if (a < 0 || b < 0) throw new Error('切片失败: ' + startAnchor);
  return text.slice(a, b);
}

function replaceOnce(haystack, find, repl, label) {
  const n = haystack.split(find).length - 1;
  if (n !== 1) throw new Error(`[${label}] 锚点命中 ${n} 次（应为 1）`);
  return haystack.replace(find, repl);
}

let step = 0;
const log = (m) => console.log(++step + '. ' + m);

// ① EditPromptContext 定义
t = replaceOnce(t, 'const MOTION_TAIL_MS=800;',
  'const MOTION_TAIL_MS=800;const EditPromptContext=(0,react.createContext)(void 0);', 'context');
log('插入 EditPromptContext');

// ② ChatView 增加 editLastPrompt 入参
t = replaceOnce(t, 'dispatchInteraction,t,fileDrag}){',
  'dispatchInteraction,editLastPrompt,t,fileDrag}){', 'ChatView props');
log('ChatView 增加 editLastPrompt');

// ③ lastUserKey（从 rc.1 已适配版搬运）
const r1Last = sliceBetween(r1, 'const lastUserKey = (0, react.useMemo)', 'const deferCompletedTurns');
const lastUserCompact = r1Last
  .replace(/\s*\n\s*/g, '')
  .replace(/\(0, react\.useMemo\)/g, '(0,react.useMemo)')
  .trim();
t = replaceOnce(t, 'const nodeStore=useChat(s=>s.nodes);',
  'const nodeStore=useChat(s=>s.nodes);' + lastUserCompact, 'lastUserKey');
log('插入 lastUserKey');

// ④ flow 插槽外包 Provider
const OLD_FLOW = 'children:renderSlot(`conversation.chat.flow`,{entries,pendingInputs,lastInputTurn,deferCollapse,cwd,openFile:requestOpenFile,inspectCall,forkAt,loadImage},{hookContext:flowContext})}';
const NEW_FLOW = 'children:(0,react_jsx_runtime.jsx)(EditPromptContext.Provider,{value:{editLastPrompt,lastUserKey},children:renderSlot(`conversation.chat.flow`,{entries,pendingInputs,lastInputTurn,deferCollapse,cwd,openFile:requestOpenFile,inspectCall,forkAt,loadImage},{hookContext:flowContext})})}';
t = replaceOnce(t, OLD_FLOW, NEW_FLOW, 'flow provider');
log('flow 插槽外包 EditPromptContext.Provider');

// ⑤ 整段替换 UserMessageNodeView（从 rc.1 已适配版搬运）
const r1Comp = sliceBetween(r1, 'const UserMessageNodeView = (0, react.memo)', 'ContextMessageNodeView');
const compCompact = r1Comp
  .replace(/\s*\n\s*/g, '')
  .replace(/\(0, react\.useMemo\)/g, '(0,react.useMemo)')
  .replace(/\(0, react\.useState\)/g, '(0,react.useState)')
  .replace(/\(0, react\.useContext\)/g, '(0,react.useContext)')
  .replace(/\(0, react_jsx_runtime\.jsxs?\)/g, (m) => m.replace(' ', ''))
  .replace(/const $/, '')
  .trimEnd();
const dstComp = sliceBetween(t, 'const UserMessageNodeView=', 'ContextMessageNodeView');
if (!dstComp.trimEnd().endsWith('const')) throw new Error('目标组件边界异常');
const dstCompBody = dstComp.trimEnd().slice(0, -'const'.length);
t = replaceOnce(t, dstCompBody, compCompact, 'UserMessageNodeView');
log('替换 UserMessageNodeView（' + dstCompBody.length + ' → ' + compCompact.length + ' 字符）');

// ⑥ binding 注入 editLastPrompt
t = replaceOnce(t, 'forkAt:seq=>{',
  'editLastPrompt:text=>session.editLastPrompt(text).then(result=>{if(!result.ok)throw new Error(`editLastPrompt failed: ${result.error?.code??``}: ${result.error?.message??``}`);return result}),forkAt:seq=>{',
  'binding editLastPrompt');
log('binding 注入 editLastPrompt');

// ⑦ 中英文案
t = replaceOnce(t, '"message.extraBlock":`附加内容块`,',
  '"message.extraBlock":`附加内容块`,"message.editPrompt":`编辑这条消息`,"message.saveEdit":`保存并重新生成`,"message.cancelEdit":`取消`,"message.editing":`重新生成中…`,', 'zh locale');
t = replaceOnce(t, '"message.extraBlock":`Extra content block`,',
  '"message.extraBlock":`Extra content block`,"message.editPrompt":`Edit this message`,"message.saveEdit":`Save and regenerate`,"message.cancelEdit":`Cancel`,"message.editing":`Regenerating…`,', 'en locale');
log('补入中英文案');

// ⑧ messageDefinition.match 允许 replacement 事件
const OLD_MATCH = 'match:event=>{if(event.type===`user/message`)return isAppendSurfaceEvent(event)&&!isCompactionCheckpoint(event)?{id:String(event.data.id),role:`start`}:null;return null}';
const NEW_MATCH = 'match:event=>event.type===`user/message`&&(isAppendSurfaceEvent(event)||isReplacementSurfaceEvent(event)&&event.data.source?.kind===`user`)&&!isCompactionCheckpoint(event)?{id:String(event.data.id),role:`start`}:null';
t = replaceOnce(t, OLD_MATCH, NEW_MATCH, 'messageDefinition.match');
log('messageDefinition.match 允许 replacement');

fs.writeFileSync(DST, t);
console.log('\n完成，文件字符数: ' + t.length);
