import fs from 'node:fs';
import path from 'node:path';

// Returns a spoken question when the tool call needs a voice "sì", else null.
// Rules mirror the vault's CLAUDE.md: deletes, moves, archive, new person/project.
export function confirmQuestion(tool, input, vault, exists = fs.existsSync) {
  if (tool === 'Bash') {
    const cmd = String(input?.command ?? '');
    if (/(^|[;&|("'`]|\s-exec(dir)?)\s*(sudo\s+|xargs\s+)?(rm|rmdir|unlink|mv|git\s+(rm|mv|clean))\s/.test(cmd)
        || /\s-delete(\s|$)/.test(cmd) || cmd.includes('99-Archive'))
      return `Devo eseguire: ${cmd.slice(0, 160)}. Confermi?`;
    return null;
  }
  if (!['Write', 'Edit', 'MultiEdit', 'NotebookEdit'].includes(tool)) return null;

  const file = path.resolve(vault, String(input?.file_path ?? input?.notebook_path ?? ''));
  const rel = path.relative(vault, file);
  if (rel.startsWith('..')) return `Scrivo fuori dal vault: ${file}. Confermi?`;
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

// Files Claude Code keeps for a session: <config>/projects/<cwd with non-alphanumerics as '-'>/<id>.jsonl (+ <id>/).
// Only well-formed UUIDs, so a bad id can never widen the path.
export function sessionPaths(id, vault, config) {
  if (!/^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/.test(id ?? '')) return [];
  const dir = path.join(config, 'projects', path.resolve(vault).replace(/[^a-zA-Z0-9]/g, '-'));
  return [path.join(dir, `${id}.jsonl`), path.join(dir, id)];
}

// Copilot asks per permission kind, not per tool: map it onto the same rules (shell = Bash, write = Write).
export function copilotQuestion(req, vault, exists = fs.existsSync) {
  if (req?.kind === 'shell') return confirmQuestion('Bash', { command: req.fullCommandText }, vault, exists);
  if (req?.kind === 'write') return confirmQuestion('Write', { file_path: req.fileName }, vault, exists);
  return null;
}
