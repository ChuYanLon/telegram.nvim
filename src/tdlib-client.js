const tdl = require('tdl');
const path = require('path');
require('dotenv').config();

const TG_API_ID = Number(process.env.TG_API_ID) || 1025907;
const TG_API_HASH = process.env.TG_API_HASH || '452b0359b988148995f22ff0f4229750';
const TG_TDLIB_PATH = process.env.TG_TDLIB_PATH;
const dataDir = process.env.TG_DATA_DIR || process.cwd();

class TelegramLSPClient {
  constructor() {
    tdl.configure({
      tdjson: TG_TDLIB_PATH,
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

  async _formatMessage(msg) {
    if (!msg) return null;
    return {
      id: msg.id,
      text: this._extractText(msg.content),
      sender: await this._resolveSender(msg.sender_id),
      date: msg.date,
    };
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
        default:
          console.log(update);
      }
    });
  }

  async handleNewMessage(msg) {
    if (typeof global.broadcast === 'function') {
      const chat = this._chats.get(msg.chat_id);
      global.broadcast({
        event: 'newMessage',
        chat: { id: msg.chat_id, title: chat ? chat.title : 'Unknown group' },
        sender: await this._resolveSender(msg.sender_id),
        text: this._extractText(msg.content),
        date: msg.date,
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
      return t === 'chatTypeBasicGroup' || t === 'chatTypeSupergroup';
    });
    return Promise.all(groups.map(g => this._enrichGroup(g)));
  }

  async sendMessage(chatId, text) {
    if (!this._ready) throw new Error('Client not ready yet');
    await this.client.invoke({
      _: 'sendMessage',
      chat_id: chatId,
      input_message_content: {
        _: 'inputMessageText',
        text: { _: 'formattedText', text, entities: [] },
      },
    });
    return { ok: true };
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
