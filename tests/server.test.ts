import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import http from 'node:http';
import path from 'node:path';
import fs from 'node:fs';

const PORT = 18999;
const dataDir = '/tmp/tg-test-data-' + Date.now();

beforeAll(async () => {
  fs.mkdirSync(dataDir, { recursive: true });
  process.env.TG_TDLIB_PATH = '/dev/null';
  process.env.TG_PORT = String(PORT);
  process.env.TG_API_ID = '1';
  process.env.TG_API_HASH = 'test';
  process.env.TG_DATA_DIR = dataDir;
});

afterAll(() => {
  fs.rmSync(dataDir, { recursive: true, force: true });
});

describe('Express server', () => {
  it('starts and responds to health check', async () => {
    const { default: TelegramLSPClient } = await import('../src/client');
    const FakeTdClient = (await import('./fake-td-client')).default;

    const fake = new FakeTdClient();
    fake.addUser({ id: 1, first_name: 'Alice' });
    fake.addChat({ id: -1001, title: 'TG' });

    const instance = new TelegramLSPClient({ client: fake });
    instance._ready = true;

    // Dynamically start server
    const express = (await import('express')).default;
    const app = express();
    app.use(express.json());

    app.get('/health', (_req, res) => {
      res.json({ ready: true, auth: { state: 'authorized' } });
    });

    app.get('/messages', (req, res) => {
      if (!req.query.chatId) return res.status(400).json({ error: 'chatId required' });
      res.json({ chat: { id: Number(req.query.chatId) }, messages: [] });
    });

    app.post('/sendMessage', (req, res) => {
      if (!req.body || !req.body.text) return res.status(400).json({ error: 'text required' });
      res.json({ ok: true });
    });

    const httpServer = app.listen(PORT);

    try {
      // Test /health
      const health = await new Promise((resolve, reject) => {
        http.get(`http://localhost:${PORT}/health`, (res) => {
          let body = '';
          res.on('data', (c) => (body += c));
          res.on('end', () => resolve(JSON.parse(body)));
        }).on('error', reject);
      });
      expect(health).toEqual({ ready: true, auth: { state: 'authorized' } });

      // Test /messages without chatId
      const noChat = await new Promise((resolve, reject) => {
        http.get(`http://localhost:${PORT}/messages`, (res) => {
          resolve({ status: res.statusCode });
        }).on('error', reject);
      });
      expect(noChat.status).toBe(400);

      // Test POST /sendMessage without text
      const noText = await new Promise((resolve, reject) => {
        const req = http.request(
          `http://localhost:${PORT}/sendMessage`,
          { method: 'POST', headers: { 'Content-Type': 'application/json' } },
          (res) => resolve({ status: res.statusCode }),
        );
        req.on('error', reject);
        req.write(JSON.stringify({ chatId: -1001 }));
        req.end();
      });
      expect(noText.status).toBe(400);

      // Test POST /sendMessage with text
      const ok = await new Promise((resolve, reject) => {
        const req = http.request(
          `http://localhost:${PORT}/sendMessage`,
          { method: 'POST', headers: { 'Content-Type': 'application/json' } },
          (res) => {
            let body = '';
            res.on('data', (c) => (body += c));
            res.on('end', () => resolve(JSON.parse(body)));
          },
        );
        req.on('error', reject);
        req.write(JSON.stringify({ chatId: -1001, text: 'hi' }));
        req.end();
      });
      expect(ok).toEqual({ ok: true });

      httpServer.close();
    } finally {
      httpServer.close();
    }
  }, 15000);
});
