class FakeTdClient {
  constructor() {
    this.handlers = {};
    this._users = new Map();
    this._chats = new Map();
    this._nextUserId = 100;
    this._nextChatId = -1000;
  }

  addUser(overrides = {}) {
    const id = overrides.id || this._nextUserId++;
    const user = {
      id,
      first_name: overrides.first_name || 'Test',
      last_name: overrides.last_name || '',
      username: overrides.username || `user_${id}`,
      type: { _: 'userTypeRegular' },
    };
    this._users.set(id, user);
    return user;
  }

  addChat(overrides = {}) {
    const id = overrides.id || this._nextChatId--;
    const chat = {
      id,
      title: overrides.title || `Chat ${Math.abs(id)}`,
      type: overrides.type || { _: 'chatTypeSupergroup', supergroup_id: Math.abs(id) },
      last_message: null,
      unread_count: 0,
    };
    this._chats.set(id, chat);
    return chat;
  }

  on(event, handler) {
    this.handlers[event] = handler;
  }

  async invoke(query) {
    switch (query._) {
      case 'getOption':
        return { value: '1.8.64' };
      case 'getUser': {
        const user = this._users.get(query.user_id);
        if (user) return user;
        return { first_name: 'Unknown', last_name: '', type: { _: 'userTypeRegular' } };
      }
      case 'getChat':
        return this._chats.get(query.chat_id) || { id: query.chat_id, title: 'Unknown Group' };
      case 'searchPublicChat':
        return { id: query.username.charCodeAt(0) };
      case 'getChatHistory':
        return { messages: [] };
      case 'getSupergroup':
        return { status: { _: 'chatMemberStatusMember' }, member_count: 42, is_channel: false };
      case 'getSupergroupFullInfo':
        return { description: 'A test group' };
      case 'getBasicGroup':
        return { status: { _: 'chatMemberStatusMember' }, member_count: 10, is_active: true };
      case 'getBasicGroupFullInfo':
        return { description: 'A basic test group' };
      case 'getGroups':
        return { chat_ids: Array.from(this._chats.keys()) };
      case 'sendMessage':
        return {
          id: Date.now(),
          content: { _: 'messageText', text: { text: query.input_message_content.text } },
          sender_id: { _: 'messageSenderUser', user_id: 1 },
          date: Math.floor(Date.now() / 1000),
          is_outgoing: true,
          reply_to: null,
        };
      case 'editMessageText':
        return { ok: true };
      case 'deleteMessages':
        return { ok: true };
      case 'forwardMessages':
        return { ok: true };
      case 'setChatMemberStatus':
        return { ok: true };
      default:
        return {};
    }
  }

  async login() {}
  async close() {}
}

module.exports = FakeTdClient;
