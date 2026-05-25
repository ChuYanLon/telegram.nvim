const { describe, it, before, after, mock } = require('node:test');
const assert = require('node:assert/strict');
const http = require('http');

let server;
const PORT = 18999;

mock.module('tdl', {
  defaultExport: {
    configure: () => {},
    createClient: () => ({
      on: () => {},
      invoke: async () => ({}),
      close: async () => {},
    }),
  },
});
mock.module('ws', {
  defaultExport: function () { return { on: () => {}, clients: new Set() }; },
  namedExports: { WebSocketServer: function () { return { on: () => {}, clients: new Set() }; } },
});

before(() => {
  process.env.TG_PORT = String(PORT);
  process.env.TG_API_ID = '1';
  process.env.TG_API_HASH = 'test';
  server = require('../src/server');
});

after(() => {
  if (server && server.close) server.close();
});

describe('GET /health', () => {
  it('returns health status', async () => {
    const data = await new Promise((resolve, reject) => {
      http.get(`http://localhost:${PORT}/health`, (res) => {
        let body = '';
        res.on('data', (c) => body += c);
        res.on('end', () => resolve(JSON.parse(body)));
      }).on('error', reject);
    });
    assert.ok(data.hasOwnProperty('ready'));
    assert.ok(data.hasOwnProperty('auth'));
  });
});

describe('POST /auth/input', () => {
  it('returns 400 when value is missing', async () => {
    const { status } = await new Promise((resolve, reject) => {
      const req = http.request(`http://localhost:${PORT}/auth/input`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
      }, (res) => {
        let body = '';
        res.on('data', (c) => body += c);
        res.on('end', () => resolve({ status: res.statusCode, body: JSON.parse(body) }));
      });
      req.on('error', reject);
      req.write(JSON.stringify({}));
      req.end();
    });
    assert.equal(status, 400);
  });
});

describe('GET /groups', () => {
  it('responds (depends on TDLib)', async () => {
    const { status } = await new Promise((resolve, reject) => {
      http.get(`http://localhost:${PORT}/groups`, (res) => {
        resolve({ status: res.statusCode });
      }).on('error', reject);
    });
    assert.ok(status === 200 || status === 500);
  });
});
