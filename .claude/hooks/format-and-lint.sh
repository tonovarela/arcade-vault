#!/usr/bin/env bash
#
# Hook PostToolUse: pasa por Prettier (y ESLint cuando aplica) los archivos que
# se acaban de crear o modificar en el proyecto, y les quita los espacios en
# blanco al final de cada linea.
#
# Dos modos, segun tool_name del JSON que llega por stdin:
#   Write/Edit/MultiEdit/NotebookEdit -> el archivo del payload
#   Bash                              -> archivos del working tree tocados en los ultimos 120s
#
# Salida: 0 normalmente. 2 si ESLint deja errores que --fix no pudo resolver,
# para que el detalle (stderr) vuelva a Claude y los corrija.

PROJECT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
PRETTIER="$PROJECT_DIR/node_modules/.bin/prettier"
ESLINT="$PROJECT_DIR/node_modules/.bin/eslint"

[[ -x "$PRETTIER" ]] || exit 0

INPUT=$(cat)
[[ -z "$INPUT" ]] && exit 0

# Node resuelve la lista de archivos objetivo (uno por linea, rutas absolutas).
read -r -d '' COLLECT <<'NODE' || true
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const [raw, projectDir] = process.argv.slice(1);
let payload;
try {
  payload = JSON.parse(raw);
} catch {
  process.exit(0);
}

const SKIP = ['node_modules/', '.next/', '.git/', '.claude/worktrees/'];
const MAX_FILES = 50;

function accept(p) {
  if (!p) return null;
  const abs = path.resolve(projectDir, p);
  const rel = path.relative(projectDir, abs);
  if (!rel || rel.startsWith('..') || path.isAbsolute(rel)) return null;
  const probe = rel + '/';
  if (SKIP.some((s) => probe.startsWith(s) || probe.includes('/' + s))) return null;
  try {
    if (!fs.statSync(abs).isFile()) return null;
  } catch {
    return null;
  }
  return abs;
}

const out = [];

if (payload.tool_name === 'Bash') {
  let status = '';
  try {
    status = execFileSync(
      'git',
      ['-C', projectDir, 'status', '--porcelain', '--untracked-files=all', '-z'],
      { encoding: 'utf8' },
    );
  } catch {
    process.exit(0);
  }
  const cutoff = Date.now() - 120000;
  const chunks = status.split('\0');
  for (let i = 0; i < chunks.length && out.length < MAX_FILES; i++) {
    const entry = chunks[i];
    if (entry.length < 4) continue;
    const code = entry.slice(0, 2);
    // En -z, un rename emite "R  nuevo\0viejo": el siguiente chunk es la ruta original.
    if (code[0] === 'R' || code[1] === 'R') i++;
    const abs = accept(entry.slice(3));
    if (!abs) continue;
    try {
      if (fs.statSync(abs).mtimeMs < cutoff) continue;
    } catch {
      continue;
    }
    out.push(abs);
  }
} else {
  const ti = payload.tool_input || {};
  const tr = payload.tool_response || {};
  const abs = accept(tr.filePath || ti.file_path || ti.path || ti.notebook_path);
  if (abs) out.push(abs);
}

if (out.length) process.stdout.write(out.join('\n') + '\n');
NODE

FILES=$(node -e "$COLLECT" "$INPUT" "$PROJECT_DIR" 2>/dev/null)
[[ -z "$FILES" ]] && exit 0

ALL=()
JS=()
while IFS= read -r f; do
  [[ -n "$f" ]] || continue
  ALL+=("$f")
  case "$f" in
    *.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs) JS+=("$f") ;;
  esac
done <<< "$FILES"

[[ ${#ALL[@]} -eq 0 ]] && exit 0

# Prettier nunca bloquea: --ignore-unknown salta lo que no sabe parsear
# (imagenes, audio, .env) y respeta .prettierignore.
if ! PRETTIER_OUT=$("$PRETTIER" --write --ignore-unknown "${ALL[@]}" 2>&1); then
  printf '%s\n' "$PRETTIER_OUT" | sed 's/^/[prettier] /' >&2
fi

# Espacios en blanco al final de linea: prettier ya los quita en lo que sabe
# parsear, esto cubre el resto (yaml raro, .env, .txt, sql, etc.) e incluye
# markdown (ojo: ahi dos espacios finales son un <br>, se pierden a proposito).
# Se saltan binarios (grep -I). El \r se conserva para no romper CRLF.
for f in "${ALL[@]}"; do
  grep -Iq . "$f" 2>/dev/null || continue
  perl -pi -e 's/[ \t]+(\r?)$/$1/' "$f" 2>/dev/null
done

if [[ ${#JS[@]} -gt 0 && -x "$ESLINT" ]]; then
  if ! ESLINT_OUT=$("$ESLINT" --fix --no-warn-ignored "${JS[@]}" 2>&1); then
    printf '%s\n' "$ESLINT_OUT" | sed 's/^/[eslint] /' >&2
    echo "[eslint] Quedan problemas que --fix no pudo resolver. Corrigelos antes de seguir." >&2
    exit 2
  fi
fi

exit 0
