#!/usr/bin/env node
// Probe opencode TUI under a pty. Answers terminal queries like a real
// terminal, so we can see whether the TUI renders and which query blocks it.
const { spawn } = require('child_process');
const fs = require('fs');

const respond = process.argv.includes('--respond');
const timeout = 10;
const out = process.env.HOME + '/oc_probe.log';
const cmd = [process.env.HOME + '/bin/opencode'];

const nodePty = (() => {
  // Use python-free approach: node-pty unavailable, so shell out to `script`
  return null;
})();

const { spawn: spawnPty } = require('child_process');
// Use `script -qec` (util-linux) to allocate a pty; feed responses via a fifo? 
// Simpler: use `script` with stdin from a pipe we control.
const cp = spawn('script', ['-qec', cmd.map(JSON.stringify).join(' '), '/dev/null'], {
  stdio: ['pipe', 'pipe', 'inherit'],
  env: { ...process.env, TERM: 'xterm-256color', COLORTERM: 'truecolor' },
});

let log = fs.createWriteStream(out);
let buf = '';
const start = Date.now();
const W = (s) => cp.stdin.write(s);

function respondTo(data) {
  let out = '';
  if (data.includes(']10;?')) out += '\x1b]10;rgb:ffff/ffff/ffff\x1b\\';
  if (data.includes(']11;?')) out += '\x1b]11;rgb:0000/0000/0000\x1b\\';
  if (data.includes(']4;0;?')) out += '\x1b]4;0;rgb:0000/0000/0000\x1b\\';
  if (data.includes(']99;')) out += '\x1b]99;i=opentui-notifications:p=ok;\x1b\\';
  if (data.includes(']1337;Capabilities')) out += '\x1b]1337;Capabilities=1\x1b\\';
  if (data.includes(']66;')) out += '\x1b]66;\x1b\\';
  if (data.includes('[>0q')) out += '\x1bP>|probe 0\x1b\\';
  if (data.includes('P+q')) out += '\x1bP1+r4d73=\x1b\\';
  if (data.includes('$p')) out += '\x1b[?1000;1002;1003;1006;2004$y';
  if (data.includes('[?u')) out += '\x1b[?1;2;3;4;6;9;22;25;68;1001;1002;1003;1005;1006;1015;1016;1017u';
  if (data.includes('[6n')) out += '\x1b[1;1R';
  if (data.includes('[14t')) out += '\x1b[4;1;80;24t';
  if (data.includes('[>c')) out += '\x1b[>41;0;0c';
  if (data.includes('[c') && !data.includes('[>c')) out += '\x1b[?62;c';
  return out;
}

cp.stdout.on('data', (chunk) => {
  log.write(chunk);
  buf = (buf + chunk.toString('latin1')).slice(-8192);
  if (respond) {
    const r = respondTo(buf);
    if (r) { W(r); }
  }
});

const timer = setInterval(() => {
  if (Date.now() - start > timeout * 1000) {
    clearInterval(timer);
    cp.kill('SIGKILL');
    setTimeout(() => process.exit(0), 200);
  }
}, 1000);
cp.on('exit', () => { clearInterval(timer); setTimeout(() => process.exit(0), 200); });
