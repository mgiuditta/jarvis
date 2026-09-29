// Jarvis agent bridge: Claude Agent SDK <-> JSON lines on stdin/stdout.
// in:  prompt{id,text} | confirm{id,allow} | interrupt | new_session | mcp_status | mcp_reconnect{name} | mcp_reload
// out: ready | commands | partial_text | tool_call | orb | file_changed | need_confirmation | done | error | mcp_status
import { query } from '@anthropic-ai/claude-agent-sdk';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { confirmQuestion, sessionPaths } from './policy.mjs';
import { orbFilter, stripTags } from './orb.mjs';
import { VAULT, send, today, readState, writeState, summary, style, loadMcp, ask, cancelPending, onMessages } from './common.mjs';

const CONFIG = process.env.CLAUDE_CONFIG_DIR ?? path.join(os.homedir(), '.claude');
// Only ever called with an id Jarvis itself saved: the user's own sessions in the vault are never touched.
const forget = (id) => { for (const p of sessionPaths(id, VAULT, CONFIG)) fs.rmSync(p, { recursive: true, force: true }); };
const sendCommands = (cs) => send({ type: 'commands', commands: cs.map(({ name, description, argumentHint }) => ({ name, description, argumentHint })) });

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

let q, input, day, turnId = null, stopped = false;
const orb = orbFilter((variant) => send({ type: 'orb', id: turnId, variant }));

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
      mcpServers: loadMcp(), // Jarvis's own (dashboard), on top of the ones the settings bring
      includePartialMessages: true,
      systemPrompt: { type: 'preset', preset: 'claude_code', append: style() },
      pathToClaudeCodeExecutable: process.env.JARVIS_CLAUDE || undefined,
      extraArgs: { chrome: null }, // --chrome: Claude in Chrome tools, off by default in SDK sessions
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
    writeState(m.session_id);
    send({ type: 'ready', session_id: m.session_id });
  } else if (m.type === 'system' && m.subtype === 'commands_changed') {
    sendCommands(m.commands);
  } else if (m.type === 'stream_event' && !m.parent_tool_use_id) {
    const e = m.event;
    if (e.type === 'content_block_delta' && e.delta?.type === 'text_delta') {
      const delta = orb.text(e.delta.text);
      if (delta) send({ type: 'partial_text', id: turnId, delta });
    }
  } else if (m.type === 'assistant') {
    for (const b of m.message.content ?? [])
      if (b.type === 'tool_use') orb.tool(b.name), send({ type: 'tool_call', id: turnId, name: b.name, summary: summary(b.input) });
  } else if (m.type === 'result') {
    cancelPending();
    if (stopped) { stopped = false; send({ type: 'done', id: turnId, text: '', session_id: m.session_id }); } // user hit stop: not an error
    else if (m.subtype === 'success') send({ type: 'done', id: turnId, text: stripTags(m.result ?? ''), session_id: m.session_id });
    else send({ type: 'error', id: turnId, message: (m.errors ?? [m.subtype]).join('; ') });
  }
}

function restart(fresh = false) {
  const old = q;
  cancelPending(); input.close();
  start(fresh); // replaces q first, so old's pump sees it was replaced
  old.close();
}

async function mcpStatus() {
  const list = await q.mcpServerStatus().catch(() => []);
  send({ type: 'mcp_status', servers: list.map((s) => ({ name: s.name, status: s.status, error: s.error, source: s.source ?? s.scope, tools: (s.tools ?? []).map((t) => t.name) })) });
}

onMessages(async (msg) => {
  if (msg.type === 'prompt') {
    if (day !== today()) restart(); // daily session
    turnId = msg.id; stopped = false; orb.reset();
    input.push({ type: 'user', message: { role: 'user', content: msg.text }, parent_tool_use_id: null, origin: { kind: 'human' } });
  } else if (msg.type === 'interrupt') {
    stopped = true; cancelPending(); q.interrupt().catch(() => {});
  } else if (msg.type === 'new_session') {
    restart(true);
  } else if (msg.type === 'mcp_status') {
    mcpStatus();
  } else if (msg.type === 'mcp_reconnect') {
    await q.reconnectMcpServer(msg.name).catch((e) => send({ type: 'error', message: `MCP ${msg.name}: ${e?.message ?? e}` }));
    mcpStatus();
  } else if (msg.type === 'mcp_reload') {
    await q.setMcpServers(loadMcp()).catch((e) => send({ type: 'error', message: `MCP: ${e?.message ?? e}` }));
    mcpStatus();
  }
});

start();
