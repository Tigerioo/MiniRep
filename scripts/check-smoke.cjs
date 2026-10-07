const { spawnSync } = require('node:child_process');
const path = require('node:path');

// fengari-node-cli 0.1.0 prints Lua failures to stderr but can exit with 0.
// Preserve its output and make those failures visible to npm and CI.
const result = spawnSync(process.execPath, [
  require.resolve('fengari-node-cli/src/lua-cli.js'),
  'tests/smoke.lua',
], {
  cwd: path.resolve(__dirname, '..'),
  encoding: 'utf8',
});

if (result.stdout) process.stdout.write(result.stdout);
if (result.stderr) process.stderr.write(result.stderr);
if (result.error) throw result.error;
process.exitCode = result.status !== 0 ? (result.status || 1) : (result.stderr ? 1 : 0);
