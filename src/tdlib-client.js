const tdl = require('tdl');
const path = require('path');
const fs = require('fs');
const { execSync } = require('child_process');
require('dotenv').config();

const TG_API_ID = Number(process.env.TG_API_ID) || 1025907;
const TG_API_HASH = process.env.TG_API_HASH || '452b0359b988148995f22ff0f4229750';
const TG_TDLIB_PATH = process.env.TG_TDLIB_PATH;
const TG_PROXY = process.env.TG_PROXY;
const dataDir = process.env.TG_DATA_DIR || process.cwd();

function detectTdlibPath() {
  if (TG_TDLIB_PATH) {
    if (fs.existsSync(TG_TDLIB_PATH)) return TG_TDLIB_PATH;
    console.warn(`TG_TDLIB_PATH set but not found: ${TG_TDLIB_PATH}`);
  }

  const isWin = process.platform === 'win32';
  const isMac = process.platform === 'darwin';
  const isLinux = process.platform === 'linux';

  if (isLinux) {
    try {
      const out = execSync('ldconfig -p 2>/dev/null | grep -i libtdjson', { encoding: 'utf8' });
      for (const line of out.trim().split('\n')) {
        const m = line.match(/=>\s*(\S+libtdjson\S+)/);
        if (m && fs.existsSync(m[1])) return m[1];
      }
    } catch {}
  }

  if (isMac) {
    try {
      const out = execSync('mdfind -name libtdjson 2>/dev/null', { encoding: 'utf8' });
      for (const f of out.trim().split('\n')) {
        if (f && (f.endsWith('.dylib') || f.endsWith('.so')) && fs.existsSync(f)) return f;
      }
    } catch {}
  }

  if (isWin) {
    try {
      const out = execSync('where tdjson.dll 2>nul', { encoding: 'utf8' });
      for (const f of out.trim().split('\n')) {
        if (f && fs.existsSync(f)) return f;
      }
    } catch {}
  }

  const home = process.env.HOME || process.env.USERPROFILE || '';
  const localAppData = process.env.LOCALAPPDATA || '';
  const programFiles = process.env.PROGRAMFILES || 'C:\\Program Files';

  const candidates = isLinux
    ? [
        `/usr/lib/${process.arch === 'x64' ? 'x86_64-linux-gnu' : process.arch === 'arm64' ? 'aarch64-linux-gnu' : ''}/libtdjson.so`,
        `/usr/local/lib/${process.arch === 'x64' ? 'x86_64-linux-gnu' : process.arch === 'arm64' ? 'aarch64-linux-gnu' : ''}/libtdjson.so`,
        `${home}/.local/lib/${process.arch === 'x64' ? 'x86_64-linux-gnu' : process.arch === 'arm64' ? 'aarch64-linux-gnu' : ''}/libtdjson.so`,
        '/usr/lib/libtdjson.so',
        '/usr/local/lib/libtdjson.so',
        `${home}/.local/lib/libtdjson.so`,
        '/usr/lib64/libtdjson.so',
        '/opt/lib/libtdjson.so',
      ]
    : isMac
    ? [
        '/opt/homebrew/lib/libtdjson.dylib',
        '/usr/local/lib/libtdjson.dylib',
        `${home}/.local/lib/libtdjson.dylib`,
        '/usr/lib/libtdjson.dylib',
      ]
    : [
        `${localAppData}\\tdlib\\bin\\tdjson.dll`,
        `${programFiles}\\tdlib\\bin\\tdjson.dll`,
        `${programFiles} (x86)\\tdlib\\bin\\tdjson.dll`,
        `${home}\\tdlib\\bin\\tdjson.dll`,
      ];

  for (const p of candidates) {
    if (fs.existsSync(p)) return p;
  }

  if (isLinux) {
    try {
      const ldpath = process.env.LD_LIBRARY_PATH || '';
      for (const dir of ldpath.split(':')) {
        const p = path.join(dir, 'libtdjson.so');
        if (fs.existsSync(p)) return p;
      }
    } catch {}
    try {
      const out = execSync('find /usr/lib /usr/local/lib /opt/lib /home -name "libtdjson.so*" -type f,l 2>/dev/null | head -3', { encoding: 'utf8' });
      for (const f of out.trim().split('\n')) {
        if (f && fs.existsSync(f)) return f;
      }
    } catch {}
  }

  return undefined;
}

let resolvedTdlibPath = detectTdlibPath();
if (resolvedTdlibPath) {
  console.log(`TDLib library: ${resolvedTdlibPath}`);
} else {
  const msg = 'Cannot find libtdjson. Install TDLib or set TG_TDLIB_PATH env var.';
  if (!TG_TDLIB_PATH) {
    console.error(msg);
    process.exit(1);
  }
  console.log('TDLib library: auto');
}

class TelegramLSPClient {
  constructor() {
    tdl.configure({
      tdjson: resolvedTdlibPath,
    });
    this.client = tdl.createClient({
      apiId: TG_API_ID,
      apiHash: TG_API_HASH,
      databaseDirectory: path.join(dataDir, 'tdlib_db'),
      filesDirectory: path.join(dataDir, 'tdlib_files'),
    });
    this._ready = false;
    this._chats = new Map();
    this._users = new Map();
    this._authState = 'initializing';
    this._authResolve = null;
    this._authHint = null;
    this._authError = null;
  }

  getAuthState() {
    return {
      state: this._authState,
      hint: this._authHint,
      error: this._authError,
      canInput: this._authResolve !== null,
    };
  }

  async submitAuthInput(value) {
    if (this._authResolve) {
      const resolve = this._authResolve;
      this._authResolve = null;
      resolve(value);
      return true;
    }
    return false;
  }

  async start() {
    try {
      const verOption = await this.client.invoke({ _: 'getOption', name: 'version' });
      if (verOption && verOption.value) {
        const parts = verOption.value.split('.').map(Number);
        if (parts[0] < 1 || (parts[0] === 1 && parts[1] < 8) || (parts[0] === 1 && parts[1] === 8 && parts[2] < 64)) {
          throw new Error(`TDLib version ${verOption.value} is too old. Minimum required: 1.8.64`);
        }
        console.log(`TDLib version: ${verOption.value}`);
      }

      if (TG_PROXY) {
        try {
          const url = new URL(TG_PROXY);
          const type = url.protocol === 'socks5:' || url.protocol === 'socks5h:'
            ? { _: 'proxyTypeSocks5', username: url.username || '', password: url.password || '' }
            : { _: 'proxyTypeHttp', username: url.username || '', password: url.password || '', http_only: false };
          await this.client.invoke({
            _: 'addProxy',
            proxy: { _: 'proxy', server: url.hostname, port: parseInt(url.port) || 1080, type },
            enable: true,
          });
          console.log(`Proxy enabled: ${url.protocol}//${url.host}`);
        } catch (e) {
          console.error('Failed to set proxy:', e.message);
        }
      }

      await this.client.login({
        type: 'user',
        getPhoneNumber: async (retry) => {
          this._authState = 'waitPhone';
          this._authError = retry ? 'Invalid phone number, please re-enter' : null;
          if (typeof global.broadcast === 'function') {
            global.broadcast({ event: 'authNeeded', type: 'phoneNumber', retry });
          }
          return new Promise((resolve) => {
            this._authResolve = resolve;
          });
        },
        getAuthCode: async (retry) => {
          this._authState = 'waitCode';
          this._authError = retry ? 'Invalid code, please re-enter' : null;
          if (typeof global.broadcast === 'function') {
            global.broadcast({ event: 'authNeeded', type: 'authCode', retry });
          }
          return new Promise((resolve) => {
            this._authResolve = resolve;
          });
        },
        getPassword: async (hint, retry) => {
          this._authState = 'waitPassword';
          this._authHint = hint || null;
          this._authError = retry ? 'Wrong password, please re-enter' : null;
          if (typeof global.broadcast === 'function') {
            global.broadcast({ event: 'authNeeded', type: 'password', hint, retry });
          }
          return new Promise((resolve) => {
            this._authResolve = resolve;
          });
        },
      });
      this._ready = true;
      this._authState = 'ready';
      this.listenUpdates();
      console.log('TDLib client ready');
    } catch (err) {
      this._authState = 'error';
      this._authError = err.message;
      console.error('Error:', err.message);
    }
  }

  async _getUserName(userId) {
    const cached = this._users.get(userId);
    if (cached) return cached;
    try {
      const user = await this.client.invoke({ _: 'getUser', user_id: userId });
      const name = [user.first_name, user.last_name].filter(Boolean).join(' ') || `user_${userId}`;
      this._users.set(userId, name);
      return name;
    } catch {
      return `user_${userId}`;
    }
  }

  async _resolveSender(senderId) {
    if (!senderId) return null;
    if (senderId._ === 'messageSenderUser') {
      const name = await this._getUserName(senderId.user_id);
      return { id: senderId.user_id, name };
    }
    if (senderId._ === 'messageSenderChat') {
      const chat = this._chats.get(senderId.chat_id);
      return { id: senderId.chat_id, name: chat ? chat.title : `chat_${senderId.chat_id}` };
    }
    return null;
  }

  _extractText(content) {
    if (!content) return '';
    if (content._ === 'messageText') return content.text.text;
    return content._;
  }

  async _formatReplyTo(msg) {
    if (!msg.reply_to || msg.reply_to._ !== 'messageReplyToMessage') return null;
    const r = msg.reply_to;
    const replyTo = { id: r.message_id };
    if (r.origin_sender_id) {
      replyTo.sender = await this._resolveSender(r.origin_sender_id);
    }
    if (!replyTo.sender && r.origin_sender_name) {
      replyTo.sender = { id: null, name: r.origin_sender_name };
    }
    if (r.chat_id === msg.chat_id) {
      try {
        const orig = await this.client.invoke({ _: 'getMessage', chat_id: msg.chat_id, message_id: r.message_id });
        if (orig) {
          replyTo.text = this._extractText(orig.content);
          if (!replyTo.sender) {
            replyTo.sender = await this._resolveSender(orig.sender_id);
          }
        }
      } catch {}
    }
    return replyTo;
  }

  async _formatMessage(msg) {
    if (!msg) return null;
    const formatted = {
      id: msg.id,
      text: this._extractText(msg.content),
      sender: await this._resolveSender(msg.sender_id),
      date: msg.date,
      own: msg.is_outgoing || false,
    };
    const replyTo = await this._formatReplyTo(msg);
    if (replyTo) formatted.replyTo = replyTo;
    return formatted;
  }

  async _enrichGroup(chat) {
    const group = {
      id: chat.id,
      title: chat.title,
    };

    if (chat.last_message) {
      group.lastMessage = await this._formatMessage(chat.last_message);
    }

    try {
      if (chat.type._ === 'chatTypeSupergroup') {
        const sg = await this.client.invoke({ _: 'getSupergroup', supergroup_id: chat.type.supergroup_id });
        group.memberCount = sg.member_count;
        if (sg.status._ === 'chatMemberStatusCreator') {
          group.owner = await this._resolveSender(sg.status.member_id);
        }
        const info = await this.client.invoke({ _: 'getSupergroupFullInfo', supergroup_id: chat.type.supergroup_id });
        group.description = info.description;
      } else if (chat.type._ === 'chatTypeBasicGroup') {
        const bg = await this.client.invoke({ _: 'getBasicGroup', basic_group_id: chat.type.basic_group_id });
        group.memberCount = bg.member_count;
        if (bg.status._ === 'chatMemberStatusCreator') {
          group.owner = await this._resolveSender(bg.status.member_id);
        }
        const info = await this.client.invoke({ _: 'getBasicGroupFullInfo', basic_group_id: chat.type.basic_group_id });
        group.description = info.description;
      }
    } catch (_) {
    }

    return group;
  }

  listenUpdates() {
    this.client.on('update', async (update) => {
      switch (update._) {
        case 'updateNewChat':
          this._chats.set(update.chat.id, update.chat);
          break;
        case 'updateNewMessage':
          await this.handleNewMessage(update.message);
          break;
        case 'updateUserChatAction':
        case 'updateChatAction':
          await this.handleUserChatAction(update);
          break;
        case 'updateChatOnlineMemberCount':
          this.handleChatOnlineMemberCount(update);
          break;
        default:
          console.log(update);
      }
    });
  }

  async handleNewMessage(msg) {
    if (typeof global.broadcast === 'function') {
      const chat = this._chats.get(msg.chat_id);
      const formatted = await this._formatMessage(msg);
      global.broadcast({
        event: 'newMessage',
        chat: { id: msg.chat_id, title: chat ? chat.title : 'Unknown group' },
        ...formatted,
      });
    }
  }

  async handleUserChatAction(update) {
    if (typeof global.broadcast === 'function') {
      const userName = update.user_id ? await this._getUserName(update.user_id) : 'unknown';
      global.broadcast({
        event: 'userAction',
        chat_id: update.chat_id,
        user_id: update.user_id,
        user_name: userName,
        action: update.action,
      });
    }
  }

  handleChatOnlineMemberCount(update) {
    if (typeof global.broadcast === 'function') {
      global.broadcast({
        event: 'chatOnlineMemberCount',
        chat_id: update.chat_id,
        online_member_count: update.online_member_count,
      });
    }
  }

  isReady() {
    return this._ready;
  }

  async getChats() {
    if (!this._ready) throw new Error('Client not ready yet');
    const allChats = [];
    let offsetOrder = '9223372036854775807';
    let offsetChatId = 0;
    const limit = 100;

    while (true) {
      const result = await this.client.invoke({
        _: 'getChats',
        offset_order: offsetOrder,
        offset_chat_id: offsetChatId,
        limit,
      });
      const chatIds = result.chat_ids;
      if (!chatIds || chatIds.length === 0) break;

      for (const id of chatIds) {
        const chat = await this.client.invoke({ _: 'getChat', chat_id: id });
        this._chats.set(id, chat);
        allChats.push(chat);
      }

      if (chatIds.length < limit) break;
      offsetOrder = String(BigInt(offsetOrder) - BigInt(1));
      offsetChatId = chatIds[chatIds.length - 1];
    }
    return [...this._chats.values()];
  }

  async getGroups() {
    const chats = await this.getChats();
    const groups = chats.filter((c) => {
      const t = c.type._;
      if (t === 'chatTypeBasicGroup') return true;
      if (t !== 'chatTypeSupergroup') return false;
      return !c.type.is_channel;
    });
    return Promise.all(groups.map(g => this._enrichGroup(g)));
  }

  async sendMessage(chatId, text, replyTo) {
    if (!this._ready) throw new Error('Client not ready yet');
    const params = {
      _: 'sendMessage',
      chat_id: chatId,
      input_message_content: {
        _: 'inputMessageText',
        text: { _: 'formattedText', text, entities: [] },
      },
    };
    if (replyTo) {
      params.reply_to = { _: 'inputMessageReplyToMessage', message_id: replyTo };
    }
    await this.client.invoke(params);
    return { ok: true };
  }

  async editMessage(chatId, messageId, text) {
    if (!this._ready) throw new Error('Client not ready yet');
    await this.client.invoke({
      _: 'editMessageText',
      chat_id: chatId,
      message_id: messageId,
      input_message_content: {
        _: 'inputMessageText',
        text: { _: 'formattedText', text, entities: [] },
      },
    });
    return { ok: true };
  }

  async deleteMessage(chatId, messageId) {
    if (!this._ready) throw new Error('Client not ready yet');
    await this.client.invoke({
      _: 'deleteMessages',
      chat_id: chatId,
      message_ids: [messageId],
      revoke: true,
    });
    return { ok: true };
  }

  async forwardMessages(fromChatId, messageIds, toChatId) {
    if (!this._ready) throw new Error('Client not ready yet');
    await this.client.invoke({
      _: 'forwardMessages',
      from_chat_id: fromChatId,
      message_ids: Array.isArray(messageIds) ? messageIds : [messageIds],
      chat_id: toChatId,
    });
    return { ok: true };
  }

  async openChat(chatId) {
    if (!this._ready) return;
    try {
      await this.client.invoke({ _: 'openChat', chat_id: chatId });
    } catch {}
  }

  async closeChat(chatId) {
    if (!this._ready) return;
    try {
      await this.client.invoke({ _: 'closeChat', chat_id: chatId });
    } catch {}
  }

  async sendChatAction(chatId, action) {
    if (!this._ready) return;
    try {
      await this.client.invoke({
        _: 'sendChatAction',
        chat_id: chatId,
        action: { _: action },
      });
    } catch {}
  }

  async searchMessages(chatId, query, limit = 50) {
    if (!this._ready) throw new Error('Client not ready yet');
    const result = await this.client.invoke({
      _: 'searchChatMessages',
      chat_id: chatId,
      query,
      limit,
    });
    const chat = this._chats.get(chatId);
    return {
      chat: { id: chatId, title: chat ? chat.title : 'Unknown group' },
      messages: await Promise.all((result.messages || []).map(m => this._formatMessage(m))),
    };
  }

  async getMessages(chatId, limit = 50, before) {
    if (!this._ready) throw new Error('Client not ready yet');
    const fromMessageId = before || 0;
    const offset = before ? -1 : 0;
    const result = await this.client.invoke({
      _: 'getChatHistory',
      chat_id: chatId,
      from_message_id: fromMessageId,
      offset,
      limit,
      only_local: false,
    });
    const chat = this._chats.get(chatId);
    return {
      chat: { id: chatId, title: chat ? chat.title : 'Unknown group' },
      messages: await Promise.all((result.messages || []).map(m => this._formatMessage(m))),
    };
  }

}

module.exports = TelegramLSPClient;
