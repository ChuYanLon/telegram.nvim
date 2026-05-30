import * as tdl from 'tdl';
import * as dotenv from 'dotenv';
import path from 'path';


import type { RawTdChat, RawTdMessage, GroupInfo, ChatInfo, FormattedMessage } from './types';
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
      (q) => this.client.invoke(q),
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
        const match = verOption.value.match(/\d+\.\d+\.\d+/);
        if (!match) {
          throw new Error(`Cannot parse TDLib version: ${verOption.value}`);
        }
        const parts = match[0].split('.').map(Number);
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

      const LOGIN_TIMEOUT = 5 * 60 * 1000;
      await Promise.race([
        this.client.login({
          type: 'user',
          getPhoneNumber: this.auth.getPhoneNumber.bind(this.auth),
          getAuthCode: this.auth.getAuthCode.bind(this.auth),
          getPassword: this.auth.getPassword.bind(this.auth),
        }),
        new Promise<void>((_, reject) =>
          setTimeout(() => reject(new Error('Login timed out after 5 minutes')), LOGIN_TIMEOUT)
        ),
      ]);

      this.updates.listen(this.client);
      this._ready = true;
      this.auth.markReady();
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
    if (!force && this._chatsLoaded) return [...this._chats.values()];
    this._chats.clear();
    this._chatsLoaded = false;

    let offsetOrder = '9223372036854775807';
    let offsetChatId = 0;
    const limit = 100;

    const MAX_ITERATIONS = 1000;
    let iterations = 0;
    while (true) {
      if (++iterations > MAX_ITERATIONS) {
        console.warn('getChats: exceeded max iterations (' + MAX_ITERATIONS + '), stopping');
        break;
      }
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
        if (sg.status._ === 'chatMemberStatusCreator' && sg.status.member_id) {
          group.owner = await this.resolver.resolveSender(sg.status.member_id);
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
    } catch (e) { console.warn('_enrichChatGroup failed:', (e as Error).message); }

    return group;
  }

  async _enrichPrivate(chat: RawTdChat): Promise<ChatInfo | null> {
    const info: ChatInfo = {
      id: chat.id,
      title: chat.title,
      type: 'private',
      unreadCount: chat.unread_count || 0,
      onlineMemberCount: chat.online_member_count || 0,
    };
    if (chat.last_message) {
      info.lastMessage = await this.formatter.format(chat.last_message);
    }
    if (chat.type.user_id) {
      info.userId = chat.type.user_id;
    }
    return info;
  }

  async getAllChats(): Promise<ChatInfo[]> {
    const chats = await this.getChats(true);
    const results = chats.map(async (chat) => {
      const t = chat.type._;
      if (t === 'chatTypeBasicGroup') {
        const g = await this._enrichGroup(chat);
        return g ? { ...g, type: 'group' as const } : null;
      }
      if (t === 'chatTypeSupergroup') {
        const g = await this._enrichGroup(chat);
        if (!g) return null;
        return chat.type.is_channel
          ? { ...g, type: 'channel' as const }
          : { ...g, type: 'group' as const };
      }
      if (t === 'chatTypePrivate' || t === 'chatTypeSecret') {
        return this._enrichPrivate(chat);
      }
      return null;
    });
    const enriched = await Promise.all(results);
    return enriched.filter(Boolean) as ChatInfo[];
  }

  async searchUserByUsername(username: string): Promise<ChatInfo> {
    if (!this._ready) throw new Error('Client not ready yet');
    const clean = username.replace(/^@/, '');
    const chat = await this.client.invoke({
      _: 'searchPublicChat',
      username: clean,
    }) as RawTdChat;
    if (!chat || !chat.id) throw new Error('User not found');
    this._chats.set(chat.id, chat);
    if (chat.type._ === 'chatTypePrivate' || chat.type._ === 'chatTypeSecret') {
      const enriched = await this._enrichPrivate(chat);
      if (enriched) return enriched;
    }
    return {
      id: chat.id,
      title: chat.title,
      type: chat.type._ === 'chatTypePrivate' || chat.type._ === 'chatTypeSecret' ? 'private' : 'group',
      unreadCount: chat.unread_count || 0,
      onlineMemberCount: chat.online_member_count || 0,
    };
  }

  async getPrivateChatByUserId(userId: number): Promise<ChatInfo> {
    if (!this._ready) throw new Error('Client not ready yet');
    const chat = await this.client.invoke({
      _: 'createPrivateChat',
      user_id: userId,
      force: true,
    }) as RawTdChat;
    this._chats.set(chat.id, chat);
    const enriched = await this._enrichPrivate(chat);
    if (enriched) return enriched;
    return {
      id: chat.id,
      title: chat.title,
      type: 'private',
      unreadCount: chat.unread_count || 0,
      onlineMemberCount: chat.online_member_count || 0,
    };
  }

  async getGroups(): Promise<GroupInfo[]> {
    const chats = await this.getChats(true);
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

  async getRawChat(chatId: number) {
    if (!this._ready) throw new Error('Client not ready yet');
    return await this.client.invoke({ _: 'getChat', chat_id: chatId }) as RawTdChat;
  }

  async getChat(chatId: number) {
    if (!this._ready) throw new Error('Client not ready yet');
    const chat = await this.getRawChat(chatId);
    let memberCount = 0;
    let description = '';
    const chatObj = chat as any;
    const chatPerms = chatObj.permissions as Record<string, unknown> | undefined;
    const defaultRestricted = chatPerms?.can_send_basic_messages === false;
    try {
      if (chat.type._ === 'chatTypeSupergroup') {
        const sg = await this.client.invoke({ _: 'getSupergroup', supergroup_id: chat.type.supergroup_id }) as { member_count: number };
        memberCount = sg.member_count;
        const info = await this.client.invoke({ _: 'getSupergroupFullInfo', supergroup_id: chat.type.supergroup_id }) as any;
        description = info.description || '';
      } else if (chat.type._ === 'chatTypeBasicGroup') {
        const bg = await this.client.invoke({ _: 'getBasicGroup', basic_group_id: chat.type.basic_group_id }) as { member_count: number };
        memberCount = bg.member_count;
        const info = await this.client.invoke({ _: 'getBasicGroupFullInfo', basic_group_id: chat.type.basic_group_id }) as any;
        description = info.description || '';
      }
    } catch (e) { console.warn('getChatInfo member count failed:', (e as Error).message); }
    return {
      id: chat.id,
      title: chat.title,
      unreadCount: chat.unread_count || 0,
      onlineMemberCount: chat.online_member_count || 0,
      memberCount,
      description,
      defaultRestricted,
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
    } catch (e) { console.warn('viewMessages failed:', (e as Error).message); }
  }

  async openChat(chatId: number) {
    if (!this._ready) return;
    try {
      await this.client.invoke({ _: 'openChat', chat_id: chatId });
    } catch (e) { console.warn('openChat failed:', (e as Error).message); }
  }

  async closeChat(chatId: number) {
    if (!this._ready) return;
    try {
      await this.client.invoke({ _: 'closeChat', chat_id: chatId });
    } catch (e) { console.warn('closeChat failed:', (e as Error).message); }
  }

  async sendChatAction(chatId: number, action: string) {
    if (!this._ready) return;
    try {
      await this.client.invoke({
        _: 'sendChatAction',
        chat_id: chatId,
        action: { _: action },
      });
    } catch (e) { console.warn('sendChatAction failed:', (e as Error).message); }
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

  async getMessages(chatId: number, limit = 50, before?: number, beforeDate?: number) {
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
    let msgs = (await Promise.all(raw.map(m => this.formatter.format(m, senderCache)))).filter(Boolean) as FormattedMessage[];
    if (before && beforeDate) {
      msgs = msgs.filter(m => m.date < beforeDate || (m.date === beforeDate && m.id < before));
    }
    msgs.sort((a, b) => b.date - a.date);
    const fmtMs = Date.now() - t1;
    return {
      chat: { id: chatId, title: chat ? chat.title : 'Unknown group' },
      messages: msgs,
      _tdlib_ms: tdlibMs,
      _format_ms: fmtMs,
    };
  }

  async getMessagesAfter(chatId: number, afterId: number, afterDate: number, limit = 50) {
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
    let msgs = (await Promise.all(
      raw.map(m => this.formatter.format(m, senderCache))
    )).filter(Boolean) as FormattedMessage[];
    msgs = msgs.filter(m => m.date > afterDate || (m.date === afterDate && m.id > afterId));
    msgs.sort((a, b) => a.date - b.date);
    const chat = this._chats.get(chatId);
    return { chat: { id: chatId, title: chat ? chat.title : 'Unknown group' }, messages: msgs };
  }

  // ─── Member Management ───────────────────────────────────────────────

  async banChatMember(chatId: number, userId: number): Promise<{ ok: boolean }> {
    if (!this._ready) throw new Error('Client not ready yet');
    await this.client.invoke({
      _: 'setChatMemberStatus',
      chat_id: chatId,
      member_id: { _: 'messageSenderUser', user_id: userId },
      status: { _: 'chatMemberStatusBanned' },
    });
    return { ok: true };
  }

  async unbanChatMember(chatId: number, userId: number): Promise<{ ok: boolean }> {
    if (!this._ready) throw new Error('Client not ready yet');
    await this.client.invoke({
      _: 'setChatMemberStatus',
      chat_id: chatId,
      member_id: { _: 'messageSenderUser', user_id: userId },
      status: { _: 'chatMemberStatusMember' },
    });
    return { ok: true };
  }

  async promoteChatMember(chatId: number, userId: number): Promise<{ ok: boolean }> {
    if (!this._ready) throw new Error('Client not ready yet');
    await this.client.invoke({
      _: 'setChatMemberStatus',
      chat_id: chatId,
      member_id: { _: 'messageSenderUser', user_id: userId },
      status: {
        _: 'chatMemberStatusAdministrator',
        custom_title: '',
        is_anonymous: false,
        can_manage_chat: true,
        can_change_info: true,
        can_post_messages: true,
        can_edit_messages: true,
        can_delete_messages: true,
        can_invite_users: true,
        can_restrict_members: true,
        can_pin_messages: true,
        can_manage_topics: true,
        can_promote_members: true,
        can_manage_video_chats: true,
        can_post_stories: true,
        can_edit_stories: true,
        can_delete_stories: true,
      },
    });
    return { ok: true };
  }

  async demoteChatMember(chatId: number, userId: number): Promise<{ ok: boolean }> {
    if (!this._ready) throw new Error('Client not ready yet');
    await this.client.invoke({
      _: 'setChatMemberStatus',
      chat_id: chatId,
      member_id: { _: 'messageSenderUser', user_id: userId },
      status: { _: 'chatMemberStatusMember' },
    });
    return { ok: true };
  }

  async restrictChatMember(chatId: number, userId: number, untilDate = 0): Promise<{ ok: boolean }> {
    if (!this._ready) throw new Error('Client not ready yet');
    await this.client.invoke({
      _: 'setChatMemberStatus',
      chat_id: chatId,
      member_id: { _: 'messageSenderUser', user_id: userId },
      status: {
        _: 'chatMemberStatusRestricted',
        is_member: true,
        permissions: {
          _: 'chatPermissions',
          can_send_messages: false,
          can_send_audios: false,
          can_send_documents: false,
          can_send_photos: false,
          can_send_videos: false,
          can_send_video_notes: false,
          can_send_voice_notes: false,
          can_send_polls: false,
          can_send_other_messages: false,
          can_add_web_page_previews: false,
          can_change_info: false,
          can_invite_users: false,
          can_pin_messages: false,
          can_manage_topics: false,
        },
        until_date: untilDate,
      },
    });
    return { ok: true };
  }

  async unrestrictChatMember(chatId: number, userId: number): Promise<{ ok: boolean }> {
    if (!this._ready) throw new Error('Client not ready yet');
    await this.client.invoke({
      _: 'setChatMemberStatus',
      chat_id: chatId,
      member_id: { _: 'messageSenderUser', user_id: userId },
      status: {
        _: 'chatMemberStatusRestricted',
        is_member: true,
        permissions: {
          _: 'chatPermissions',
          can_send_messages: true,
          can_send_audios: true,
          can_send_documents: true,
          can_send_photos: true,
          can_send_videos: true,
          can_send_video_notes: true,
          can_send_voice_notes: true,
          can_send_polls: true,
          can_send_other_messages: true,
          can_add_web_page_previews: true,
          can_change_info: true,
          can_invite_users: true,
          can_pin_messages: true,
          can_manage_topics: true,
        },
        until_date: 0,
      },
    });
    return { ok: true };
  }

  async addChatMember(chatId: number, userId: number): Promise<{ ok: boolean }> {
    if (!this._ready) throw new Error('Client not ready yet');
    const chat = await this.getRawChat(chatId);
    if (chat.type._ === 'chatTypeBasicGroup') {
      await this.client.invoke({ _: 'addChatMember', chat_id: chatId, user_id: userId });
    } else {
      // For supergroups, share an invite link instead
      const link = await this.createChatInviteLink(chatId);
      throw new Error(`Cannot add member directly to a supergroup. Share this invite link: ${link.invite_link || 'failed to generate'}`);
    }
    return { ok: true };
  }

  async searchChatMembers(chatId: number, query = '', limit = 200): Promise<any[]> {
    if (!this._ready) throw new Error('Client not ready yet');
    const result = await this.client.invoke({
      _: 'searchChatMembers',
      chat_id: chatId,
      query,
      limit,
      filter: { _: 'chatMembersFilterMembers' },
    }) as { members?: any[] };
    return this._resolveChatMembers(result.members || []);
  }

  async setChatDefaultPermissions(chatId: number, permissions: Record<string, boolean>): Promise<{ ok: boolean }> {
    if (!this._ready) throw new Error('Client not ready yet');
    const allow = permissions.can_send_messages;
    const perms: Record<string, unknown> = { _: 'chatPermissions' };
    if (allow) {
      perms.can_send_basic_messages = true;
      perms.can_send_audios = true;
      perms.can_send_documents = true;
      perms.can_send_photos = true;
      perms.can_send_videos = true;
      perms.can_send_video_notes = true;
      perms.can_send_voice_notes = true;
      perms.can_send_polls = true;
      perms.can_send_other_messages = true;
      perms.can_add_link_previews = true;
    } else {
      perms.can_send_basic_messages = false;
      perms.can_send_audios = false;
      perms.can_send_documents = false;
      perms.can_send_photos = false;
      perms.can_send_videos = false;
      perms.can_send_video_notes = false;
      perms.can_send_voice_notes = false;
      perms.can_send_polls = false;
      perms.can_send_other_messages = false;
      perms.can_add_link_previews = false;
    }
    await this.client.invoke({ _: 'setChatPermissions', chat_id: chatId, permissions: perms });
    return { ok: true };
  }

  // ─── Group Settings ─────────────────────────────────────────────────

  async setChatTitle(chatId: number, title: string): Promise<{ ok: boolean }> {
    if (!this._ready) throw new Error('Client not ready yet');
    await this.client.invoke({ _: 'setChatTitle', chat_id: chatId, title });
    return { ok: true };
  }

  async setChatDescription(chatId: number, description: string): Promise<{ ok: boolean }> {
    if (!this._ready) throw new Error('Client not ready yet');
    await this.client.invoke({ _: 'setChatDescription', chat_id: chatId, description });
    return { ok: true };
  }

  async leaveChat(chatId: number): Promise<{ ok: boolean }> {
    if (!this._ready) throw new Error('Client not ready yet');
    await this.client.invoke({ _: 'leaveChat', chat_id: chatId });
    return { ok: true };
  }

  async deleteChatHistory(chatId: number, removeFromChatList = true): Promise<{ ok: boolean }> {
    if (!this._ready) throw new Error('Client not ready yet');
    await this.client.invoke({
      _: 'deleteChatHistory',
      chat_id: chatId,
      remove_from_chat_list: removeFromChatList,
      revoke: false,
    });
    return { ok: true };
  }

  // ─── Invite Links ───────────────────────────────────────────────────

  async createChatInviteLink(chatId: number, expireDate?: number, memberLimit?: number): Promise<any> {
    if (!this._ready) throw new Error('Client not ready yet');
    const params: Record<string, unknown> = { _: 'createChatInviteLink', chat_id: chatId };
    if (expireDate !== undefined) params.expire_date = expireDate;
    if (memberLimit !== undefined) params.member_limit = memberLimit;
    return await this.client.invoke(params);
  }

  async getChatInviteLinks(chatId: number): Promise<any[]> {
    if (!this._ready) throw new Error('Client not ready yet');
    const result = await this.client.invoke({
      _: 'getChatInviteLinks',
      chat_id: chatId,
      creator_user_id: (await this.client.invoke({ _: 'getMe' })).id,
      is_revoked: false,
      limit: 50,
    }) as { invite_links?: any[] };
    return result.invite_links || [];
  }

  async editChatInviteLink(chatId: number, inviteLink: string, expireDate?: number, memberLimit?: number): Promise<any> {
    if (!this._ready) throw new Error('Client not ready yet');
    const params: Record<string, unknown> = { _: 'editChatInviteLink', chat_id: chatId, invite_link: inviteLink };
    if (expireDate !== undefined) params.expire_date = expireDate;
    if (memberLimit !== undefined) params.member_limit = memberLimit;
    return await this.client.invoke(params);
  }

  async revokeChatInviteLink(chatId: number, inviteLink: string): Promise<any> {
    if (!this._ready) throw new Error('Client not ready yet');
    return await this.client.invoke({
      _: 'revokeChatInviteLink',
      chat_id: chatId,
      invite_link: inviteLink,
    });
  }

  // ─── Permissions ─────────────────────────────────────────────────────

  async getMyPermissions(chatId: number): Promise<Record<string, unknown>> {
    if (!this._ready) return {};
    try {
      const chat = await this.getRawChat(chatId);
      const me = await this.client.invoke({ _: 'getMe' }) as { id: number };
      const perms: Record<string, unknown> = {
        my_user_id: me.id,
        is_owner: false,
        is_admin: false,
        can_send_messages: false,
        can_restrict_members: false,
        can_promote_members: false,
        can_change_info: false,
        can_pin_messages: false,
        can_invite_users: false,
        can_delete_messages: false,
        can_manage_chat: false,
      };

      if (chat.type._ === 'chatTypeSupergroup') {
        const sg: any = await this.client.invoke({ _: 'getSupergroup', supergroup_id: chat.type.supergroup_id });
        const s = sg.status;
        const isChannel = !!chat.type.is_channel;
        if (s._ === 'chatMemberStatusCreator') {
          perms.is_owner = true;
          perms.is_admin = true;
          perms.can_send_messages = true;
          perms.can_restrict_members = true;
          perms.can_promote_members = true;
          perms.can_change_info = true;
          perms.can_pin_messages = true;
          perms.can_invite_users = true;
          perms.can_delete_messages = true;
          perms.can_manage_chat = true;
        } else if (s._ === 'chatMemberStatusAdministrator') {
          perms.is_admin = true;
          perms.can_send_messages = isChannel ? !!s.can_post_messages : true;
          perms.can_restrict_members = !!s.can_restrict_members;
          perms.can_promote_members = !!s.can_promote_members;
          perms.can_change_info = !!s.can_change_info;
          perms.can_pin_messages = !!s.can_pin_messages;
          perms.can_invite_users = !!s.can_invite_users;
          perms.can_delete_messages = !!s.can_delete_messages;
          perms.can_manage_chat = !!s.can_manage_chat;
        }
        if (isChannel && s._ === 'chatMemberStatusMember') {
          perms.can_send_messages = false;
        }
      } else if (chat.type._ === 'chatTypeBasicGroup') {
        const bg: any = await this.client.invoke({ _: 'getBasicGroup', basic_group_id: chat.type.basic_group_id });
        const s = bg.status;
        if (s._ === 'chatMemberStatusCreator') {
          perms.is_owner = true;
          perms.is_admin = true;
          perms.can_send_messages = true;
          perms.can_restrict_members = true;
          perms.can_promote_members = true;
          perms.can_change_info = true;
          perms.can_pin_messages = true;
          perms.can_invite_users = true;
          perms.can_delete_messages = true;
          perms.can_manage_chat = true;
        } else if (s._ === 'chatMemberStatusAdministrator') {
          perms.is_admin = true;
          perms.can_send_messages = true;
          perms.can_restrict_members = true;
          perms.can_promote_members = true;
          perms.can_change_info = true;
          perms.can_invite_users = true;
          perms.can_delete_messages = true;
          perms.can_manage_chat = true;
        }
      }

      return perms;
    } catch (e) {
      console.warn('getMyPermissions failed:', (e as Error).message);
      return {};
    }
  }

  // ─── Helpers ────────────────────────────────────────────────────────

  private async _resolveChatMembers(members: any[]): Promise<any[]> {
    return Promise.all(members.map(async (m) => {
      const sender = m.member_id || { _: 'messageSenderUser', user_id: 0 };
      const userInfo = await this.resolver.resolveSender(sender);
      const status = m.status?._?.replace('chatMemberStatus', '') || 'member';
      return {
        user_id: sender.user_id || sender.chat_id || 0,
        name: userInfo?.name || 'Unknown',
        status,
        joined_date: m.joined_chat_date,
      };
    }));
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
    } catch (e) { console.warn('getMessage around failed:', e); }

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

    const centerDate = target ? target.date : 0;
    const older = (await Promise.all(
      (olderResult.messages || []).map(m => this.formatter.format(m, senderCache))
    )).filter(Boolean).filter(m => {
      const fm = m as FormattedMessage;
      if (target && fm.id === messageId) return false;
      return fm.date < centerDate || (fm.date === centerDate && fm.id < messageId);
    }).sort((a, b) => (a as FormattedMessage).date - (b as FormattedMessage).date) as FormattedMessage[];

    const newer = (await Promise.all(
      (newerResult.messages || []).map(m => this.formatter.format(m, senderCache))
    )).filter(Boolean).filter(m => {
      const fm = m as FormattedMessage;
      return fm.date > centerDate || (fm.date === centerDate && fm.id > messageId);
    }).sort((a, b) => (a as FormattedMessage).date - (b as FormattedMessage).date).slice(0, half) as FormattedMessage[];

    const allMsgs = [...older, ...(target ? [target] : []), ...newer];
    const chat = this._chats.get(chatId);
    return { chat: { id: chatId, title: chat ? chat.title : 'Unknown group' }, messages: allMsgs, targetIndex: older.length };
  }

  async getMessageMedia(chatId: number, messageId: number): Promise<{ path: string; mediaPath?: string } | null> {
    try {
      const msg = await this.client.invoke({ _: 'getMessage', chat_id: chatId, message_id: messageId }) as RawTdMessage;
      if (!msg || !msg.content) return null;
      await this.client.invoke({ _: 'openMessageContent', chat_id: chatId, message_id: messageId }).catch(() => {});

      const content = msg.content as Record<string, unknown>;
      const allIds: number[] = [];
      let targetId = 0;

      const collect = (obj: Record<string, unknown>, ...keys: string[]) => {
        for (const key of keys) {
          const val = obj[key];
          if (!val) continue;
          const arr = Array.isArray(val) ? val : [val];
          for (const item of arr) {
            const f = (item as Record<string, unknown>)?.['photo']
              || (item as Record<string, unknown>)?.['sticker']
              || (item as Record<string, unknown>)?.['video']
              || (item as Record<string, unknown>)?.['document']
              || (item as Record<string, unknown>)?.['animation']
              || (item as Record<string, unknown>)?.['voice']
              || (item as Record<string, unknown>)?.['audio']
              || item;
            const fileId = (f as Record<string, unknown> | undefined)?.['id'] as number | undefined;
            if (fileId && fileId > 0) allIds.push(fileId);
          }
        }
      };

      const t = content._ as string;
      if (t === 'messagePhoto') {
        const photo = content['photo'] as Record<string, unknown> | undefined;
        const sizes = photo?.['sizes'] as Record<string, unknown>[] | undefined;
        if (sizes) {
          for (const s of sizes) collect(s, 'photo', 'sizes');
          const lastSize = sizes[sizes.length - 1];
          const lastFile = (lastSize['photo'] || lastSize['sizes']) as Record<string, unknown> | Record<string, unknown>[] | undefined;
          if (lastFile) {
            const f = Array.isArray(lastFile) ? lastFile[0] : lastFile;
            targetId = (f?.['id'] as number) || 0;
          }
        }
      } else if (t === 'messageSticker') {
        collect(content['sticker'] as Record<string, unknown>, 'sticker', 'thumbnail');
        const sf = (content['sticker'] as Record<string, unknown> | undefined)?.['sticker'] as Record<string, unknown> | undefined;
        targetId = (sf?.['id'] as number) || 0;
      } else {
        const cfg: Record<string, string> = { messageVideo: 'video', messageDocument: 'document', messageAnimation: 'animation', messageVoiceNote: 'voice_note', messageVideoNote: 'video_note', messageAudio: 'audio' };
        const key = cfg[t];
        if (key) {
          const media = content[key] as Record<string, unknown> | undefined;
          if (media) {
            collect(media, key.replace('_note', '').replace('_', ''), 'thumbnail');
            const main = media[key.replace('_note', '').replace('_', '')] as Record<string, unknown> | undefined;
            // Poll for thumbnail first, main file second
            const thumb = media['thumbnail'] as Record<string, unknown> | undefined;
            const thumbFile = thumb?.['file'] as Record<string, unknown> | undefined;
            targetId = (thumbFile?.['id'] as number) || (main?.['id'] as number) || 0;
          }
        }
      }

      const uniqueIds = [...new Set(allIds)];
      await Promise.all(uniqueIds.map(id => this.client.invoke({ _: 'downloadFile', file_id: id, priority: 1 }).catch(() => {})));

      // Poll specifically for the highest-quality file
      if (targetId > 0) {
        for (let attempt = 0; attempt < 15; attempt++) {
          await new Promise(r => setTimeout(r, 1000));
          const fi = await this.client.invoke({ _: 'getFile', file_id: targetId }).catch(() => null) as Record<string, unknown> | null;
          const local = fi?.['local'] as Record<string, unknown> | undefined;
          const path = local?.['path'] as string | undefined;
          if (path) return { path };
        }
      }

      const formatted = await this.formatter.format(msg);
      if (formatted?.filePath) {
        const result: { path: string; mediaPath?: string } = { path: formatted.filePath };
        if (formatted.mediaPath) result.mediaPath = formatted.mediaPath;
        return result;
      }
      return { path: '' };
    } catch (e) { console.warn('getMessageMedia failed:', (e as Error).message); return null; }
  }
}

export default TelegramLSPClient;
