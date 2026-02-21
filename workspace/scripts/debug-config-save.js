#!/usr/bin/env node
/**
 * Conecta ao gateway, faz config.get e depois config.set com o mesmo config.
 * Imprime a resposta completa (incluindo details.issues) para ver o erro real de "invalid config".
 * Uso: node workspace/scripts/debug-config-save.js
 * Requer: OPENCLAW_GATEWAY_TOKEN no .env ou variável de ambiente.
 */
const http = require('http');
const crypto = require('crypto');
const path = require('path');
const fs = require('fs');

// Carregar .env se existir
const envPath = path.join(__dirname, '../../.env');
if (fs.existsSync(envPath)) {
  const env = fs.readFileSync(envPath, 'utf8');
  env.split('\n').forEach(line => {
    const m = line.match(/^\s*([A-Za-z_][A-Za-z0-9_]*)=(.*)$/);
    if (m && !process.env[m[1]]) process.env[m[1]] = m[2].replace(/^["']|["']$/g, '').trim();
  });
}

const TOKEN = process.env.OPENCLAW_GATEWAY_TOKEN || '97fb8d9c326a7d30f9b888d825c68d45f7cc3fad919ca763';
const DEBUG = process.env.DEBUG === '1';
const GATEWAY = process.env.OPENCLAW_GATEWAY_URL || '127.0.0.1:18789';

function uuid() { return crypto.randomUUID(); }

function sendWsFrame(socket, data) {
  const payload = Buffer.from(data);
  const mask = crypto.randomBytes(4);
  let header;
  if (payload.length <= 125) {
    header = Buffer.alloc(6); header[0] = 0x81; header[1] = 0x80 | payload.length; mask.copy(header, 2);
  } else if (payload.length <= 65535) {
    header = Buffer.alloc(8); header[0] = 0x81; header[1] = 0x80 | 126; header.writeUInt16BE(payload.length, 2); mask.copy(header, 4);
  } else {
    header = Buffer.alloc(14); header[0] = 0x81; header[1] = 0x80 | 127; header.writeBigUInt64BE(BigInt(payload.length), 2); mask.copy(header, 10);
  }
  const masked = Buffer.alloc(payload.length);
  for (let i = 0; i < payload.length; i++) masked[i] = payload[i] ^ mask[i % 4];
  socket.write(Buffer.concat([header, masked]));
}

function parseWsFrames(d) {
  const frames = []; let i = 0;
  while (i + 2 <= d.length) {
    const b1 = d[i]; const b2 = d[i+1]; let len = b2 & 0x7f; i += 2;
    if (len === 126) { if (i+2 > d.length) break; len = d.readUInt16BE(i); i += 2; }
    else if (len === 127) { if (i+8 > d.length) break; len = Number(d.readBigUInt64BE(i)); i += 8; }
    if (i + len > d.length) break;
    const payload = d.slice(i, i + len).toString(); i += len;
    if ((b1 & 0x0f) === 1) frames.push(payload);
  }
  return frames;
}

const key = crypto.randomBytes(16).toString('base64');
const [host, port] = GATEWAY.split(':');
const req = http.request({
  hostname: host, port: parseInt(port, 10), path: '/', method: 'GET',
  headers: { 'Connection': 'Upgrade', 'Upgrade': 'websocket', 'Sec-WebSocket-Version': '13', 'Sec-WebSocket-Key': key }
});

req.on('upgrade', (res, socket) => {
  let authed = false;
  let configPayload = null;
  let baseHash = null;
  let reqId = null;

  socket.on('data', (d) => {
    parseWsFrames(d).forEach(f => {
      try {
        const msg = JSON.parse(f);
        if (DEBUG) console.error('[debug]', msg.type || msg.event || '?', msg.id || '', Object.keys(msg.payload || {}).slice(0, 5).join(','));
        if (msg.event === 'connect.challenge') {
          sendWsFrame(socket, JSON.stringify({
            type: 'req', id: uuid(), method: 'connect',
            params: {
              minProtocol: 1, maxProtocol: 1,
              client: { id: 'debug-script', version: 'dev', platform: 'darwin', mode: 'backend' },
              caps: [], auth: { token: TOKEN }, role: 'operator', scopes: ['operator.admin']
            }
          }));
          return;
        }
        if (msg.type === 'res' && !authed) {
          authed = true;
          reqId = uuid();
          sendWsFrame(socket, JSON.stringify({ type: 'req', id: reqId, method: 'config.get', params: {} }));
          return;
        }
        if (msg.id === reqId && msg.type === 'res') {
          const pl = msg.payload;
          const ok = pl?.ok !== false;
          configPayload = pl?.config ?? pl;
          baseHash = pl?.hash ?? pl?.baseHash ?? null;
          if (!ok && !configPayload) {
            console.error('config.get falhou:', JSON.stringify(pl, null, 2));
            socket.destroy(); process.exit(1);
          }
          if (!baseHash && pl && typeof pl.hash !== 'undefined') baseHash = pl.hash;
          if (!baseHash) {
            console.error('config.get não devolveu hash.');
            socket.destroy(); process.exit(1);
          }
          const raw = typeof pl?.raw === 'string' ? pl.raw : (typeof configPayload === 'string' ? configPayload : JSON.stringify(configPayload, null, 2));
          const setId = uuid();
          sendWsFrame(socket, JSON.stringify({ type: 'req', id: setId, method: 'config.set', params: { raw, baseHash } }));
          reqId = setId;
          return;
        }
        if (msg.id === reqId && msg.type === 'res') {
          const ok = msg.payload?.ok;
          if (ok) {
            console.log('OK: config.set aceite.');
            socket.destroy(); process.exit(0);
          }
          console.error('config.set rejeitado.\n');
          const issues = msg.payload?.details?.issues ?? msg.payload?.issues ?? [];
          if (issues.length) {
            console.error('--- Erros de validação (details.issues) ---');
            issues.forEach((iss, i) => {
              const path = typeof iss === 'string' ? iss : (iss.path ?? iss.message ?? '<root>');
              const message = typeof iss === 'string' ? '' : (iss.message || '');
              console.error(`${i + 1}. ${path}${message ? ': ' + message : ''}`);
            });
            console.error('');
          }
          console.error('Resposta completa (para inspeção):');
          console.error(JSON.stringify(msg, null, 2));
          socket.destroy(); process.exit(1);
        }
      } catch (e) {}
    });
  });

  setTimeout(() => {
    console.error('Timeout 15s.');
    socket.destroy();
    process.exit(1);
  }, 15000);
});

req.on('error', (e) => {
  console.error('Erro de conexão:', e.message);
  process.exit(1);
});
req.end();
