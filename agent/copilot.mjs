// Jarvis agent bridge for GitHub Copilot: same JSON-lines protocol as agent.mjs (see there).
// Uses the user's Copilot CLI (JARVIS_COPILOT) and its GitHub login.
import { CopilotClient, RuntimeConnection } from '@github/copilot-sdk';
import { copilotQuestion } from './policy.mjs';
import { orbFilter, stripTags } from './orb.mjs';
import { VAULT, send, today, readState, writeState, summary, style, loadMcp, ask, cancelPending, onMessages } from './common.mjs';

const client = new CopilotClient({
  connection: RuntimeConnection.forStdio({ path: process.env.JARVIS_COPILOT || undefined }),
  workingDirectory: VAULT,
});

let session, day, turnId = null, stopped = false, failed = false, lastText = '';
const orb = orbFilter((variant) => send({ type: 'orb', id: turnId, variant }));

const config = () => ({
  workingDirectory: VAULT,
  streaming: true,
  mcpServers: loadMcp(), // Jarvis's own (dashboard), on top of ~/.copilot/mcp-config.json
  systemMessage: { content: style() },
  // No onUserInputRequest: without it the ask_user tool is off, questions go in the spoken answer.
  onPermissionRequest: async (req) => {
    const question = copilotQuestion(req, VAULT)
      ?? (req.managedApprovalRequired ? `Copilot chiede il permesso: ${req.intention ?? req.kind}. Confermi?` : null);
    if (!question) return { kind: 'approve-once' };
    return (await ask(question)) ? { kind: 'approve-once' } : { kind: 'reject', feedback: "L'utente ha rifiutato." };
  },
  hooks: {
    onPostToolUse: async (h) => {
      const p = h.toolArgs?.path;
      if (p && /^(edit|create|write)/.test(h.toolName)) send({ type: 'file_changed', path: p, op: h.toolName });
    },
  },
});

async function start(fresh = false) {
  const saved = readState();
  day = today();
  // ponytail: old daily sessions stay in Copilot's own store (~/.copilot), no cleanup like agent.mjs's forget()
  session = !fresh && saved?.day === day
    ? await client.resumeSession(saved.id, config()).catch(() => null)
    : null;
  session ??= await client.createSession(config());
  writeState(session.sessionId);
  const mine = session;
  session.on((e) => { if (mine === session) handle(e); });
  send({ type: 'ready', session_id: session.sessionId });
}

function handle(e) {
  const d = e.data ?? {};
  if (d.parentToolCallId) return; // sub-agent chatter
  if (e.type === 'assistant.message_delta') { const delta = orb.text(d.deltaContent ?? ''); if (delta) send({ type: 'partial_text', id: turnId, delta }); }
  else if (e.type === 'assistant.message') lastText = stripTags(d.content ?? lastText);
  else if (e.type === 'tool.execution_start') orb.tool(d.toolName), send({ type: 'tool_call', id: turnId, name: d.toolName, summary: summary(d.arguments ?? {}) });
  else if (e.type === 'session.error') { failed = true; cancelPending(); send({ type: 'error', id: turnId, message: d.message ?? d.errorType }); }
  else if (e.type === 'session.idle') {
    cancelPending();
    if (!failed) send({ type: 'done', id: turnId, text: stopped ? '' : lastText, session_id: session.sessionId });
    stopped = failed = false;
  }
}

async function restart(fresh = false) {
  cancelPending();
  const old = session;
  await start(fresh);
  old?.disconnect().catch(() => {});
}

async function mcpStatus() {
  const { servers = [] } = await session.rpc.mcp.list().catch(() => ({}));
  const tools = async (s) => s.status !== 'connected' ? []
    : ((await session.rpc.mcp.listTools({ serverName: s.name }).catch(() => ({}))).tools ?? []).map((t) => t.name);
  send({ type: 'mcp_status', servers: await Promise.all(servers.map(async (s) => ({ name: s.name, status: s.status, error: s.error, source: s.source, tools: await tools(s) }))) });
}

let ready; // messages wait for the first session, or a prompt races start() and opens a second one
onMessages(async (msg) => {
  await ready;
  if (msg.type === 'prompt') {
    if (day !== today()) await restart(); // daily session
    turnId = msg.id; stopped = failed = false; lastText = ''; orb.reset();
    session.send({ prompt: msg.text }).catch((e) => send({ type: 'error', id: turnId, message: String(e?.message ?? e) }));
  } else if (msg.type === 'interrupt') {
    stopped = true; cancelPending(); session.abort().catch(() => {});
  } else if (msg.type === 'new_session') {
    await restart(true);
  } else if (msg.type === 'mcp_status') {
    mcpStatus();
  } else if (msg.type === 'mcp_reconnect') {
    await session.rpc.mcp.restartServer({ serverName: msg.name }).catch((e) => send({ type: 'error', message: `MCP ${msg.name}: ${e?.message ?? e}` }));
    mcpStatus();
  } else if (msg.type === 'mcp_reload') {
    await restart(); // mcpServers is session config: resume the same session with the new file
    mcpStatus();
  }
});

ready = client.start().then(() => start()).catch((e) => {
  send({ type: 'error', message: `Copilot non parte: ${e?.message ?? e}. Controlla il path della Copilot CLI e il login (copilot, poi /login).` });
  process.exit(1);
});
