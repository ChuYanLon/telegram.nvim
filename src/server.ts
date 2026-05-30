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

app.get('/chats', async (_req, res) => {
  try {
    const chats = await tgClient.getAllChats();
    res.json(chats);
  } catch (err) {
    res.status(500).json({ error: (err as Error).message });
  }
});

app.post('/chats/openByUserId', async (req, res) => {
  try {
    const { userId } = req.body;
    if (!userId) {
      res.status(400).json({ error: 'userId is required' });
      return;
    }
    const chat = await tgClient.getPrivateChatByUserId(Number(userId));
    res.json(chat);
  } catch (err) {
    res.status(500).json({ error: (err as Error).message });
  }
});

app.post('/chats/searchUser', async (req, res) => {
  try {
    const { username } = req.body;
    if (!username) {
      res.status(400).json({ error: 'username is required' });
      return;
    }
    const chat = await tgClient.searchUserByUsername(username);
    res.json(chat);
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
    await tgClient.openChat(Number(chatId));
    res.json({ ok: true });
  } catch (err) {
    res.status(500).json({ error: (err as Error).message });
  }
});

app.post('/chat/action', async (req, res) => {
  try {
    const { chatId, action } = req.body;
    if (!chatId || !action) { res.status(400).json({ error: 'chatId and action are required' }); return; }
    await tgClient.sendChatAction(Number(chatId), action);
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
    await tgClient.closeChat(Number(chatId));
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
    const { chatId, limit, before, beforeDate, after, afterDate } = req.query;
    if (!chatId) {
      res.status(400).json({ error: 'chatId is required' });
      return;
    }
    const t0 = Date.now();
    let result;
    if (after) {
      result = await tgClient.getMessagesAfter(Number(chatId), Number(after), Number(afterDate), limit ? Number(limit) : 50);
    } else {
      result = await tgClient.getMessages(
        Number(chatId),
        limit ? Number(limit) : 50,
        before ? Number(before) : undefined,
        beforeDate ? Number(beforeDate) : undefined,
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
    const msg = await tgClient.sendMessage(Number(chatId), text, replyTo ? Number(replyTo) : undefined);
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
    const result = await tgClient.deleteMessage(Number(chatId), Number(messageId), revoke !== false);
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
    const result = await tgClient.forwardMessages(
      Number(fromChatId),
      Array.isArray(messageIds) ? messageIds.map(Number) : Number(messageIds),
      Number(toChatId)
    );
    res.json(result);
  } catch (err) {
    res.status(500).json({ error: (err as Error).message });
  }
});

// ─── Member Management ────────────────────────────────────────────────

app.post('/chat/ban', async (req, res) => {
  try {
    const { chatId, userId } = req.body;
    if (!chatId || !userId) { res.status(400).json({ error: 'chatId and userId are required' }); return; }
    const result = await tgClient.banChatMember(Number(chatId), Number(userId));
    res.json(result);
  } catch (err) { res.status(500).json({ error: (err as Error).message }); }
});

app.post('/chat/unban', async (req, res) => {
  try {
    const { chatId, userId } = req.body;
    if (!chatId || !userId) { res.status(400).json({ error: 'chatId and userId are required' }); return; }
    const result = await tgClient.unbanChatMember(Number(chatId), Number(userId));
    res.json(result);
  } catch (err) { res.status(500).json({ error: (err as Error).message }); }
});

app.post('/chat/promote', async (req, res) => {
  try {
    const { chatId, userId } = req.body;
    if (!chatId || !userId) { res.status(400).json({ error: 'chatId and userId are required' }); return; }
    const result = await tgClient.promoteChatMember(Number(chatId), Number(userId));
    res.json(result);
  } catch (err) { res.status(500).json({ error: (err as Error).message }); }
});

app.post('/chat/demote', async (req, res) => {
  try {
    const { chatId, userId } = req.body;
    if (!chatId || !userId) { res.status(400).json({ error: 'chatId and userId are required' }); return; }
    const result = await tgClient.demoteChatMember(Number(chatId), Number(userId));
    res.json(result);
  } catch (err) { res.status(500).json({ error: (err as Error).message }); }
});

app.post('/chat/restrict', async (req, res) => {
  try {
    const { chatId, userId, untilDate } = req.body;
    if (!chatId || !userId) { res.status(400).json({ error: 'chatId and userId are required' }); return; }
    const result = await tgClient.restrictChatMember(Number(chatId), Number(userId), untilDate ? Number(untilDate) : 0);
    res.json(result);
  } catch (err) { res.status(500).json({ error: (err as Error).message }); }
});

app.post('/chat/unrestrict', async (req, res) => {
  try {
    const { chatId, userId } = req.body;
    if (!chatId || !userId) { res.status(400).json({ error: 'chatId and userId are required' }); return; }
    const result = await tgClient.unrestrictChatMember(Number(chatId), Number(userId));
    res.json(result);
  } catch (err) { res.status(500).json({ error: (err as Error).message }); }
});

app.post('/chat/add-member', async (req, res) => {
  try {
    const { chatId, userId } = req.body;
    if (!chatId || !userId) { res.status(400).json({ error: 'chatId and userId are required' }); return; }
    const result = await tgClient.addChatMember(Number(chatId), Number(userId));
    res.json(result);
  } catch (err) { res.status(500).json({ error: (err as Error).message }); }
});

app.get('/chat/my-permissions', async (req, res) => {
  try {
    const { chatId } = req.query;
    if (!chatId) { res.status(400).json({ error: 'chatId is required' }); return; }
    const result = await tgClient.getMyPermissions(Number(chatId));
    res.json(result);
  } catch (err) { res.status(500).json({ error: (err as Error).message }); }
});

app.get('/chat/members', async (req, res) => {
  try {
    const { chatId } = req.query;
    if (!chatId) { res.status(400).json({ error: 'chatId is required' }); return; }
    const result = await tgClient.searchChatMembers(Number(chatId));
    res.json({ members: result });
  } catch (err) { res.status(500).json({ error: (err as Error).message }); }
});

app.post('/chat/set-permissions', async (req, res) => {
  try {
    const { chatId, permissions } = req.body;
    if (!chatId || !permissions) { res.status(400).json({ error: 'chatId and permissions are required' }); return; }
    const result = await tgClient.setChatDefaultPermissions(Number(chatId), permissions);
    res.json(result);
  } catch (err) { res.status(500).json({ error: (err as Error).message }); }
});

// ─── Group Settings ────────────────────────────────────────────────────

app.post('/chat/set-title', async (req, res) => {
  try {
    const { chatId, title } = req.body;
    if (!chatId || !title) { res.status(400).json({ error: 'chatId and title are required' }); return; }
    const result = await tgClient.setChatTitle(Number(chatId), title);
    res.json(result);
  } catch (err) { res.status(500).json({ error: (err as Error).message }); }
});

app.post('/chat/set-description', async (req, res) => {
  try {
    const { chatId, description } = req.body;
    if (!chatId || description === undefined) { res.status(400).json({ error: 'chatId and description are required' }); return; }
    const result = await tgClient.setChatDescription(Number(chatId), description);
    res.json(result);
  } catch (err) { res.status(500).json({ error: (err as Error).message }); }
});

app.post('/chat/leave', async (req, res) => {
  try {
    const { chatId } = req.body;
    if (!chatId) { res.status(400).json({ error: 'chatId is required' }); return; }
    const result = await tgClient.leaveChat(Number(chatId));
    res.json(result);
  } catch (err) { res.status(500).json({ error: (err as Error).message }); }
});

app.post('/chat/delete-history', async (req, res) => {
  try {
    const { chatId } = req.body;
    if (!chatId) { res.status(400).json({ error: 'chatId is required' }); return; }
    const result = await tgClient.deleteChatHistory(Number(chatId));
    res.json(result);
  } catch (err) { res.status(500).json({ error: (err as Error).message }); }
});

// ─── Invite Links ──────────────────────────────────────────────────────

app.post('/chat/create-invite-link', async (req, res) => {
  try {
    const { chatId, expireDate, memberLimit } = req.body;
    if (!chatId) { res.status(400).json({ error: 'chatId is required' }); return; }
    const result = await tgClient.createChatInviteLink(Number(chatId), expireDate ? Number(expireDate) : undefined, memberLimit ? Number(memberLimit) : undefined);
    res.json(result);
  } catch (err) { res.status(500).json({ error: (err as Error).message }); }
});

app.get('/chat/invite-links', async (req, res) => {
  try {
    const { chatId } = req.query;
    if (!chatId) { res.status(400).json({ error: 'chatId is required' }); return; }
    const result = await tgClient.getChatInviteLinks(Number(chatId));
    res.json({ invite_links: result });
  } catch (err) { res.status(500).json({ error: (err as Error).message }); }
});

app.post('/chat/edit-invite-link', async (req, res) => {
  try {
    const { chatId, inviteLink, expireDate, memberLimit } = req.body;
    if (!chatId || !inviteLink) { res.status(400).json({ error: 'chatId and inviteLink are required' }); return; }
    const result = await tgClient.editChatInviteLink(Number(chatId), inviteLink, expireDate ? Number(expireDate) : undefined, memberLimit ? Number(memberLimit) : undefined);
    res.json(result);
  } catch (err) { res.status(500).json({ error: (err as Error).message }); }
});

app.post('/chat/revoke-invite-link', async (req, res) => {
  try {
    const { chatId, inviteLink } = req.body;
    if (!chatId || !inviteLink) { res.status(400).json({ error: 'chatId and inviteLink are required' }); return; }
    const result = await tgClient.revokeChatInviteLink(Number(chatId), inviteLink);
    res.json(result);
  } catch (err) { res.status(500).json({ error: (err as Error).message }); }
});

app.get('/messageMedia', async (req, res) => {
  try {
    const { chatId, messageId } = req.query;
    if (!chatId || !messageId) {
      res.status(400).json({ error: 'chatId and messageId required' });
      return;
    }
    const result = await tgClient.getMessageMedia(Number(chatId), Number(messageId));
    res.json(result);
  } catch (err) {
    res.status(500).json({ error: (err as Error).message });
  }
});

const server = app.listen(PORT, () => {
  console.log('HTTP server: http://localhost:' + PORT);
  console.log('WebSocket server: ws://localhost:' + WS_PORT);
});

async function shutdown() {
  console.log('Shutting down...');
  wss.close();
  server.close();
  try {
    await tgClient.client.close();
  } catch {}
  process.exit(0);
}

process.on('SIGINT', shutdown);
process.on('SIGTERM', () => process.exit(0));

tgClient.start().catch(console.error);
