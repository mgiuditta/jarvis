import { test } from 'node:test';
import assert from 'node:assert/strict';
import { confirmQuestion as q } from './policy.mjs';

const V = '/vault';
const existing = new Set(['/vault/06-People/Anna Rossi.md', '/vault/01-Projects/Acme/Spartacus', '/vault/00-Inbox/x.md']);
const exists = (p) => existing.has(p);

test('bash', () => {
  assert.ok(q('Bash', { command: 'rm 00-Inbox/x.md' }, V, exists));
  assert.ok(q('Bash', { command: 'cd a && mv x y' }, V, exists));
  assert.ok(q('Bash', { command: 'cp a 99-Archive/' }, V, exists));
  assert.equal(q('Bash', { command: 'grep -rl mv .' }, V, exists), null);
  assert.equal(q('Bash', { command: 'ls 00-Inbox' }, V, exists), null);
  assert.ok(q('Bash', { command: 'find . -name x | xargs rm -f' }, V, exists));
});

test('files', () => {
  assert.ok(q('Edit', { file_path: '/vault/99-Archive/a.md' }, V, exists));
  assert.ok(q('Write', { file_path: '/vault/06-People/Mario Bianchi.md' }, V, exists));
  assert.equal(q('Write', { file_path: '/vault/06-People/Anna Rossi.md' }, V, exists), null);
  assert.ok(q('Write', { file_path: '/vault/01-Projects/Acme/Nuovo/Acme - Nuovo.md' }, V, exists));
  assert.equal(q('Write', { file_path: '/vault/01-Projects/Acme/Spartacus/adr/0001.md' }, V, exists), null);
  assert.equal(q('Edit', { file_path: '/vault/00-Inbox/x.md' }, V, exists), null);
  assert.equal(q('Read', { file_path: '/vault/99-Archive/a.md' }, V, exists), null);
});
