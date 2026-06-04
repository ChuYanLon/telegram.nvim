class FakeTdClient {
  handlers: Record<string, (...args: unknown[]) => void> = {};
  _users: Map<number, { id: number; first_name?: string; last_name?: string; username?: string; type: { _: string } }> = new Map();
  _chats: Map<number, { id: number; title: string; type: { _: string; supergroup_id?: number; is_channel?: boolean }; last_message: null; unread_count: number }> = new Map();
  _nextUserId = 100;
  _nextChatId = -1000;
  _pinnedMessages: Map<number, number> = new Map();

  setPinnedMessage(chatId: number, messageId: number) {
    this._pinnedMessages.set(chatId, messageId);
  }

  addUser(overrides: { id?: number; first_name?: string; last_name?: string; username?: string } = {}) {
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

  addChat(overrides: { id?: number; title?: string; type?: { _: string; supergroup_id?: number } } = {}) {
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

  on(event: string, handler: (...args: unknown[]) => void) {
    this.handlers[event] = handler;
  }

  async invoke(query: Record<string, unknown>) {
    switch (query._) {
      case 'getOption':
        return { value: '1.8.64' };
      case 'getUser': {
        const user = this._users.get(query.user_id as number);
        if (user) return user;
        return { first_name: 'Unknown', last_name: '', type: { _: 'userTypeRegular' } };
      }
      case 'getChat':
        return this._chats.get(query.chat_id as number) || { id: query.chat_id, title: 'Unknown Group' };
      case 'searchPublicChat':
        return { id: (query.username as string).charCodeAt(0) };
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
      case 'parseTextEntities':
        return { text: (query.text as string) || '', entities: [] };
      case 'getGroups':
        return { chat_ids: Array.from(this._chats.keys()) };
      case 'sendMessage':
        const inputText = (query.input_message_content as Record<string, unknown>).text as Record<string, unknown>;
        const msgText = typeof inputText === 'string' ? inputText : (inputText.text as string) || '';
        return {
          id: Date.now(),
          content: { _: 'messageText', text: { text: msgText } },
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
      case 'searchChatMessages': {
        const filter = query.filter as { _?: string } | undefined;
        if (filter?._ === 'searchMessagesFilterPinned') {
          const chatId = query.chat_id as number;
          const pinnedId = this._pinnedMessages.get(chatId);
          if (pinnedId) {
            return { messages: [{ id: pinnedId, content: { _: 'messageText', text: { text: 'pinned message' } } }] };
          }
        }
        return { messages: [] };
      }
      case 'getChatAdministrators': {
        const admins: { user_id: number; custom_title: string }[] = [];
        for (const [uid, user] of this._users) {
          admins.push({ user_id: uid, custom_title: '' });
        }
        return { administrators: admins };
      }
      case 'setChatMemberStatus':
        return { ok: true };
      default:
        return {};
    }
  }

  async login() {}
  async close() {}
}

export default FakeTdClient;
