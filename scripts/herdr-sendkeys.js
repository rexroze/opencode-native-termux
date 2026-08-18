#!/usr/bin/env node
// Minimal herdr client-protocol injector: connects to herdr-client.sock,
// handshakes, clears the focused pane's line buffer and types a command.
// Used to test agent detection. Wire format: u32 LE length + bincode(standard).
const net = require('net');
const sock = process.env.HOME + '/.config/herdr/herdr-client.sock';
const cmd = process.argv[2] || 'opencode';
const pre = process.argv[3] === 'nokill' ? '' : '\x15'; // Ctrl+U clear line by default

function varint(n) { // unsigned LEB128
  const out = [];
  do { let b = n & 0x7f; n = Math.floor(n / 128); if (n) b |= 0x80; out.push(b); } while (n);
  return out;
}
function send(c, bytes) {
  const payload = Buffer.from(bytes);
  const frame = Buffer.alloc(4 + payload.length);
  frame.writeUInt32LE(payload.length, 0);
  payload.copy(frame, 4);
  c.write(frame);
}

const c = net.connect(sock);
c.on('connect', () => {
  // ClientMessage::Hello { version:19, cols, rows, cell px, RenderEncoding::SemanticFrame, Keybindings::Server, LaunchMode::App }
  send(c, [0, ...varint(19), ...varint(80), ...varint(24), ...varint(0), ...varint(0), ...varint(0), ...varint(0), ...varint(0)]);
  setTimeout(() => {
    const data = Buffer.from(pre + cmd + '\r', 'latin1');
    // ClientMessage::Input { data: Vec<u8> }
    send(c, [1, ...varint(data.length), ...data]);
    console.log('sent:', JSON.stringify(pre + cmd + '\r'));
  }, 600);
  setTimeout(() => c.destroy(), 2000);
});
c.on('data', () => { /* ignore frames (Welcome + renders) */ });
c.on('error', (e) => { console.error('error:', e.message); process.exit(1); });
c.on('close', () => process.exit(0));
