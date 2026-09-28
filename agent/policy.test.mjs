import { test } from 'node:test';
import assert from 'node:assert/strict';
import { confirmQuestion as q, sessionPaths } from './policy.mjs';

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
  assert.ok(q('Bash', { command: 'find . -name x -delete' }, V, exists));
  assert.ok(q('Bash', { command: 'find . -name x -exec rm {} +' }, V, exists));
  assert.ok(q('Bash', { command: 'git clean -fd' }, V, exists));
  assert.ok(q('Bash', { command: 'bash -c "rm x"' }, V, exists));
});

test('files', () => {
  assert.ok(q('Edit', { file_path: '/vault/99-Archive/a.md' }, V, exists));
  assert.ok(q('Write', { file_path: '/vault/06-People/Mario Bianchi.md' }, V, exists));
  assert.equal(q('Write', { file_path: '/vault/06-People/Anna Rossi.md' }, V, exists), null);
  assert.ok(q('Write', { file_path: '/vault/01-Projects/Acme/Nuovo/Acme - Nuovo.md' }, V, exists));
  assert.equal(q('Write', { file_path: '/vault/01-Projects/Acme/Spartacus/adr/0001.md' }, V, exists), null);
  assert.equal(q('Edit', { file_path: '/vault/00-Inbox/x.md' }, V, exists), null);
  assert.equal(q('Read', { file_path: '/vault/99-Archive/a.md' }, V, exists), null);
  assert.ok(q('Write', { file_path: '/Users/me/.zshrc' }, V, exists));
  assert.ok(q('Edit', { file_path: '../x.md' }, V, exists));
});

test('session paths', () => {
  const id = '78693793-327a-4542-b3ee-3266d52f2be7';
  assert.deepEqual(sessionPaths(id, '/Users/me/Dev/sbu-brain', '/c'),
    [`/c/projects/-Users-me-Dev-sbu-brain/${id}.jsonl`, `/c/projects/-Users-me-Dev-sbu-brain/${id}`]);
  assert.deepEqual(sessionPaths('../../etc', '/v', '/c'), []);
  assert.deepEqual(sessionPaths(undefined, '/v', '/c'), []);
});
