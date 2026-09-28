// Shared by the two bridges (agent.mjs = Claude, copilot.mjs = Copilot): same JSON-lines protocol.
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { createInterface } from 'node:readline';

export const VAULT = process.env.JARVIS_VAULT ?? process.cwd();
export const STATE = process.env.JARVIS_STATE ?? path.join(os.homedir(), 'Library/Application Support/Jarvis/session.json');
export const MCP = process.env.JARVIS_MCP ?? path.join(os.homedir(), 'Library/Application Support/Jarvis/mcp.json');
fs.mkdirSync(path.dirname(STATE), { recursive: true });

export const send = (o) => process.stdout.write(JSON.stringify(o) + '\n');
export const today = () => new Date().toLocaleDateString('sv'); // YYYY-MM-DD, local time
export const readState = () => { try { return JSON.parse(fs.readFileSync(STATE, 'utf8')); } catch { return null; } };
export const writeState = (id) => fs.writeFileSync(STATE, JSON.stringify({ day: today(), id }));
export const summary = (i = {}) => String(i.file_path ?? i.path ?? i.command ?? i.skill ?? i.pattern ?? i.url ?? i.query ?? i.description ?? '').slice(0, 140);

// Jarvis-owned MCP servers, same shape as a .mcp.json. A broken file means none, not a dead agent.
export function loadMcp(file = MCP) {
  try { return JSON.parse(fs.readFileSync(file, 'utf8')).mcpServers ?? {}; } catch { return {}; }
}

// The sbu-brain vault layout: daily notes and vault skills only make sense there.
export const isVault = (dir = VAULT) => fs.existsSync(path.join(dir, '00-Inbox'));

export const style = () => `Sei Jarvis, un assistente vocale. Rispondi in italiano, dai del tu, tono asciutto.
La risposta viene letta ad alta voce fino alla prima riga vuota: apri con al massimo due frasi brevi, senza markdown né elenchi.
Dettagli, liste e link vanno dopo una riga vuota: verranno solo mostrati a schermo.
L'utente detta con Wispr Flow: il testo può avere piccoli errori di trascrizione, interpreta nomi e termini con buon senso.
Ogni domanda è un giro a voce, quindi falle tutte insieme: se una skill (es. wayfinder, grilling) ha più domande indipendenti, mettile in un unico turno.
A voce di' solo quante sono (es. "Ho quattro domande, le trovi a schermo"); dopo la riga vuota mettile numerate, ognuna con la tua risposta consigliata.
L'utente può rispondere a tutte in un colpo (es. "uno sì, tre la B"); "ok" o "vai" significa accettare le risposte consigliate rimaste. Non chiedere quello che puoi scoprire da solo.${isVault() ? `
Lavori nel secondo cervello dell'utente. Il piano di oggi è in 00-Inbox/daily/${today()}.md: leggilo quando serve contesto sulla giornata.
Per le richieste ricorrenti usa le skill del vault (es. prep-day, close-day, ingest, decision, pull-tickets, pull-mrs, pull-teams, weekly).` : ''}`;

// Voice confirmations: need_confirmation out, confirm{id,allow} in.
const pending = new Map(); // confirmation id -> resolve(bool)
let seq = 0;
export function ask(question) {
  const id = `c${++seq}`;
  send({ type: 'need_confirmation', id, question });
  return new Promise((resolve) => pending.set(id, resolve));
}
export function answer(id, allow) { pending.get(id)?.(!!allow); pending.delete(id); }
export function cancelPending() { for (const r of pending.values()) r(false); pending.clear(); }

// stdin JSON lines -> handler(msg). stdin closed = the app is gone.
export function onMessages(handler) {
  createInterface({ input: process.stdin }).on('line', (line) => {
    let msg; try { msg = JSON.parse(line); } catch { return send({ type: 'error', message: `JSON non valido: ${line.slice(0, 80)}` }); }
    if (msg.type === 'confirm') return answer(msg.id, msg.allow);
    handler(msg);
  }).on('close', () => process.exit(0));
}
