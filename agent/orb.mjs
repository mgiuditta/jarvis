// Orb variants: the model writes ⟦orb:name⟧ in its answer; we cut it out of the text and tell the app.
import fs from 'node:fs';

export function loadCatalog(file = new URL('../orb/variants.js', import.meta.url)) {
  try { const s = fs.readFileSync(file, 'utf8'); return JSON.parse(s.slice(s.indexOf('= [') + 2, s.lastIndexOf(']') + 1)); } catch { return []; }
}
export const CATALOG = loadCatalog();

export const orbPrompt = (cat = CATALOG) => cat.length ? `
Un orb animato mostra cosa stai facendo: scrivi ⟦orb:nome⟧ (invisibile, non viene letto) a ogni passo: all'inizio, prima di ogni strumento e prima della risposta finale, scegliendo ogni volta il nome più adatto a quel passo (cambialo, non ripetere sempre lo stesso) tra: ${cat.map((v) => v.hint ? `${v.name} (${v.hint})` : v.name).join(', ')}.` : '';

// Used when the model didn't tag: the tool it runs says what it's doing.
const TOOLS = [
  [/^web(search|fetch)$|web_search|web_fetch|^fetch/i, 'lente'],
  [/gmail|mail/i, 'busta'],
  [/calendar/i, 'calendario'],
  [/chrome|browser|playwright/i, 'globo'],
  [/figma/i, 'pillole-figma'],
  [/github/i, 'gatto-polpo'],
  [/gitlab/i, 'volpe-tanuki'],
  [/docker/i, 'balena-container'],
  [/kube|k8s|helm/i, 'timone'],
  [/postgres|sql|database|supabase/i, 'database'],
  [/slack/i, 'cancelletto'],
  [/(^|_)test/i, 'provetta'],
  [/drive/i, 'cartella'],
  [/^(edit|write|multiedit|notebookedit|create|str_replace)/i, 'matita'],
  [/^(bash|shell|powershell)/i, 'terminale'],
  [/^(read|glob|grep|view|ls)$/i, 'documento'],
  [/^(task|agent)$/i, 'robot-retro'],
];
export const toolVariant = (name = '') => TOOLS.find(([re]) => re.test(name))?.[1] ?? null;

const TAG = /⟦orb:([^⟧]*)⟧/g;
export const stripTags = (t = '') => t.replace(/⟦orb:[^⟧]*⟧[ \t]*/g, '');

// Streaming filter: holds back a ⟦ until its ⟧ arrives (or 40 chars say it wasn't a tag).
export function orbFilter(emit, names = new Set(CATALOG.map((v) => v.name)), now = Date.now) {
  let held = '', lastTag = -Infinity;
  return {
    text(delta) {
      let s = (held + delta).replace(TAG, (_, n) => { n = n.trim(); if (names.has(n)) { lastTag = now(); emit(n); } return ''; });
      held = '';
      const open = s.lastIndexOf('⟦');
      if (open >= 0 && s.length - open <= 40) { held = s.slice(open); s = s.slice(0, open); }
      return s;
    },
    tool(name) {
      const v = toolVariant(name);
      if (v && names.has(v) && now() - lastTag > 800) emit(v);
    },
    reset() { held = ''; lastTag = -Infinity; },
  };
}
