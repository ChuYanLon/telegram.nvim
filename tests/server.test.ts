import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import http from 'node:http';
import path from 'node:path';
import fs from 'node:fs';

const PORT = 18999;
const dataDir = '/tmp/tg-test-data-' + Date.now();

let fake: any;
let instance: any;
let app: any;
let httpServer: any;

function get(path: string): Promise<{ status: number; body: any }> {
  return new Promise((resolve, reject) => {
    http.get(`http://localhost:${PORT}${path}`, (res) => {
      let body = '';
      res.on('data', (c) => (body += c));
      res.on('end', () => resolve({ status: res.statusCode, body: body ? JSON.parse(body) : null }));
    }).on('error', reject);
  });
}

function post(path: string, data: any): Promise<{ status: number; body: any }> {
  return new Promise((resolve, reject) => {
    const req = http.request(
      `http://localhost:${PORT}${path}`,
      { method: 'POST', headers: { 'Content-Type': 'application/json' } },
      (res) => {
        let body = '';
        res.on('data', (c) => (body += c));
        res.on('end', () => resolve({ status: res.statusCode, body: body ? JSON.parse(body) : null }));
      },
    );
    req.on('error', reject);
    req.write(JSON.stringify(data));
    req.end();
  });
}

beforeAll(async () => {
  fs.mkdirSync(dataDir, { recursive: true });
  process.env.TG_TDLIB_PATH = '/dev/null';
  process.env.TG_PORT = String(PORT);
  process.env.TG_API_ID = '1';
  process.env.TG_API_HASH = 'test';
  process.env.TG_DATA_DIR = dataDir;

  const { default: TelegramLSPClient } = await import('../src/client');
  const FakeTdClient = (await import('./fake-td-client')).default;
  fake = new FakeTdClient();
  fake.addUser({ id: 1, first_name: 'Alice' });
  fake.addChat({ id: -1001, title: 'TG' });

  instance = new TelegramLSPClient({ client: fake });
  instance._ready = true;

  const express = (await import('express')).default;
  app = express();
  app.use(express.json());

  // Health endpoint
  app.get('/health', (_req: any, res: any) => {
    res.json({ ready: true, auth: { state: 'authorized' } });
  });

  app.get('/chats', async (_req: any, res: any) => {
    try {
      const chats = await instance.getAllChats();
      res.json(chats);
    } catch (err: any) {
      res.status(500).json({ error: err.message });
    }
  });

  app.get('/groups', async (_req: any, res: any) => {
    try {
      const groups = await instance.getGroups();
      res.json(groups);
    } catch (err: any) {
      res.status(500).json({ error: err.message });
    }
  });

  app.get('/messages', async (req: any, res: any) => {
    try {
      const { chatId, limit, before, after, beforeDate, afterDate } = req.query;
      if (!chatId) { res.status(400).json({ error: 'chatId is required' }); return; }
      if (after) {
        const result = await instance.getMessagesAfter(Number(chatId), Number(after), Number(afterDate), limit ? Number(limit) : 50);
        res.json(result);
      } else {
        const result = await instance.getMessages(Number(chatId), limit ? Number(limit) : 50, before ? Number(before) : undefined, beforeDate ? Number(beforeDate) : undefined);
        res.json(result);
      }
    } catch (err: any) {
      res.status(500).json({ error: err.message });
    }
  });

  app.post('/sendMessage', async (req: any, res: any) => {
    try {
      const { chatId, text, replyTo } = req.body;
      if (!chatId || !text) { res.status(400).json({ error: 'chatId and text are required' }); return; }
      const result = await instance.sendMessage(Number(chatId), text, replyTo);
      res.json(result);
    } catch (err: any) {
      res.status(500).json({ error: err.message });
    }
  });

  app.post('/editMessage', async (req: any, res: any) => {
    try {
      const { chatId, messageId, text } = req.body;
      if (!chatId || !messageId || !text) { res.status(400).json({ error: 'chatId, messageId and text are required' }); return; }
      const msg = await instance.editMessage(Number(chatId), Number(messageId), text);
      res.json({ ok: true, message: msg });
    } catch (err: any) {
      res.status(500).json({ error: err.message });
    }
  });

  app.post('/deleteMessage', async (req: any, res: any) => {
    try {
      const { chatId, messageId } = req.body;
      if (!chatId || !messageId) { res.status(400).json({ error: 'chatId and messageId are required' }); return; }
      const result = await instance.deleteMessage(Number(chatId), Number(messageId));
      res.json(result);
    } catch (err: any) {
      res.status(500).json({ error: err.message });
    }
  });

  app.post('/forwardMessages', async (req: any, res: any) => {
    try {
      const { fromChatId, messageIds, toChatId } = req.body;
      if (!fromChatId || !messageIds || !toChatId) { res.status(400).json({ error: 'fromChatId, messageIds, toChatId are required' }); return; }
      const result = await instance.forwardMessages(Number(fromChatId), messageIds.map(Number), Number(toChatId));
      res.json(result);
    } catch (err: any) {
      res.status(500).json({ error: err.message });
    }
  });

  app.post('/chat/open', async (req: any, res: any) => {
    try {
      const { chatId } = req.body;
      if (!chatId) { res.status(400).json({ error: 'chatId is required' }); return; }
      await instance.openChat(Number(chatId));
      res.json({ ok: true });
    } catch (err: any) {
      res.status(500).json({ error: err.message });
    }
  });

  app.post('/chat/close', async (req: any, res: any) => {
    try {
      const { chatId } = req.body;
      if (!chatId) { res.status(400).json({ error: 'chatId is required' }); return; }
      await instance.closeChat(Number(chatId));
      res.json({ ok: true });
    } catch (err: any) {
      res.status(500).json({ error: err.message });
    }
  });

  httpServer = app.listen(PORT);
});

afterAll(() => {
  httpServer?.close();
  fs.rmSync(dataDir, { recursive: true, force: true });
});

describe('Express server routes', () => {
  it('GET /health returns auth state', async () => {
    const { body } = await get('/health');
    expect(body).toEqual({ ready: true, auth: { state: 'authorized' } });
  });

  it('GET /chats returns chat list', async () => {
    const { body } = await get('/chats');
    expect(Array.isArray(body)).toBe(true);
  });

  it('GET /groups returns groups', async () => {
    const { body } = await get('/groups');
    expect(Array.isArray(body)).toBe(true);
  });

  it('GET /messages requires chatId', async () => {
    const { status } = await get('/messages');
    expect(status).toBe(400);
  });

  it('GET /messages with chatId returns messages', async () => {
    const { body } = await get('/messages?chatId=-1001');
    expect(body.chat.id).toBe(-1001);
    expect(Array.isArray(body.messages)).toBe(true);
  });

  it('GET /messages with before/after uses date-based filtering', async () => {
    const { body } = await get('/messages?chatId=-1001&limit=5&before=0&beforeDate=1000000');
    expect(Array.isArray(body.messages)).toBe(true);
  });

  it('POST /sendMessage requires text', async () => {
    const { status } = await post('/sendMessage', { chatId: -1001 });
    expect(status).toBe(400);
  });

  it('POST /sendMessage with text succeeds', async () => {
    const { body } = await post('/sendMessage', { chatId: -1001, text: 'hello' });
    expect(body.id).toBeGreaterThan(0);
  });

  it('POST /editMessage requires all fields', async () => {
    const { status } = await post('/editMessage', { chatId: -1001 });
    expect(status).toBe(400);
  });

  it('POST /editMessage succeeds', async () => {
    const { body } = await post('/editMessage', { chatId: -1001, messageId: 1, text: 'edited' });
    expect(body.ok).toBe(true);
  });

  it('POST /deleteMessage requires chatId and messageId', async () => {
    const { status } = await post('/deleteMessage', { chatId: -1001 });
    expect(status).toBe(400);
  });

  it('POST /deleteMessage succeeds', async () => {
    const { body } = await post('/deleteMessage', { chatId: -1001, messageId: 1 });
    expect(body.ok).toBe(true);
  });

  it('POST /forwardMessages requires all fields', async () => {
    const { status } = await post('/forwardMessages', { fromChatId: -1001 });
    expect(status).toBe(400);
  });

  it('POST /forwardMessages succeeds', async () => {
    const { body } = await post('/forwardMessages', { fromChatId: -1001, messageIds: [1], toChatId: -1002 });
    expect(body.ok).toBe(true);
  });

  it('POST /chat/open requires chatId', async () => {
    const { status } = await post('/chat/open', {});
    expect(status).toBe(400);
  });

  it('POST /chat/open succeeds', async () => {
    const { body } = await post('/chat/open', { chatId: -1001 });
    expect(body.ok).toBe(true);
  });

  it('POST /chat/close succeeds', async () => {
    const { body } = await post('/chat/close', { chatId: -1001 });
    expect(body.ok).toBe(true);
  });
}, 30000);
