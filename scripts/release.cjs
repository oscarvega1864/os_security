// Herramienta de publicacion (solo desarrollo y GitHub Actions; no forma parte del recurso).
//   node scripts/release.cjs version          -> imprime la version de config/config.lua
//   node scripts/release.cjs check v0.9.0     -> falla si la etiqueta no coincide con la version
//   node scripts/release.cjs package          -> dist/os_security-vX.Y.Z.zip (solo archivos del recurso)
//   node scripts/release.cjs notes v0.9.0     -> notas de la release en Markdown (CHANGELOG + commits)
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { execFileSync } = require('node:child_process');

const root = path.resolve(__dirname, '..');
const git = (...args) => execFileSync('git', args, { cwd: root, encoding: 'utf8' }).trim();

function version() {
  const source = fs.readFileSync(path.join(root, 'config/config.lua'), 'utf8');
  const match = source.match(/Version\s*=\s*'(\d+\.\d+\.\d+)'/);
  if (!match) throw new Error('No se encuentra Version en config/config.lua');
  return match[1];
}
const zipName = value => `os_security-v${value}.zip`;

// Seccion del CHANGELOG de una version ("## 0.9.0 — Titulo" hasta la siguiente "## ").
function changelog(value) {
  const lines = fs.readFileSync(path.join(root, 'CHANGELOG.md'), 'utf8').split(/\r?\n/);
  const start = lines.findIndex(line => line.startsWith(`## ${value}`));
  if (start === -1) return { title: null, body: '' };
  let end = lines.findIndex((line, index) => index > start && line.startsWith('## '));
  if (end === -1) end = lines.length;
  const title = lines[start].replace(/^##\s*\d+\.\d+\.\d+\s*[—-]?\s*/, '').trim() || null;
  return { title, body: lines.slice(start + 1, end).join('\n').trim() };
}

// Commits desde la etiqueta anterior (o todos en la primera release).
function commits(tag) {
  let previous = null;
  try { previous = git('describe', '--tags', '--abbrev=0', '--match', 'v*', `${tag}^`); } catch { previous = null; }
  const range = previous ? `${previous}..${tag}` : tag;
  const log = git('log', '--no-merges', '--format=%h%x09%s', range);
  return { previous, items: log ? log.split('\n').map(line => line.split('\t')) : [] };
}

function notes(tag) {
  const value = tag.replace(/^v/, '');
  const { title, body } = changelog(value);
  const { previous, items } = commits(tag);
  const out = [];
  out.push(`Gruppe Sechs · **OS Security ${tag}**${title ? ` — ${title}` : ''}. Recurso standalone de seguridad para FiveM: tablets G6, CCTV, alarmas, cerraduras, vehículos y minijuegos, sin frameworks ni MySQL.`, '');
  out.push('| Tu servidor | Descarga |', '| --- | --- |', `| FiveM (GTA V Legacy) | \`${zipName(value)}\` |`, '');
  out.push('**Instalación nueva:** descomprime el zip en `resources/` (la carpeta debe llamarse `os_security`), añade `ensure os_security` al `server.cfg` y reinicia el servidor. Permisos e integraciones opcionales en el [README](../../blob/' + tag + '/README.md).', '');
  out.push('**Actualizar:** sustituye la carpeta `os_security` conservando `data/` (inventario, montajes y dispositivos) y reinicia el servidor completo.', '');
  if (body) out.push(`## Novedades en ${tag}`, '', body, '');
  out.push(`## Cambios en ${tag}`, '');
  if (items.length) for (const [hash, subject] of items) out.push(`- \`${hash}\` ${subject}`);
  else out.push('- Sin commits nuevos.');
  out.push('');
  if (previous) out.push(`**Comparar:** [${previous}...${tag}](../../compare/${previous}...${tag})`, '');
  out.push(`Historial completo: [CHANGELOG.md](../../blob/${tag}/CHANGELOG.md).`);
  return out.join('\n');
}

function packageZip() {
  const value = version();
  const dist = path.join(root, 'dist');
  fs.mkdirSync(dist, { recursive: true });
  const file = path.join(dist, zipName(value));
  // git archive respeta export-ignore (.gitattributes): sin tests, scripts ni herramientas de desarrollo.
  git('archive', '--format=zip', '--prefix=os_security/', '-o', file, 'HEAD');
  const sha = crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
  console.log(`${path.relative(root, file)}  ${(fs.statSync(file).size / 1024).toFixed(1)} KB  sha256:${sha}`);
}

const [command, argument] = process.argv.slice(2);
if (command === 'version') console.log(version());
else if (command === 'check') {
  if (argument !== `v${version()}`) { console.error(`La etiqueta ${argument} no coincide con la version v${version()} de config/config.lua`); process.exit(1); }
  if (!changelog(version()).body) { console.error(`CHANGELOG.md no tiene seccion para ${version()}`); process.exit(1); }
  console.log(`Version v${version()} correcta`);
} else if (command === 'package') packageZip();
else if (command === 'notes') process.stdout.write(notes(argument || `v${version()}`) + '\n');
else { console.error('Uso: node scripts/release.cjs version|check <tag>|package|notes [tag]'); process.exit(1); }
