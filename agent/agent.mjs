// Jarvis agent bridge: Claude Agent SDK <-> JSON lines on stdin/stdout.
// in:  prompt{id,text} | confirm{id,allow} | interrupt | new_session
// out: ready | partial_text | tool_call | file_changed | need_confirmation | done | error
import { query } from '@anthropic-ai/claude-agent-sdk';
import { createInterface } from 'node:readline';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { confirmQuestion } from './policy.mjs';

const VAULT = process.env.JARVIS_VAULT ?? process.cwd();
const STATE = process.env.JARVIS_STATE ?? path.join(os.homedir(), 'Library/Application Support/Jarvis/session.json');
fs.mkdirSync(path.dirname(STATE), { recursive: true });
const STYLE = `Sei Jarvis, l'assistente vocale del secondo cervello. Rispondi in italiano, dai del tu, tono asciutto.
La risposta viene letta ad alta voce fino alla prima riga vuota: apri con al massimo due frasi brevi, senza markdown né elenchi.
Dettagli, liste e link vanno dopo una riga vuota: verranno solo mostrati a schermo.`;

const send = (o) => process.stdout.write(JSON.stringify(o) + '\n');
const today = () => new Date().toLocaleDateString('sv'); // YYYY-MM-DD, local time
const readState = () => { try { return JSON.parse(fs.readFileSync(STATE, 'utf8')); } catch { return null; } };
const summary = (i = {}) => String(i.file_path ?? i.command ?? i.skill ?? i.pattern ?? i.url ?? i.query ?? i.description ?? '').slice(0, 140);

// Minimal async queue feeding the SDK's streaming input mode.
function channel() {
  const items = []; let wake = null; let closed = false;
  return {
    push(x) { items.push(x); wake?.(); },
    close() { closed = true; wake?.(); },
    async *[Symbol.asyncIterator]() {
      for (;;) {
        while (items.length) yield items.shift();
        if (closed) return;
        await new Promise((r) => (wake = r)); wake = null;
      }
    },
  };
}

const pending = new Map(); // confirmation id -> resolve(bool)
let seq = 0;
function ask(question) {
  const id = `c${++seq}`;
  send({ type: 'need_confirmation', id, question });
  return new Promise((resolve) => pending.set(id, resolve));
}
function cancelPending() { for (const r of pending.values()) r(false); pending.clear(); }

let q, input, day, turnId = null;

function start() {
  const saved = readState();
  day = today();
  input = channel();
  q = query({
    prompt: input,
    options: {
      cwd: VAULT,
      resume: saved?.day === day ? saved.id : undefined,
      settingSources: ['user', 'project', 'local'],
      includePartialMessages: true,
      systemPrompt: { type: 'preset', preset: 'claude_code', append: STYLE },
      pathToClaudeCodeExecutable: process.env.JARVIS_CLAUDE || undefined,
      // Tools the vault settings don't pre-allow. Voice confirmation is only for destructive actions
      // (PreToolUse hook below); settings "deny" rules still apply before this is called.
      canUseTool: async (tool, toolInput) => tool === 'AskUserQuestion'
        ? { behavior: 'deny', message: "Sei un assistente vocale: fai la domanda nel testo della risposta, l'utente risponde a voce." }
        : { behavior: 'allow', updatedInput: toolInput },
      hooks: {
        // Runs even for pre-allowed tools: enforces the vault's "ask before destroying" rule.
        PreToolUse: [{ timeout: 600, hooks: [async (h) => {
          const question = confirmQuestion(h.tool_name, h.tool_input, VAULT);
          if (!question) return {};
          const allow = await ask(question);
          return { hookSpecificOutput: { hookEventName: 'PreToolUse', permissionDecision: allow ? 'allow' : 'deny', permissionDecisionReason: allow ? 'Confermato a voce' : "L'utente ha rifiutato." } };
        }] }],
        PostToolUse: [{ matcher: 'Write|Edit|MultiEdit|NotebookEdit', hooks: [async (h) => {
          send({ type: 'file_changed', path: h.tool_input?.file_path ?? h.tool_input?.notebook_path, op: h.tool_name });
          return {};
        }] }],
      },
    },
  });
  pump(q);
}

async function pump(current) {
  try {
    for await (const m of current) handle(m);
  } catch (e) {
    if (current === q) send({ type: 'error', message: String(e?.message ?? e) });
  }
  if (current === q) process.exit(1); // stream ended on its own, not replaced: let the app restart us
}

function handle(m) {
  if (m.type === 'system' && m.subtype === 'init') {
    fs.writeFileSync(STATE, JSON.stringify({ day, id: m.session_id }));
    send({ type: 'ready', session_id: m.session_id });
  } else if (m.type === 'stream_event' && !m.parent_tool_use_id) {
    const e = m.event;
    if (e.type === 'content_block_delta' && e.delta?.type === 'text_delta') send({ type: 'partial_text', id: turnId, delta: e.delta.text });
  } else if (m.type === 'assistant') {
    for (const b of m.message.content ?? [])
      if (b.type === 'tool_use') send({ type: 'tool_call', id: turnId, name: b.name, summary: summary(b.input) });
  } else if (m.type === 'result') {
    cancelPending();
    if (m.subtype === 'success') send({ type: 'done', id: turnId, text: m.result ?? '', session_id: m.session_id });
    else send({ type: 'error', id: turnId, message: (m.errors ?? [m.subtype]).join('; ') });
  }
}

function restart() {
  const old = q;
  cancelPending(); input.close();
  start(); // replaces q first, so old's pump sees it was replaced
  old.close();
}

createInterface({ input: process.stdin }).on('line', (line) => {
  let msg; try { msg = JSON.parse(line); } catch { return send({ type: 'error', message: `JSON non valido: ${line.slice(0, 80)}` }); }
  if (msg.type === 'prompt') {
    if (day !== today()) restart(); // daily session
    turnId = msg.id;
    input.push({ type: 'user', message: { role: 'user', content: msg.text }, parent_tool_use_id: null, origin: { kind: 'human' } });
  } else if (msg.type === 'confirm') {
    pending.get(msg.id)?.(!!msg.allow); pending.delete(msg.id);
  } else if (msg.type === 'interrupt') {
    cancelPending(); q.interrupt().catch(() => {});
  } else if (msg.type === 'new_session') {
    fs.rmSync(STATE, { force: true }); restart();
  }
}).on('close', () => process.exit(0));

start();
