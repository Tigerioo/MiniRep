const fs = require('node:fs');
const path = require('node:path');
const lua = require('luaparse');
const root = path.resolve(__dirname, '../MiniRep');
const toc = fs.readFileSync(path.join(root, 'MiniRep.toc'), 'utf8');
if (!/^## Interface: 50504$/m.test(toc)) throw new Error('Unexpected interface');
if (!/^## SavedVariablesPerCharacter: MiniRepDB$/m.test(toc)) throw new Error('Missing per-character database');
const files = toc.split(/\r?\n/).map(x => x.trim()).filter(x => x && !x.startsWith('#'));
for (const file of files) {
  lua.parse(fs.readFileSync(path.join(root, file), 'utf8'), { luaVersion: '5.1' });
  console.log('Lua 5.1 syntax OK: ' + file);
}
if (files.length !== 5) throw new Error('Unexpected package file list');
console.log('TOC load order and per-character declaration OK');
