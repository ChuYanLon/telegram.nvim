const express = require('express');
const { WebSocketServer } = require('ws');
const TelegramLSPClient = require('./tdlib-client.js');

const PORT = Number(process.env.TG_PORT) || 8080;
const WS_PORT = Number(process.env.TG_WS_PORT) || PORT + 1;

const app = express();
const wss = new WebSocketServer({ port: WS_PORT });

const tgClient = new TelegramLSPClient();

global.broadcast = (data) => {
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
      return res.status(400).json({ error: 'value is required' });
    }
    const ok = await tgClient.submitAuthInput(String(value));
    if (ok) {
      res.json({ ok: true });
    } else {
      res.status(400).json({ error: 'No pending auth input' });
    }
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.get('/groups', async (_req, res) => {
  try {
    const groups = await tgClient.getGroups();
    res.json(groups);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.get('/messages', async (req, res) => {
  try {
    const { chatId, limit, before } = req.query;
    if (!chatId) {
      return res.status(400).json({ error: 'chatId is required' });
    }
    const result = await tgClient.getMessages(
      Number(chatId),
      limit ? Number(limit) : 50,
      before ? Number(before) : undefined
    );
    res.json(result);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.post('/sendMessage', async (req, res) => {
  try {
    const { chatId, text, replyTo } = req.body;
    if (!chatId || !text) {
      return res.status(400).json({ error: 'chatId and text are required' });
    }
    const result = await tgClient.sendMessage(chatId, text, replyTo);
    res.json(result);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.post('/editMessage', async (req, res) => {
  try {
    const { chatId, messageId, text } = req.body;
    if (!chatId || !messageId || !text) {
      return res.status(400).json({ error: 'chatId, messageId and text are required' });
    }
    const result = await tgClient.editMessage(chatId, messageId, text);
    res.json(result);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.post('/deleteMessage', async (req, res) => {
  try {
    const { chatId, messageId } = req.body;
    if (!chatId || !messageId) {
      return res.status(400).json({ error: 'chatId and messageId are required' });
    }
    const result = await tgClient.deleteMessage(chatId, messageId);
    res.json(result);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.post('/forwardMessages', async (req, res) => {
  try {
    const { fromChatId, messageIds, toChatId } = req.body;
    if (!fromChatId || !messageIds || !toChatId) {
      return res.status(400).json({ error: 'fromChatId, messageIds and toChatId are required' });
    }
    const result = await tgClient.forwardMessages(fromChatId, messageIds, toChatId);
    res.json(result);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.listen(PORT, () => {
  console.log('HTTP server: http://localhost:' + PORT);
  console.log('WebSocket server: ws://localhost:' + WS_PORT);
});

tgClient.start().catch(console.error);
