import type { SenderInfo, RawTdMessage } from './types';

export class Resolver {
  _users: Map<number, string> = new Map();
  _chats: Map<number, { title: string }> = new Map();
  _invoke: (q: unknown) => Promise<unknown>;
  private static MAX_USERS = 5000;

  constructor(invoke: (q: unknown) => Promise<unknown>) {
    this._invoke = invoke;
  }

  private _cacheUser(id: number, name: string) {
    if (!this._users.has(id) && this._users.size >= Resolver.MAX_USERS) {
      const first = this._users.keys().next().value;
      if (first !== undefined) this._users.delete(first);
    }
    this._users.set(id, name);
  }

  setUser(id: number, name: string) {
    this._cacheUser(id, name);
  }

  setChatsMap(chats: Map<number, { title: string }>) {
    this._chats = chats;
  }

  async getUserName(userId: number): Promise<string> {
    const cached = this._users.get(userId);
    if (cached) return cached;
    try {
      const user = await this._invoke({ _: 'getUser', user_id: userId }) as { first_name?: string; last_name?: string };
      const name = [user.first_name, user.last_name].filter(Boolean).join(' ') || `user_${userId}`;
      this._cacheUser(userId, name);
      return name;
    } catch (e) {
      console.warn('getUserName failed for', userId, (e as Error).message);
      return `user_${userId}`;
    }
  }

  async resolveSender(senderId: { _: string; user_id?: number; chat_id?: number } | null): Promise<SenderInfo | null> {
    if (!senderId) return null;
    if (senderId._ === 'messageSenderUser') {
      if (senderId.user_id == null) return null;
      const name = await this.getUserName(senderId.user_id);
      return { id: senderId.user_id, name };
    }
    if (senderId._ === 'messageSenderChat') {
      if (senderId.chat_id == null) return null;
      const chat = this._chats.get(senderId.chat_id);
      return { id: senderId.chat_id, name: chat ? chat.title : `chat_${senderId.chat_id}` };
    }
    return null;
  }

  async preloadSenders(
    rawMessages: RawTdMessage[],
    senderKey: (id: { _: string; user_id?: number; chat_id?: number } | null) => string | null,
  ): Promise<Map<string, SenderInfo>> {
    const unique = new Map<string, { _: string; user_id?: number; chat_id?: number }>();
    for (const m of rawMessages) {
      const key = senderKey(m.sender_id);
      if (key && m.sender_id && !unique.has(key)) unique.set(key, m.sender_id);
    }
    const cache = new Map<string, SenderInfo>();
    await Promise.all([...unique].map(async ([key, id]) => {
      const sender = await this.resolveSender(id);
      if (sender) cache.set(key, sender);
    }));
    return cache;
  }
}
