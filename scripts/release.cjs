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

// Raiz del repositorio: el directorio actual (en Actions el script se ejecuta desde una copia en RUNNER_TEMP).
const root = process.cwd();
const git = (...args) => execFileSync('git', args, { cwd: root, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }).trim();

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
  const log = git('log', '--no-merges', '--format=%h%x09%an%x09%s', range);
  return { previous, items: log ? log.split('\n').map(line => line.split('\t')) : [] };
}

// URL del repositorio: la de GitHub Actions o la del remoto origin.
function repository() {
  if (process.env.GITHUB_REPOSITORY) return `https://github.com/${process.env.GITHUB_REPOSITORY}`;
  try {
    const remote = git('remote', 'get-url', 'origin').replace(/\.git$/, '');
    const match = remote.match(/github\.com[:/](.+\/.+)$/);
    if (match) return `https://github.com/${match[1]}`;
  } catch { /* sin remoto */ }
  return '';
}

// Mismo formato que las releases de vMenu: presentacion, tabla de descarga, instalacion,
// "Cambios en ..." (hash, autor y mensaje de cada commit) y enlace a la documentacion.
function notes(tag) {
  const value = tag.replace(/^v/, '');
  const { previous, items } = commits(tag);
  const repo = repository();
  const docs = `${repo}/blob/${tag}/README.md`;
  const out = [];
  out.push('Una versión de OS Security (Gruppe Sechs) para FiveM. Descarga el zip y ponlo en tu servidor.', '');
  out.push('| Tu servidor | Descarga |', '| :---: | :---: |', `| FiveM (GTA V Legacy) | \`${zipName(value)}\` |`, '');
  out.push(`¿Servidor nuevo? Descomprime el zip en \`resources/\` (la carpeta debe llamarse \`os_security\`), añade \`ensure os_security\` a tu \`server.cfg\` y reinicia. Los permisos ACE están en la [guía de instalación](${docs}).`, '');
  out.push('¿Actualizando? Sustituye la carpeta `os_security` **conservando `data/`** (inventario, montajes y dispositivos) y reinicia el servidor completo.', '');
  out.push('¿Integraciones? `os_inventory`, `os_devtools`, `os_notify` y `os_admin` son opcionales: sin ellas OS Security funciona por sí solo, con su propio inventario y sin frameworks ni MySQL.', '');
  out.push(`## Cambios en OS Security ${tag}`, '');
  if (items.length) for (const [hash, author, subject] of items) out.push(`- \`${hash}\` (${author}) ${subject}`);
  else out.push('- Sin cambios de código.');
  out.push('');
  out.push(`Docs: [OS Security](${docs}). Historial: [CHANGELOG](${repo}/blob/${tag}/CHANGELOG.md).${previous ? ` Comparar: [${previous}...${tag}](${repo}/compare/${previous}...${tag}).` : ''}`);
  return out.join('\n');
}

function packageZip() {
  const value = version();
  const dist = path.join(root, 'dist');
  fs.mkdirSync(dist, { recursive: true });
  const file = path.join(dist, zipName(value));
  // git archive respeta export-ignore (.gitattributes): sin tests, scripts ni herramientas de desarrollo.
  git('archive', '--format=zip', '--prefix=os_security/', '-o', file, 'HEAD');
  // Copia con nombre fijo: el enlace del README (releases/latest/download/os_security.zip) baja siempre la ultima.
  fs.copyFileSync(file, path.join(dist, 'os_security.zip'));
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
