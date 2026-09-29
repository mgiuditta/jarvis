# Orb a varianti — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** L'orb si trasforma in una di ~100 forme (oggetti, personaggi, umori) scelte dall'AI con un tag `⟦orb:nome⟧`, con fallback sui tool usati.

**Architecture:** Catalogo unico `orb/variants.js` (JSON dentro un assegnamento, così lo carica sia `<script>` sia Node). Il sidecar (`agent/orb.mjs`) toglie i tag dallo stream e manda `{type:'orb', variant}`; Swift lo passa all'orb; `orb.js` sostituisce il blob mesh con un quad raymarched SDF e fa morph blob → forma.

**Tech Stack:** Node ESM + `node:test`, Swift 6 / SwiftUI / WKWebView, three.js 0.160 (ShaderMaterial, GLSL).

Spec: `docs/superpowers/specs/2026-09-29-orb-varianti-design.md`.

**Deviazione dallo spec (semplificazione):** niente env `JARVIS_ORB_CATALOG` né `WKUserScript`. `agent/` e `orb/` sono fratelli sia nel repo sia nel bundle (rsync nella build phase), quindi Node legge `new URL('../orb/variants.js', import.meta.url)` e la pagina carica `variants.js` con un `<script>`. `gallery.html` funziona anche da `file://`.

---

## File

| File | Ruolo |
|---|---|
| `orb/variants.js` (nuovo) | catalogo `ORB_VARIANTS = [...]` (JSON valido tra `[` e `]`) |
| `agent/orb.mjs` (nuovo) | `loadCatalog`, `orbPrompt`, `toolVariant`, `orbFilter`, `stripTags` |
| `agent/orb.test.mjs` (nuovo) | test del filtro/fallback/catalogo |
| `agent/common.mjs` | `style()` += `orbPrompt()` |
| `agent/agent.mjs`, `agent/copilot.mjs` | delta → filtro, tool_call → fallback, done text → `stripTags` |
| `Jarvis/AgentClient.swift` | `AgentEvent.variant` |
| `Jarvis/AppState.swift` | `orbVariant`, `case "orb"`, reset in `endTurn` |
| `Jarvis/Orb.swift`, `Jarvis/Overlay.swift` | passano `variant` a `orb.set` |
| `orb/orb.html` | carica `variants.js` |
| `orb/orb.js` | blob raymarched SDF, forme, morph, mood, hue |
| `orb/gallery.html` (nuovo) | griglia QA di tutte le varianti |

---

### Task 1: Catalogo e modulo `agent/orb.mjs` (TDD)

**Files:** Create `orb/variants.js`, `agent/orb.mjs`, `agent/orb.test.mjs`

- [ ] **Step 1: catalogo iniziale** `orb/variants.js`, solo varianti con forma già implementata (cresce nei task 6–7):

```js
// Orb variants: the model picks one by name (⟦orb:name⟧). Read by orb.js (<script>) and agent/orb.mjs (JSON between [ and ]).
// shape = SDF id in orb.js, mood = calm|spiky|jitter|shards|pulse, hue = color override or null, hint = word for the prompt.
var ORB_VARIANTS = [
  {"name": "blob", "shape": "blob", "mood": "calm", "hue": null, "hint": "neutro"},
  {"name": "lente", "shape": "lens", "mood": "calm", "hue": null, "hint": "ricerca"},
  ...
];
```

- [ ] **Step 2: test che falliscono** `agent/orb.test.mjs`:

```js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { orbFilter, stripTags, toolVariant, loadCatalog, orbPrompt } from './orb.mjs';

const names = new Set(['lente', 'busta', 'terminale']);
const make = () => { const out = []; let t = 0; const f = orbFilter((v) => out.push(v), names, () => t); return { f, out, tick: (ms) => (t += ms) }; };

test('tag in one delta', () => {
  const { f, out } = make();
  assert.equal(f.text('⟦orb:lente⟧Cerco'), 'Cerco');
  assert.deepEqual(out, ['lente']);
});
test('tag split across deltas', () => {
  const { f, out } = make();
  assert.equal(f.text('Ok ⟦or'), 'Ok ');
  assert.equal(f.text('b:bu'), '');
  assert.equal(f.text('sta⟧ scrivo'), ' scrivo');
  assert.deepEqual(out, ['busta']);
});
test('unknown name dropped silently', () => {
  const { f, out } = make();
  assert.equal(f.text('⟦orb:pippo⟧ciao'), 'ciao');
  assert.deepEqual(out, []);
});
test('unclosed bracket released after 40 chars', () => {
  const { f } = make();
  assert.equal(f.text('a ⟦ b'), 'a ');
  assert.equal(f.text('x'.repeat(40)), '⟦ b' + 'x'.repeat(40));
});
test('plain text untouched', () => {
  assert.equal(make().f.text('niente tag qui'), 'niente tag qui');
});
test('tool fallback respects 2s after a tag', () => {
  const { f, out, tick } = make();
  f.text('⟦orb:lente⟧');
  f.tool('Bash'); assert.deepEqual(out, ['lente']);
  tick(2500); f.tool('Bash'); assert.deepEqual(out, ['lente', 'terminale']);
  f.tool('SconosciutoTool'); assert.deepEqual(out, ['lente', 'terminale']);
});
test('reset drops a half tag', () => {
  const { f } = make();
  f.text('⟦orb:le'); f.reset();
  assert.equal(f.text('ciao'), 'ciao');
});
test('stripTags', () => assert.equal(stripTags('⟦orb:lente⟧ Cerco ⟦orb:busta⟧e scrivo'), 'Cerco e scrivo'));
test('toolVariant', () => {
  assert.equal(toolVariant('WebSearch'), 'lente');
  assert.equal(toolVariant('mcp__claude_ai_Gmail__search_threads'), 'busta');
  assert.equal(toolVariant('bash'), 'terminale');
  assert.equal(toolVariant('edit'), 'matita');
  assert.equal(toolVariant('Nope'), null);
});
test('real catalog parses, names unique, tool map targets exist', () => {
  const cat = loadCatalog();
  assert.ok(cat.length > 10);
  const n = cat.map((v) => v.name);
  assert.equal(new Set(n).size, n.length);
  for (const v of ['lente', 'busta', 'calendario', 'globo', 'matita', 'terminale', 'documento', 'robot-retro', 'cartella', 'tavolozza'])
    assert.ok(n.includes(v), v);
  assert.match(orbPrompt(cat), /⟦orb:nome⟧/);
  assert.equal(orbPrompt([]), '');
});
```

- [ ] **Step 3:** `node --test agent/orb.test.mjs` → FAIL (module not found).
- [ ] **Step 4: implementazione** `agent/orb.mjs`:

```js
// Orb variants: the model writes ⟦orb:name⟧ in its answer; we cut it out of the text and tell the app.
import fs from 'node:fs';

export function loadCatalog(file = new URL('../orb/variants.js', import.meta.url)) {
  try { const s = fs.readFileSync(file, 'utf8'); return JSON.parse(s.slice(s.indexOf('= [') + 2, s.lastIndexOf(']') + 1)); } catch { return []; }
}
export const CATALOG = loadCatalog();

export const orbPrompt = (cat = CATALOG) => cat.length ? `
Un orb animato mostra cosa stai facendo: prima della risposta e ogni volta che cambi fase scrivi ⟦orb:nome⟧ (invisibile, non viene letto), col nome più adatto tra: ${cat.map((v) => v.hint ? `${v.name} (${v.hint})` : v.name).join(', ')}.` : '';

// Used when the model didn't tag: the tool it runs says what it's doing.
const TOOLS = [
  [/^web(search|fetch)$|web_search|web_fetch|^fetch/i, 'lente'],
  [/gmail|mail/i, 'busta'],
  [/calendar/i, 'calendario'],
  [/chrome|browser|playwright/i, 'globo'],
  [/figma/i, 'tavolozza'],
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
      if (v && names.has(v) && now() - lastTag > 2000) emit(v);
    },
    reset() { held = ''; lastTag = -Infinity; },
  };
}
```

Nota sul test "tag split": dopo il tag, `' scrivo'` mantiene lo spazio (il filtro streaming non lo mangia; `stripTags` sul testo finale sì).

- [ ] **Step 5:** `node --test agent/orb.test.mjs agent/policy.test.mjs` → PASS.
- [ ] **Step 6:** commit `feat(orb): catalogo varianti e filtro tag`.

### Task 2: Sidecar collegati

**Files:** Modify `agent/common.mjs`, `agent/agent.mjs`, `agent/copilot.mjs`

- [ ] `common.mjs`: `import { orbPrompt } from './orb.mjs';` e in fondo a `style()` concatenare `${orbPrompt()}`.
- [ ] `agent.mjs`: `const orb = orbFilter((variant) => send({ type: 'orb', id: turnId, variant }));`
  - partial_text: `const t = orb.text(e.delta.text); if (t) send({ type: 'partial_text', id: turnId, delta: t });`
  - tool_use: `orb.tool(b.name);` prima del send tool_call.
  - done: `text: stripTags(m.result ?? '')`.
  - prompt: `orb.reset();` insieme a `turnId = msg.id`.
- [ ] `copilot.mjs`: stesso schema (`d.deltaContent`, `d.toolName`, `lastText = stripTags(d.content ?? lastText)` nel `assistant.message`, `orb.reset()` al prompt).
- [ ] Update header comment `out:` in agent.mjs con `orb`.
- [ ] `node --test agent/` → PASS; `node -e "import('./agent/common.mjs').then(m=>console.log(m.style().slice(-300)))"` mostra il catalogo.
- [ ] commit `feat(orb): sidecar emette eventi orb`.

### Task 3: Swift

**Files:** Modify `Jarvis/AgentClient.swift`, `Jarvis/AppState.swift`, `Jarvis/Orb.swift`, `Jarvis/Overlay.swift`

- [ ] `AgentEvent`: aggiungere `variant` alla lista `var id, delta, …: String?`.
- [ ] `AppState`: `var orbVariant = "blob"  // shape the orb takes while working, from the agent (⟦orb:…⟧)`; in `handle`: `case "orb": orbVariant = e.variant ?? "blob"`; in `endTurn`: `orbVariant = "blob"` (copre done, error, /clear, restart).
- [ ] `OrbWebView`: `var variant = "blob"`; in `push()` `let name = variant.filter { $0.isLetter || $0.isNumber || $0 == "-" }` e aggiungere `,variant:'\(name)'` al JS.
- [ ] `OrbView`: `let variant: String`, `v.variant = variant` in `updateNSView`.
- [ ] `Overlay`: `OrbView(state: app.state, colorHex: orbHex, levels: app.speaker.levels, hovering: hovering, variant: app.orbVariant)`.
- [ ] Build: `xcodebuild -project Jarvis.xcodeproj -scheme Jarvis -configuration Debug build -quiet` → BUILD SUCCEEDED. (Non lanciare/installare l'app.)
- [ ] commit `feat(orb): variant da agent a orb`.

### Task 4: `orb.js` raymarched + prime forme

**Files:** Modify `orb/orb.html`, `orb/orb.js`

- [ ] `orb.html`: `<script src="variants.js"></script>` prima di `orb.js`.
- [ ] Sostituire la mesh blob con una `PlaneGeometry(6, 6)` a z=0 e ShaderMaterial raymarcher:
  - vertex: `vWorld = (modelMatrix * vec4(position,1.)).xyz`.
  - fragment: `ro = cameraPosition`, `rd = normalize(vWorld - cameraPosition)`; ruota in object space con `uniform mat3 uRot`; early-out se il raggio manca la sfera di raggio 2.3 (`discard`); ≤ 72 passi; `discard` se non colpisce.
  - `map(p)`: `mix(blob(p), shape(p), uMix)` + `mood(p)`; `blob(p)` = displacement attuale (`field` Ashima 2 ottave, `uAmp`, `uFreq`, `uTime`) su raggio 1.45.
  - shading identico a oggi (fresnel 2.2, diff, spec 60, spec2, irid, veins da `field`, rim × `uGlow`), normale da 4 tap tetraedrici.
  - `uShape` int → `switch` di funzioni SDF; materiale speciale per `symbiote` (occhi bianchi).
- [ ] JS: `set({variant})` → lookup in `ORB_VARIANTS`; morph: `uMix` scende a 0, a 0 si cambia `uShape`/mood/rotazione, poi sale a 1; tenuta minima 1,5 s; stati `confirm`/`error` o variante `blob` → target blob. `hue` sostituisce il colore base finché la variante è attiva. Rotazione: blob = spin continuo come oggi; forme = oscillazione ±0.5 rad attorno a vista frontale (così busta/lente non vanno di taglio).
- [ ] Forme iniziali (catalogo del task 1): blob, lens, envelope, gear, calendar, globe, pencil, terminal, document, robot, folder, palette, symbiote, person.
- [ ] commit `feat(orb): blob raymarched con varianti`.

### Task 5: `orb/gallery.html`

- [ ] Pagina standalone che carica `three.min.js`, `variants.js`, `orb.js` in N iframe? No: più semplice, una pagina che crea una griglia di `<iframe src="orb.html#nome">` e `orb.js` legge `location.hash` per mettersi in modalità demo (ciclo blob → forma ogni 4 s, stato `thinking`). Nome sotto ogni iframe.
- [ ] Verifica a occhio in Chrome (`file://…/orb/gallery.html`), dimensione 96 e 200 px. Screenshot per l'utente.
- [ ] commit.

### Task 6: Oggetti (resto del catalogo)
Per ogni categoria dello spec: SDF in `orb.js` + riga in `variants.js`, check in gallery, commit per categoria. Regola: sagoma leggibile a 96 px, altrimenti semplificare o togliere.

### Task 7: Personaggi (30 omaggi)
Come task 6. Omaggi, non copie; commit a blocchi di ~10.

### Task 8: Verifica finale
- [ ] `node --test agent/` PASS, build Xcode OK, gallery tutta leggibile, spec aggiornato (deviazione catalogo).
- [ ] Nessun lancio/reinstall dell'app senza ok dell'utente.
