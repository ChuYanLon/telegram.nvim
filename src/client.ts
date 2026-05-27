import * as tdl from 'tdl';
import * as dotenv from 'dotenv';
import path from 'path';
import type { RawTdChat, RawTdMessage, GroupInfo, FormattedMessage } from './types';
import { initTdlibModule, getResolvedTdlibPath } from './tdlib';
import { AuthManager } from './auth';
import { MessageFormatter } from './format';
import { Resolver } from './resolve';
import { UpdateDispatcher } from './updates';
import { extractText } from './format';

dotenv.config();
initTdlibModule();

const TG_API_ID = Number(process.env.TG_API_ID) || 1025907;
const TG_API_HASH = process.env.TG_API_HASH || '452b0359b988148995f22ff0f4229750';
const TG_PROXY = process.env.TG_PROXY;
const dataDir = process.env.TG_DATA_DIR || process.cwd();

export class TelegramLSPClient {
  client: any;
  _ready = false;
  _chats: Map<number, RawTdChat> = new Map();
  _chatsLoaded = false;

  auth: AuthManager;
  resolver: Resolver;
  formatter: MessageFormatter;
  updates: UpdateDispatcher;

  constructor(opts?: { client?: typeof TelegramLSPClient.prototype.client }) {
    if (opts?.client) {
      this.client = opts.client;
    } else {
      const lib = getResolvedTdlibPath();
      if (lib) tdl.configure({ tdjson: lib });
      this.client = tdl.createClient({
        apiId: TG_API_ID,
        apiHash: TG_API_HASH,
        databaseDirectory: path.join(dataDir, 'tdlib_db'),
        filesDirectory: path.join(dataDir, 'tdlib_files'),
      });
    }

    this.auth = new AuthManager();
    this.resolver = new Resolver((q) => this.client.invoke(q));
    this.resolver.setChatsMap(this._chats);
    this.formatter = new MessageFormatter(this.resolver, (q) => this.client.invoke(q));
    this.updates = new UpdateDispatcher(
      this.formatter,
      this.resolver,
      this._chats,
      () => global.broadcast,
    );
  }

  getAuthState() {
    return this.auth.getState();
  }

  async submitAuthInput(value: string) {
    return this.auth.submitInput(value);
  }

  async start() {
    try {
      const verOption = await this.client.invoke({ _: 'getOption', name: 'version' }) as { value?: string };
      if (verOption?.value) {
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
            ? { _: 'proxyTypeSocks5' as const, username: url.username || '', password: url.password || '' }
            : { _: 'proxyTypeHttp' as const, username: url.username || '', password: url.password || '', http_only: false };
          await this.client.invoke({
            _: 'addProxy',
            proxy: { _: 'proxy', server: url.hostname, port: parseInt(url.port) || 1080, type },
            enable: true,
          });
          console.log(`Proxy enabled: ${url.protocol}//${url.host}`);
        } catch (e: unknown) {
          console.error('Failed to set proxy:', (e as Error).message);
        }
      }

      this.auth.setBroadcast(global.broadcast);

      await this.client.login({
        type: 'user',
        getPhoneNumber: this.auth.getPhoneNumber.bind(this.auth),
        getAuthCode: this.auth.getAuthCode.bind(this.auth),
        getPassword: this.auth.getPassword.bind(this.auth),
      });

      this._ready = true;
      this.auth.markReady();
      this.updates.listen(this.client);
      console.log('TDLib client ready');
    } catch (err: unknown) {
      this.auth.markError((err as Error).message);
      console.error('Error:', (err as Error).message);
    }
  }

  isReady(): boolean {
    return this._ready;
  }

  async getChats(force?: boolean): Promise<RawTdChat[]> {
    if (!this._ready) throw new Error('Client not ready yet');
    if (this._chatsLoaded && !force) return [...this._chats.values()];

    let offsetOrder = '9223372036854775807';
    let offsetChatId = 0;
    const limit = 100;

    while (true) {
      const result = await this.client.invoke({
        _: 'getChats',
        chat_list: { _: 'chatListMain' },
        offset_order: offsetOrder,
        offset_chat_id: offsetChatId,
        limit,
      }) as { chat_ids: number[] };
      const chatIds = result.chat_ids;
      if (!chatIds || chatIds.length === 0) break;

      for (const id of chatIds) {
        const chat = await this.client.invoke({ _: 'getChat', chat_id: id }) as RawTdChat;
        const inMainList = (chat.positions || []).some(
          p => p.list && p.list._ === 'chatListMain'
        );
        if (!inMainList) continue;
        this._chats.set(id, chat);
      }

      if (chatIds.length < limit) break;
      const prevOrder = offsetOrder;
      const prevChatId = offsetChatId;
      offsetChatId = chatIds[chatIds.length - 1];
      const lastChat = this._chats.get(offsetChatId);
      if (lastChat) {
        const pos = (lastChat.positions || []).find(p => p.list && p.list._ === 'chatListMain');
        if (pos) offsetOrder = String(pos.order);
      }
      if (offsetOrder === prevOrder || offsetChatId === prevChatId) break;
    }
    this._chatsLoaded = true;
    return [...this._chats.values()];
  }

  async _enrichGroup(chat: RawTdChat): Promise<GroupInfo | null> {
    const group: GroupInfo = {
      id: chat.id,
      title: chat.title,
      unreadCount: chat.unread_count || 0,
      onlineMemberCount: chat.online_member_count || 0,
    };

    if (chat.last_message) {
      group.lastMessage = await this.formatter.format(chat.last_message);
    }

    try {
      if (chat.type._ === 'chatTypeSupergroup') {
        const sg: any = await this.client.invoke({ _: 'getSupergroup', supergroup_id: chat.type.supergroup_id });
        if (sg.status._ === 'chatMemberStatusLeft' || sg.status._ === 'chatMemberStatusBanned') return null;
        group.memberCount = sg.member_count;
        if (sg.status._ === 'chatMemberStatusCreator') {
          group.owner = await this.resolver.resolveSender(sg.status.member_id!);
        }
        const info: any = await this.client.invoke({ _: 'getSupergroupFullInfo', supergroup_id: chat.type.supergroup_id });
        group.description = info.description;
      } else if (chat.type._ === 'chatTypeBasicGroup') {
        const bg: any = await this.client.invoke({ _: 'getBasicGroup', basic_group_id: chat.type.basic_group_id });
        if (bg.status._ === 'chatMemberStatusLeft' || bg.status._ === 'chatMemberStatusBanned' || !bg.is_active) return null;
        group.memberCount = bg.member_count;
        if (bg.status._ === 'chatMemberStatusCreator') {
          group.owner = await this.resolver.resolveSender(bg.status.member_id!);
        }
        const info: any = await this.client.invoke({ _: 'getBasicGroupFullInfo', basic_group_id: chat.type.basic_group_id });
        group.description = info.description;
      }
    } catch { /* ignore */ }

    return group;
  }

  async getGroups(): Promise<GroupInfo[]> {
    const chats = await this.getChats();
    const groups = chats.filter((c) => {
      const t = c.type._;
      if (t === 'chatTypeBasicGroup') return true;
      if (t !== 'chatTypeSupergroup') return false;
      return !c.type.is_channel;
    });
    const enriched = await Promise.all(groups.map(g => this._enrichGroup(g)));
    return enriched.filter(Boolean) as GroupInfo[];
  }

  async sendMessage(chatId: number, text: string, replyTo?: number): Promise<FormattedMessage | null> {
    if (!this._ready) throw new Error('Client not ready yet');
    const params: Record<string, unknown> = {
      _: 'sendMessage',
      chat_id: chatId,
      input_message_content: {
        _: 'inputMessageText',
        text: { _: 'formattedText', text, entities: [] },
      },
    };
    if (replyTo) params.reply_to = { _: 'inputMessageReplyToMessage', message_id: replyTo };
    const result = await this.client.invoke(params) as RawTdMessage;
    return this.formatter.format(result);
  }

  async editMessage(chatId: number, messageId: number, text: string): Promise<{ ok: boolean }> {
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

  async deleteMessage(chatId: number, messageId: number, revoke = true): Promise<{ ok: boolean }> {
    if (!this._ready) throw new Error('Client not ready yet');
    await this.client.invoke({
      _: 'deleteMessages',
      chat_id: chatId,
      message_ids: [messageId],
      revoke,
    });
    return { ok: true };
  }

  async forwardMessages(fromChatId: number, messageIds: number | number[], toChatId: number): Promise<{ ok: boolean }> {
    if (!this._ready) throw new Error('Client not ready yet');
    await this.client.invoke({
      _: 'forwardMessages',
      from_chat_id: fromChatId,
      message_ids: Array.isArray(messageIds) ? messageIds : [messageIds],
      chat_id: toChatId,
    });
    return { ok: true };
  }

  async getChat(chatId: number) {
    if (!this._ready) throw new Error('Client not ready yet');
    const chat = await this.client.invoke({ _: 'getChat', chat_id: chatId }) as RawTdChat;
    let memberCount = 0;
    try {
      if (chat.type._ === 'chatTypeSupergroup') {
        const sg = await this.client.invoke({ _: 'getSupergroup', supergroup_id: chat.type.supergroup_id }) as { member_count: number };
        memberCount = sg.member_count;
      } else if (chat.type._ === 'chatTypeBasicGroup') {
        const bg = await this.client.invoke({ _: 'getBasicGroup', basic_group_id: chat.type.basic_group_id }) as { member_count: number };
        memberCount = bg.member_count;
      }
    } catch { /* ignore */ }
    return {
      id: chat.id,
      title: chat.title,
      unreadCount: chat.unread_count || 0,
      onlineMemberCount: chat.online_member_count || 0,
      memberCount,
    };
  }

  async viewMessages(chatId: number, messageId?: number) {
    if (!this._ready) return;
    try {
      await this.client.invoke({
        _: 'viewMessages',
        chat_id: chatId,
        message_ids: messageId ? [messageId] : [],
        force_read: true,
      });
    } catch { /* ignore */ }
  }

  async openChat(chatId: number) {
    if (!this._ready) return;
    try {
      await this.client.invoke({ _: 'openChat', chat_id: chatId });
    } catch { /* ignore */ }
  }

  async closeChat(chatId: number) {
    if (!this._ready) return;
    try {
      await this.client.invoke({ _: 'closeChat', chat_id: chatId });
    } catch { /* ignore */ }
  }

  async sendChatAction(chatId: number, action: string) {
    if (!this._ready) return;
    try {
      await this.client.invoke({
        _: 'sendChatAction',
        chat_id: chatId,
        action: { _: action },
      });
    } catch { /* ignore */ }
  }

  async searchMessages(chatId: number, query: string, limit = 50) {
    if (!this._ready) throw new Error('Client not ready yet');
    const result = await this.client.invoke({
      _: 'searchChatMessages',
      chat_id: chatId,
      query,
      limit,
    }) as { messages?: RawTdMessage[] };
    const chat = this._chats.get(chatId);
    return {
      chat: { id: chatId, title: chat ? chat.title : 'Unknown group' },
      messages: await Promise.all((result.messages || []).map(m => this.formatter.format(m))),
    };
  }

  async getMessage(chatId: number, messageId: number): Promise<FormattedMessage | null> {
    if (!this._ready) throw new Error('Client not ready yet');
    const msg = await this.client.invoke({
      _: 'getMessage',
      chat_id: chatId,
      message_id: messageId,
    }) as RawTdMessage;
    return this.formatter.format(msg);
  }

  async getMessages(chatId: number, limit = 50, before?: number) {
    if (!this._ready) throw new Error('Client not ready yet');
    const fromMessageId = before || 0;
    const offset = before ? -1 : 0;
    const t0 = Date.now();
    const result = await this.client.invoke({
      _: 'getChatHistory',
      chat_id: chatId,
      from_message_id: fromMessageId,
      offset,
      limit,
      only_local: false,
    }) as { messages?: RawTdMessage[] };
    const tdlibMs = Date.now() - t0;
    const chat = this._chats.get(chatId);
    const t1 = Date.now();
    const raw = result.messages || [];
    const senderCache = raw.length > 1 ? await this.formatter.preloadSenders(raw) : null;
    const msgs = await Promise.all(raw.map(m => this.formatter.format(m, senderCache)));
    const fmtMs = Date.now() - t1;
    return {
      chat: { id: chatId, title: chat ? chat.title : 'Unknown group' },
      messages: msgs,
      _tdlib_ms: tdlibMs,
      _format_ms: fmtMs,
    };
  }

  async getMessagesAfter(chatId: number, afterId: number, limit = 50) {
    if (!this._ready) throw new Error('Client not ready yet');
    const result = await this.client.invoke({
      _: 'getChatHistory',
      chat_id: chatId,
      from_message_id: afterId,
      offset: -limit,
      limit,
      only_local: false,
    }) as { messages?: RawTdMessage[] };
    const raw = result.messages || [];
    const senderCache = raw.length > 1 ? await this.formatter.preloadSenders(raw) : null;
    const msgs = (await Promise.all(
      raw.map(m => this.formatter.format(m, senderCache))
    )).filter(Boolean) as FormattedMessage[];
    const newer: FormattedMessage[] = [];
    for (const m of msgs) {
      if (m.id > afterId) newer.push(m);
      else break;
    }
    const chat = this._chats.get(chatId);
    return { chat: { id: chatId, title: chat ? chat.title : 'Unknown group' }, messages: newer.reverse() };
  }

  // Test accessors that delegate to sub-modules
  _extractText(content: any) { return extractText(content); }
  _formatMessage(msg: any, cache?: any) { return this.formatter.format(msg, cache); }
  _formatReplyTo(msg: any) { return (this.formatter as any)._formatReplyTo(msg); }
  _resolveSender(id: any) { return this.resolver.resolveSender(id); }
  handleUserChatAction(u: any) { return this.updates.handleUserChatAction(u); }
  handleChatAction(u: any) { return this.updates.handleChatAction(u); }
  handleNewMessage(m: any) { return this.updates.handleNewMessage(m); }
  handleChatMemberUpdate(u: any) { return this.updates.handleChatMemberUpdate(u); }
  handleChatOnlineMemberCount(u: any) { return this.updates.handleChatOnlineMemberCount(u); }

  async getMessagesAround(chatId: number, messageId: number, limit = 31) {
    if (!this._ready) throw new Error('Client not ready yet');
    const half = Math.floor(limit / 2);
    let target: FormattedMessage | null = null;
    try {
      target = await this.getMessage(chatId, messageId);
    } catch { /* ignore */ }

    const [olderResult, newerResult] = await Promise.all([
      this.client.invoke({
        _: 'getChatHistory', chat_id: chatId, from_message_id: messageId, offset: 0, limit: half + 1, only_local: false,
      }).catch(() => ({ messages: [] })),
      this.client.invoke({
        _: 'getChatHistory', chat_id: chatId, from_message_id: messageId, offset: -half, limit: half, only_local: false,
      }).catch(() => ({ messages: [] })),
    ]) as [{ messages?: RawTdMessage[] }, { messages?: RawTdMessage[] }];

    const allRaw = [...(olderResult.messages || []), ...(newerResult.messages || [])];
    const senderCache = allRaw.length > 1 ? await this.formatter.preloadSenders(allRaw) : null;

    const older = (await Promise.all(
      (olderResult.messages || []).map(m => this.formatter.format(m, senderCache))
    )).filter(Boolean).filter(m => !target || (m as FormattedMessage).id !== messageId).reverse() as FormattedMessage[];

    const newer = (await Promise.all(
      (newerResult.messages || []).map(m => this.formatter.format(m, senderCache))
    )).filter(Boolean).filter(m => !target || (m as FormattedMessage).id > messageId).reverse().slice(0, half) as FormattedMessage[];

    const allMsgs = [...older, ...(target ? [target] : []), ...newer];
    const chat = this._chats.get(chatId);
    return { chat: { id: chatId, title: chat ? chat.title : 'Unknown group' }, messages: allMsgs, targetIndex: older.length };
  }

  async getMessageMedia(chatId: number, messageId: number): Promise<{ path: string } | null> {
    try {
      const msg = await this.client.invoke({ _: 'getMessage', chat_id: chatId, message_id: messageId }) as RawTdMessage;
      if (!msg || !msg.content) return null;
      await this.client.invoke({ _: 'openMessageContent', chat_id: chatId, message_id: messageId }).catch(() => {});

      const content = msg.content as Record<string, unknown>;
      const files: number[] = [];

      // Collect all file IDs from media content
      const collectFiles = (obj: Record<string, unknown>, ...keys: string[]) => {
        for (const key of keys) {
          const val = obj[key];
          if (!val) continue;
          const arr = Array.isArray(val) ? val : [val];
          for (const item of arr) {
            const f = (item as Record<string, unknown> | undefined)?.['photo'] || (item as Record<string, unknown> | undefined)?.['sticker'] || (item as Record<string, unknown> | undefined)?.['video'] || (item as Record<string, unknown> | undefined)?.['document'] || (item as Record<string, unknown> | undefined)?.['animation'] || (item as Record<string, unknown> | undefined)?.['voice'] || (item as Record<string, unknown> | undefined)?.['audio'] || item;
            const fileId = (f as Record<string, unknown> | undefined)?.['id'] as number | undefined;
            if (fileId && fileId > 0) files.push(fileId);
          }
        }
      };

      const t = content._ as string;
      if (t === 'messagePhoto') {
        const photo = content['photo'] as Record<string, unknown> | undefined;
        const sizes = photo?.['sizes'] as Record<string, unknown>[] | undefined;
        if (sizes) for (const s of sizes) collectFiles(s, 'photo', 'sizes');
      } else if (t === 'messageSticker') {
        collectFiles(content['sticker'] as Record<string, unknown>, 'sticker', 'thumbnail');
      } else {
        const cfg = { messageVideo: 'video', messageDocument: 'document', messageAnimation: 'animation', messageVoiceNote: 'voice_note', messageVideoNote: 'video_note', messageAudio: 'audio' } as Record<string, string>;
        const key = cfg[t];
        if (key) {
          const media = content[key] as Record<string, unknown> | undefined;
          if (media) {
            collectFiles(media, key.replace('_note', '').replace('_', ''), 'thumbnail');
          }
        }
      }

      const uniqueIds = [...new Set(files)];
      await Promise.all(uniqueIds.map(id => this.client.invoke({ _: 'downloadFile', file_id: id, priority: 1 }).catch(() => {})));

      for (let attempt = 0; attempt < 15; attempt++) {
        await new Promise(r => setTimeout(r, 1000));
        const fresh = await this.client.invoke({ _: 'getMessage', chat_id: chatId, message_id: messageId }) as RawTdMessage;
        if (fresh?.content) {
          const freshContent = fresh.content as Record<string, unknown>;
          const formatted = await this.formatter.format(fresh);
          if (formatted?.filePath) return { path: formatted.filePath };
        }
      }

      const formatted = await this.formatter.format(msg);
      if (formatted?.filePath) return { path: formatted.filePath };
      return { path: '' };
    } catch { return null; }
  }
}

export default TelegramLSPClient;
