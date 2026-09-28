// Jarvis agent bridge: Claude Agent SDK <-> JSON lines on stdin/stdout.
// in:  prompt{id,text} | confirm{id,allow} | interrupt | new_session
// out: ready | commands | partial_text | tool_call | file_changed | need_confirmation | done | error
import { query } from '@anthropic-ai/claude-agent-sdk';
import { createInterface } from 'node:readline';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { confirmQuestion, sessionPaths } from './policy.mjs';

const VAULT = process.env.JARVIS_VAULT ?? process.cwd();
const STATE = process.env.JARVIS_STATE ?? path.join(os.homedir(), 'Library/Application Support/Jarvis/session.json');
fs.mkdirSync(path.dirname(STATE), { recursive: true });
const style = () => `Sei Jarvis, l'assistente vocale del secondo cervello. Rispondi in italiano, dai del tu, tono asciutto.
La risposta viene letta ad alta voce fino alla prima riga vuota: apri con al massimo due frasi brevi, senza markdown né elenchi.
Dettagli, liste e link vanno dopo una riga vuota: verranno solo mostrati a schermo.
L'utente detta con Wispr Flow: il testo può avere piccoli errori di trascrizione, interpreta nomi e termini con buon senso.
Ogni domanda è un giro a voce, quindi falle tutte insieme: se una skill (es. wayfinder, grilling) ha più domande indipendenti, mettile in un unico turno.
A voce di' solo quante sono (es. "Ho quattro domande, le trovi a schermo"); dopo la riga vuota mettile numerate, ognuna con la tua risposta consigliata.
L'utente può rispondere a tutte in un colpo (es. "uno sì, tre la B"); "ok" o "vai" significa accettare le risposte consigliate rimaste. Non chiedere quello che puoi scoprire da solo.
Il piano di oggi è in 00-Inbox/daily/${today()}.md: leggilo quando serve contesto sulla giornata.
Per le richieste ricorrenti usa le skill del vault (es. prep-day, close-day, ingest, decision, pull-tickets, pull-mrs, pull-teams, weekly).`;

const send = (o) => process.stdout.write(JSON.stringify(o) + '\n');
const today = () => new Date().toLocaleDateString('sv'); // YYYY-MM-DD, local time
const CONFIG = process.env.CLAUDE_CONFIG_DIR ?? path.join(os.homedir(), '.claude');
// Only ever called with an id Jarvis itself saved: the user's own sessions in the vault are never touched.
const forget = (id) => { for (const p of sessionPaths(id, VAULT, CONFIG)) fs.rmSync(p, { recursive: true, force: true }); };
const readState = () => { try { return JSON.parse(fs.readFileSync(STATE, 'utf8')); } catch { return null; } };
const sendCommands = (cs) => send({ type: 'commands', commands: cs.map(({ name, description, argumentHint }) => ({ name, description, argumentHint })) });
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

function start(fresh = false) {
  const saved = readState();
  day = today();
  input = channel();
  q = query({
    prompt: input,
    options: {
      cwd: VAULT,
      // Skip a session whose transcript is gone, or resume fails and the app restarts us forever.
      resume: !fresh && saved?.day === day && fs.existsSync(sessionPaths(saved.id, VAULT, CONFIG)[0] ?? '') ? saved.id : undefined,
      settingSources: ['user', 'project', 'local'],
      includePartialMessages: true,
      systemPrompt: { type: 'preset', preset: 'claude_code', append: style() },
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
  q.supportedCommands().then(sendCommands, () => {}); // skills for the "/" picker, before any prompt
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
    const prev = readState()?.id;
    if (prev && prev !== m.session_id) forget(prev); // previous Jarvis session is closed now
    fs.writeFileSync(STATE, JSON.stringify({ day, id: m.session_id }));
    send({ type: 'ready', session_id: m.session_id });
  } else if (m.type === 'system' && m.subtype === 'commands_changed') {
    sendCommands(m.commands);
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

function restart(fresh = false) {
  const old = q;
  cancelPending(); input.close();
  start(fresh); // replaces q first, so old's pump sees it was replaced
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
    restart(true);
  }
}).on('close', () => process.exit(0));

start();
