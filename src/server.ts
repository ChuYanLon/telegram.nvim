import express from 'express';
import { WebSocketServer } from 'ws';
import TelegramLSPClient from './client';

const PORT = Number(process.env.TG_PORT) || 8080;
const WS_PORT = Number(process.env.TG_WS_PORT) || PORT + 1;

const app = express();
const wss = new WebSocketServer({ port: WS_PORT });

const tgClient = new TelegramLSPClient();

declare global {
  var broadcast: ((data: unknown) => void) | undefined;
}

global.broadcast = (data: unknown) => {
  wss.clients.forEach((client) => {
    if (client.readyState === 1) {
      client.send(JSON.stringify(data));
    }
  });
};

wss.on('connection', (ws) => {
  console.log('Neovim client connected');
});

app.use(express.json());

app.get('/health', (_req, res) => {
  res.json({
    ready: tgClient.isReady(),
    auth: tgClient.getAuthState(),
  });
});

app.post('/auth/input', async (req, res) => {
  try {
    const { value } = req.body;
    if (value === undefined || value === null) {
      res.status(400).json({ error: 'value is required' });
      return;
    }
    const ok = await tgClient.submitAuthInput(String(value));
    if (ok) {
      res.json({ ok: true });
    } else {
      res.status(400).json({ error: 'No pending auth input' });
    }
  } catch (err) {
    res.status(500).json({ error: (err as Error).message });
  }
});

app.get('/groups', async (_req, res) => {
  try {
    const groups = await tgClient.getGroups();
    res.json(groups);
  } catch (err) {
    res.status(500).json({ error: (err as Error).message });
  }
});

app.post('/chat/viewMessages', async (req, res) => {
  try {
    const { chatId, messageId } = req.body;
    if (!chatId || !messageId) { res.status(400).json({ error: 'chatId and messageId are required' }); return; }
    await tgClient.viewMessages(Number(chatId), Number(messageId));
    res.json({ ok: true });
  } catch (err) {
    res.status(500).json({ error: (err as Error).message });
  }
});

app.post('/chat/open', async (req, res) => {
  try {
    const { chatId } = req.body;
    if (!chatId) { res.status(400).json({ error: 'chatId is required' }); return; }
    await tgClient.openChat(chatId);
    res.json({ ok: true });
  } catch (err) {
    res.status(500).json({ error: (err as Error).message });
  }
});

app.post('/chat/action', async (req, res) => {
  try {
    const { chatId, action } = req.body;
    if (!chatId || !action) { res.status(400).json({ error: 'chatId and action are required' }); return; }
    await tgClient.sendChatAction(chatId, action);
    res.json({ ok: true });
  } catch (err) {
    res.status(500).json({ error: (err as Error).message });
  }
});

app.get('/chat', async (req, res) => {
  try {
    const { chatId } = req.query;
    if (!chatId) { res.status(400).json({ error: 'chatId is required' }); return; }
    const chat = await tgClient.getChat(Number(chatId));
    res.json(chat);
  } catch (err) {
    res.status(500).json({ error: (err as Error).message });
  }
});

app.post('/chat/close', async (req, res) => {
  try {
    const { chatId } = req.body;
    if (!chatId) { res.status(400).json({ error: 'chatId is required' }); return; }
    await tgClient.closeChat(chatId);
    res.json({ ok: true });
  } catch (err) {
    res.status(500).json({ error: (err as Error).message });
  }
});

app.get('/message', async (req, res) => {
  try {
    const { chatId, messageId } = req.query;
    if (!chatId || !messageId) {
      res.status(400).json({ error: 'chatId and messageId are required' });
      return;
    }
    const msg = await tgClient.getMessage(Number(chatId), Number(messageId));
    res.json(msg);
  } catch (err) {
    res.status(500).json({ error: (err as Error).message });
  }
});

app.get('/searchMessages', async (req, res) => {
  try {
    const { chatId, query, limit } = req.query;
    if (!chatId || !query) {
      res.status(400).json({ error: 'chatId and query are required' });
      return;
    }
    const result = await tgClient.searchMessages(Number(chatId), query as string, limit ? Number(limit) : 50);
    res.json(result);
  } catch (err) {
    res.status(500).json({ error: (err as Error).message });
  }
});

app.get('/messages', async (req, res) => {
  try {
    const { chatId, limit, before, after } = req.query;
    if (!chatId) {
      res.status(400).json({ error: 'chatId is required' });
      return;
    }
    const t0 = Date.now();
    let result;
    if (after) {
      result = await tgClient.getMessagesAfter(Number(chatId), Number(after), limit ? Number(limit) : 50);
    } else {
      result = await tgClient.getMessages(
        Number(chatId),
        limit ? Number(limit) : 50,
        before ? Number(before) : undefined
      );
    }
    const totalMs = Date.now() - t0;
    result._timing = { total_ms: totalMs, tdlib_ms: result._tdlib_ms, format_ms: result._format_ms };
    res.json(result);
  } catch (err) {
    res.status(500).json({ error: (err as Error).message });
  }
});

app.get('/messages/around', async (req, res) => {
  try {
    const { chatId, messageId, limit } = req.query;
    if (!chatId || !messageId) {
      res.status(400).json({ error: 'chatId and messageId are required' });
      return;
    }
    const result = await tgClient.getMessagesAround(Number(chatId), Number(messageId), limit ? Number(limit) : 11);
    res.json(result);
  } catch (err) {
    console.error('/messages/around error:', (err as Error).message);
    res.status(500).json({ error: (err as Error).message });
  }
});

app.post('/sendMessage', async (req, res) => {
  try {
    const { chatId, text, replyTo } = req.body;
    if (!chatId || !text) {
      res.status(400).json({ error: 'chatId and text are required' });
      return;
    }
    const msg = await tgClient.sendMessage(chatId, text, replyTo);
    res.json({ ok: true, message: msg });
  } catch (err) {
    res.status(500).json({ error: (err as Error).message });
  }
});

app.post('/editMessage', async (req, res) => {
  try {
    const { chatId, messageId, text } = req.body;
    if (!chatId || !messageId || !text) {
      res.status(400).json({ error: 'chatId, messageId and text are required' });
      return;
    }
    const result = await tgClient.editMessage(Number(chatId), Number(messageId), text);
    res.json(result);
  } catch (err) {
    res.status(500).json({ error: (err as Error).message });
  }
});

app.post('/deleteMessage', async (req, res) => {
  try {
    const { chatId, messageId, revoke } = req.body;
    if (!chatId || !messageId) {
      res.status(400).json({ error: 'chatId and messageId are required' });
      return;
    }
    const result = await tgClient.deleteMessage(chatId, messageId, revoke !== false);
    res.json(result);
  } catch (err) {
    res.status(500).json({ error: (err as Error).message });
  }
});

app.post('/forwardMessages', async (req, res) => {
  try {
    const { fromChatId, messageIds, toChatId } = req.body;
    if (!fromChatId || !messageIds || !toChatId) {
      res.status(400).json({ error: 'fromChatId, messageIds and toChatId are required' });
      return;
    }
    const result = await tgClient.forwardMessages(fromChatId, messageIds, toChatId);
    res.json(result);
  } catch (err) {
    res.status(500).json({ error: (err as Error).message });
  }
});

app.listen(PORT, () => {
  console.log('HTTP server: http://localhost:' + PORT);
  console.log('WebSocket server: ws://localhost:' + WS_PORT);
});

tgClient.start().catch(console.error);
