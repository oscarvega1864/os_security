// Development only. All fixtures and simulated FiveM files live in WASM memory.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { LuaFactory } = require('wasmoon');

async function main() {
  const root = path.resolve(__dirname, '..');
  const factory = new LuaFactory();
  const files = [];
  function collect(directory) {
    for (const entry of fs.readdirSync(path.join(root, directory), { withFileTypes: true })) {
      if (['.git', 'node_modules', '.tools', 'data'].includes(entry.name)) continue;
      const relative = path.join(directory, entry.name).replaceAll('\\', '/');
      if (entry.isDirectory()) collect(relative);
      else if (relative.endsWith('.lua')) files.push(relative);
    }
  }
  collect('');
  for (const file of files) await factory.mountFile(`/repo/${file}`, fs.readFileSync(path.join(root, file)));
  for (const file of ['web/index.html', 'web/style.css', 'web/app.js', 'web/minigame.js']) await factory.mountFile(`/repo/${file}`, fs.readFileSync(path.join(root, file)));
  const lua = await factory.createEngine({ enableProxy: false });
  try {
    // The optional codec is read only, never copied into the repository.
    const codecIndex = process.argv.indexOf('--codec');
    if (codecIndex !== -1) {
      assert(process.argv[codecIndex + 1], '--codec requires a Lua JSON codec path');
      await factory.mountFile('/codec.lua', fs.readFileSync(path.resolve(process.argv[codecIndex + 1])));
      await lua.doFile('/codec.lua');
      console.log('JSON codec: supplied Lua library (read only)');
    } else {
      lua.global.set('__encode', data => JSON.stringify(data));
      lua.global.set('__decode', text => JSON.parse(text, (_key, value) => {
        if (value === null) throw new Error('null is outside the device contract');
        return value;
      }));
      await lua.doString(`json = {
        encode = __encode,
        decode = function(text) return __decode(text), #text + 1 end
      }`);
      console.log('JSON codec: JSON.stringify/JSON.parse bridge (not the FiveM codec)');
    }
    lua.global.set('__luaFiles', files);
    lua.global.set('__testResult', (name, passed, error) => {
      console.log(`${passed ? 'PASS' : 'FAIL'} ${name}${passed ? '' : `: ${error}`}`);
    });
    await lua.doString(`assert(_VERSION == 'Lua 5.4'); print('Runtime: ' .. _VERSION)`);
    await lua.doFile('/repo/tests/core_spec.lua');
    const failures = lua.global.get('__failures');
    assert.equal(failures, 0, `${failures} Lua test(s) failed`);
  } finally {
    lua.global.close();
  }
}

main().catch(error => { console.error(error); process.exitCode = 1; });
