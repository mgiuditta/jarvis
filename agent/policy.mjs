import fs from 'node:fs';
import path from 'node:path';

// Returns a spoken question when the tool call needs a voice "sì", else null.
// Rules mirror the vault's CLAUDE.md: deletes, moves, archive, new person/project.
export function confirmQuestion(tool, input, vault, exists = fs.existsSync) {
  if (tool === 'Bash') {
    const cmd = String(input?.command ?? '');
    if (/(^|[;&|(])\s*(sudo\s+|xargs\s+)?(rm|rmdir|unlink|mv|git\s+(rm|mv))\s/.test(cmd) || cmd.includes('99-Archive'))
      return `Devo eseguire: ${cmd.slice(0, 160)}. Confermi?`;
    return null;
  }
  if (!['Write', 'Edit', 'MultiEdit', 'NotebookEdit'].includes(tool)) return null;

  const file = path.resolve(vault, String(input?.file_path ?? input?.notebook_path ?? ''));
  const rel = path.relative(vault, file);
  if (rel.startsWith('99-Archive' + path.sep)) return `Archivio ${path.basename(file)}. Confermi?`;
  if (tool !== 'Write' || exists(file)) return null;
  if (rel.startsWith('06-People' + path.sep)) return `Creo la persona ${path.basename(file, '.md')}. Confermi?`;
  // New project = its 01-Projects/<Azienda>/<Progetto> folder doesn't exist yet.
  // <Azienda>/<Azienda>.md lives in the company folder, deeper files under <Azienda>/<Progetto>/.
  const parts = rel.split(path.sep);
  if (parts[0] !== '01-Projects' || parts.length < 3) return null;
  const projectDir = parts.slice(0, parts.length > 3 ? 3 : 2).join(path.sep);
  if (!exists(path.join(vault, projectDir))) return `Creo il nuovo progetto ${projectDir.slice('01-Projects/'.length)}. Confermi?`;
  return null;
}
