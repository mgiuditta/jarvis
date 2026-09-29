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
