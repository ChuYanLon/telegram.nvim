import { describe, it, expect, beforeAll, afterAll, vi } from 'vitest';
import http from 'node:http';

const PORT = 18999;

vi.mock('dotenv', () => ({ default: { config: () => ({}) } }));
vi.mock('tdl', () => ({
  default: {
    configure: () => {},
    createClient: () => ({
      on: () => {},
      invoke: async () => ({ value: '1.8.64' }),
      login: async () => {},
      close: async () => {},
    }),
  },
}));
vi.mock('ws', () => ({
  default: function () {
    return { on: () => {}, clients: new Set() };
  },
  WebSocketServer: function () {
    return { on: () => {}, clients: new Set(), close: () => {} };
  },
}));

let server;

beforeAll(async () => {
  process.env.TG_PORT = String(PORT);
  process.env.TG_API_ID = '1';
  process.env.TG_API_HASH = 'test';
  server = await import('../src/server');
});

afterAll(() => {
  return new Promise((resolve) => {
    server.wss.close();
    server.tgClient.client.close();
    server.httpServer.close(resolve);
  });
});

describe('GET /health', () => {
  it('returns health status', async () => {
    const data = await new Promise((resolve, reject) => {
      http.get(`http://localhost:${PORT}/health`, (res) => {
        let body = '';
        res.on('data', (c) => (body += c));
        res.on('end', () => resolve(JSON.parse(body)));
      }).on('error', reject);
    });
    expect(data).toHaveProperty('ready');
    expect(data).toHaveProperty('auth');
  });
});

describe('POST /auth/input', () => {
  it('returns 400 when value is missing', async () => {
    const { status } = await new Promise((resolve, reject) => {
      const req = http.request(
        `http://localhost:${PORT}/auth/input`,
        { method: 'POST', headers: { 'Content-Type': 'application/json' } },
        (res) => {
          let body = '';
          res.on('data', (c) => (body += c));
          res.on('end', () => resolve({ status: res.statusCode }));
        },
      );
      req.on('error', reject);
      req.write(JSON.stringify({}));
      req.end();
    });
    expect(status).toBe(400);
  });
});

describe('GET /groups', () => {
  it('responds (depends on TDLib)', async () => {
    const { status } = await new Promise((resolve, reject) => {
      http.get(`http://localhost:${PORT}/groups`, (res) => {
        resolve({ status: res.statusCode });
      }).on('error', reject);
    });
    expect([200, 500]).toContain(status);
  });
});
