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
const pkg = require(path.join(process.cwd(), 'package.json')) as { version: string };

export class TelegramLSPClient {
  client: any;
  _ready = false;
  _keepOnlineTimer: ReturnType<typeof setTimeout> | undefined;
  _chats: Map<number, RawTdChat> = new Map();
  _chatsLoaded = false;
  _pinnedMessageIds: Map<number, number> = new Map();
  private static MAX_CHATS = 500;
  private static MAX_PINNED = 200;

  private _cacheChat(id: number, chat: RawTdChat) {
    if (!this._chats.has(id) && this._chats.size >= TelegramLSPClient.MAX_CHATS) {
      const first = this._chats.keys().next().value;
      if (first !== undefined) this._chats.delete(first);
    }
    this._chats.set(id, chat);
  }

  private _cachePinned(chatId: number, msgId: number) {
    if (!this._pinnedMessageIds.has(chatId) && this._pinnedMessageIds.size >= TelegramLSPClient.MAX_PINNED) {
      const first = this._pinnedMessageIds.keys().next().value;
      if (first !== undefined) this._pinnedMessageIds.delete(first);
    }
    this._pinnedMessageIds.set(chatId, msgId);
  }

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
      const osType = process.platform === 'darwin' ? 'macOS' : process.platform === 'win32' ? 'Windows' : 'Linux';
      this.client = tdl.createClient({
        apiId: TG_API_ID,
        apiHash: TG_API_HASH,
        databaseDirectory: path.join(dataDir, 'tdlib_db'),
        filesDirectory: path.join(dataDir, 'tdlib_files'),
        tdlibParameters: {
          device_model: 'telegram.nvim',
          application_version: pkg.version,
          system_version: osType,
        },
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
      this._pinnedMessageIds,
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
      await this.client.invoke({ _: 'setOption', name: 'online', value: { _: 'optionValueBoolean', value: true } }).catch(() => {});
      const keepOnline = () => {
        if (!this._ready) return;
        this.client.invoke({ _: 'setOption', name: 'online', value: { _: 'optionValueBoolean', value: true } }).catch(() => {});
        this._keepOnlineTimer = setTimeout(keepOnline, 30000);
      };
      this._keepOnlineTimer = setTimeout(keepOnline, 30000);
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
      unreadMentionCount: chat.unread_mention_count || 0,
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
        if (!group.onlineMemberCount && info.online_member_count) group.onlineMemberCount = info.online_member_count;
      } else if (chat.type._ === 'chatTypeBasicGroup') {
        const bg: any = await this.client.invoke({ _: 'getBasicGroup', basic_group_id: chat.type.basic_group_id });
        if (bg.status._ === 'chatMemberStatusLeft' || bg.status._ === 'chatMemberStatusBanned' || !bg.is_active) return null;
        group.memberCount = bg.member_count;
        if (bg.status._ === 'chatMemberStatusCreator') {
          group.owner = await this.resolver.resolveSender(bg.status.member_id!);
        }
        const info: any = await this.client.invoke({ _: 'getBasicGroupFullInfo', basic_group_id: chat.type.basic_group_id });
        group.description = info.description;
        if (!group.onlineMemberCount && info.online_member_count) group.onlineMemberCount = info.online_member_count;
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
      unreadMentionCount: chat.unread_mention_count || 0,
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

  async getSavedMessages(): Promise<ChatInfo> {
    if (!this._ready) throw new Error('Client not ready yet');
    const me = await this.client.invoke({ _: 'getMe' }) as { id: number };
    const chat = await this.client.invoke({
      _: 'createPrivateChat',
      user_id: me.id,
      force: true,
    }) as RawTdChat;
    this._cacheChat(chat.id, chat);
    const enriched = await this._enrichPrivate(chat);
    if (enriched) { enriched.isSaved = true; enriched.title = 'Favorites'; return enriched; }
    return {
      id: chat.id,
      title: 'Favorites',
      type: 'private',
      unreadCount: chat.unread_count || 0,
      unreadMentionCount: chat.unread_mention_count || 0,
      onlineMemberCount: chat.online_member_count || 0,
      isSaved: true,
    };
  }

  async searchUserByUsername(username: string): Promise<ChatInfo> {
    if (!this._ready) throw new Error('Client not ready yet');
    const clean = username.replace(/^@/, '');
    const chat = await this.client.invoke({
      _: 'searchPublicChat',
      username: clean,
    }) as RawTdChat;
    if (!chat || !chat.id) throw new Error('User not found');
    this._cacheChat(chat.id, chat);
    if (chat.type._ === 'chatTypePrivate' || chat.type._ === 'chatTypeSecret') {
      const enriched = await this._enrichPrivate(chat);
      if (enriched) return enriched;
    }
    return {
      id: chat.id,
      title: chat.title,
      type: chat.type._ === 'chatTypePrivate' || chat.type._ === 'chatTypeSecret' ? 'private' : 'group',
      unreadCount: chat.unread_count || 0,
      unreadMentionCount: chat.unread_mention_count || 0,
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
    this._cacheChat(chat.id, chat);
    const enriched = await this._enrichPrivate(chat);
    if (enriched) return enriched;
    return {
      id: chat.id,
      title: chat.title,
      type: 'private',
      unreadCount: chat.unread_count || 0,
      unreadMentionCount: chat.unread_mention_count || 0,
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

  async getArchivedChats(): Promise<ChatInfo[]> {
    if (!this._ready) throw new Error('Client not ready yet');
    const archived: RawTdChat[] = [];

    let offsetOrder = '9223372036854775807';
    let offsetChatId = 0;
    const limit = 100;
    const MAX_ITERATIONS = 100;

    for (let iterations = 0; iterations < MAX_ITERATIONS; iterations++) {
      const result = await this.client.invoke({
        _: 'getChats',
        chat_list: { _: 'chatListArchive' },
        offset_order: offsetOrder,
        offset_chat_id: offsetChatId,
        limit,
      }) as { chat_ids: number[] };
      const chatIds = result.chat_ids;
      if (!chatIds || chatIds.length === 0) break;

      for (const id of chatIds) {
        const chat = await this.client.invoke({ _: 'getChat', chat_id: id }) as RawTdChat;
        const inArchive = (chat.positions || []).some(p => p.list && p.list._ === 'chatListArchive');
        if (!inArchive) continue;
        archived.push(chat);
      }

      if (chatIds.length < limit) break;
      const prevOrder = offsetOrder;
      const prevChatId = offsetChatId;
      offsetChatId = chatIds[chatIds.length - 1];
      const lastChat = archived.find(c => c.id === offsetChatId);
      if (lastChat) {
        const pos = (lastChat.positions || []).find(p => p.list && p.list._ === 'chatListArchive');
        if (pos) offsetOrder = String(pos.order);
      }
      if (offsetOrder === prevOrder || offsetChatId === prevChatId) break;
    }

    const results = archived.map(async (chat) => {
      const t = chat.type._;
      if (t === 'chatTypeBasicGroup' || t === 'chatTypeSupergroup') {
        const g = await this._enrichGroup(chat);
        if (!g) return null;
        return {
          ...g,
          type: (t === 'chatTypeSupergroup' && chat.type.is_channel) ? 'channel' as const : 'group' as const,
          isArchived: true,
        };
      }
      if (t === 'chatTypePrivate' || t === 'chatTypeSecret') {
        const info = await this._enrichPrivate(chat);
        if (info) return { ...info, isArchived: true };
      }
      return null;
    });

    const enriched = await Promise.all(results);
    return enriched.filter(Boolean) as ChatInfo[];
  }

  private async _parseMD(text: string): Promise<{ _: string; text: string; entities: unknown[] }> {
    try {
      const parsed = await this.client.invoke({
        _: 'parseTextEntities',
        text,
        parse_mode: { _: 'textParseModeMarkdown' },
      }) as { text: string; entities: unknown[] };
      if (parsed && parsed.entities) return { _: 'formattedText', text: parsed.text, entities: parsed.entities };
    } catch (e) {
      console.warn('Markdown parse failed:', (e as Error).message);
    }
    return { _: 'formattedText', text, entities: [] };
  }

  async sendMessage(chatId: number, text: string, replyTo?: number): Promise<FormattedMessage | null> {
    if (!this._ready) throw new Error('Client not ready yet');
    const formatted = await this._parseMD(text);
    const params: Record<string, unknown> = {
      _: 'sendMessage',
      chat_id: chatId,
      input_message_content: {
        _: 'inputMessageText',
        text: formatted,
      },
    };
    if (replyTo) params.reply_to = { _: 'inputMessageReplyToMessage', message_id: replyTo };
    const result = await this.client.invoke(params) as RawTdMessage;
    const msg = await this.formatter.format(result);
    if (msg && text !== msg.text) msg.text = text;
    return msg;
  }

  async editMessage(chatId: number, messageId: number, text: string): Promise<FormattedMessage | null> {
    if (!this._ready) throw new Error('Client not ready yet');
    const formatted = await this._parseMD(text);
    await this.client.invoke({
      _: 'editMessageText',
      chat_id: chatId,
      message_id: messageId,
      input_message_content: {
        _: 'inputMessageText',
        text: formatted,
      },
    });
    try {
      const updated = await this.client.invoke({
        _: 'getMessage',
        chat_id: chatId,
        message_id: messageId,
      }) as RawTdMessage;
      const msg = await this.formatter.format(updated);
      if (msg && text !== msg.text) msg.text = text;
      return msg;
    } catch {
      return null;
    }
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

  async pinMessage(chatId: number, messageId: number): Promise<{ ok: boolean }> {
    if (!this._ready) throw new Error('Client not ready yet');
    await this.client.invoke({
      _: 'pinChatMessage',
      chat_id: chatId,
      message_id: messageId,
    });
    return { ok: true };
  }

  async unpinMessage(chatId: number, messageId: number): Promise<{ ok: boolean }> {
    if (!this._ready) throw new Error('Client not ready yet');
    await this.client.invoke({
      _: 'unpinChatMessage',
      chat_id: chatId,
      message_id: messageId,
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
    let inviteLink = '';
    const chatObj = chat as any;
    const chatPerms = chatObj.permissions as Record<string, unknown> | undefined;
    const defaultRestricted = chatPerms?.can_send_basic_messages === false;
    const defaultPermissions = chatPerms ? {
      can_send_messages: chatPerms.can_send_basic_messages !== false,
      can_send_audios: chatPerms.can_send_audios !== false,
      can_send_documents: chatPerms.can_send_documents !== false,
      can_send_photos: chatPerms.can_send_photos !== false,
      can_send_videos: chatPerms.can_send_videos !== false,
      can_send_video_notes: chatPerms.can_send_video_notes !== false,
      can_send_voice_notes: chatPerms.can_send_voice_notes !== false,
      can_send_polls: chatPerms.can_send_polls !== false,
      can_send_other_messages: chatPerms.can_send_other_messages !== false,
      can_add_web_page_previews: chatPerms.can_add_link_previews !== false,
      can_change_info: chatPerms.can_change_info === true,
      can_invite_users: chatPerms.can_invite_users === true,
      can_pin_messages: chatPerms.can_pin_messages === true,
      can_manage_topics: chatPerms.can_manage_topics === true,
    } : undefined;
    try {
      if (chat.type._ === 'chatTypeSupergroup') {
        const sg = await this.client.invoke({ _: 'getSupergroup', supergroup_id: chat.type.supergroup_id }) as { member_count: number };
        memberCount = sg.member_count;
        const info = await this.client.invoke({ _: 'getSupergroupFullInfo', supergroup_id: chat.type.supergroup_id }) as any;
        description = info.description || '';
        inviteLink = typeof info.invite_link === 'string' ? info.invite_link : info.invite_link?.invite_link || '';
        if (!chat.online_member_count && info.online_member_count) chat.online_member_count = info.online_member_count;
      } else if (chat.type._ === 'chatTypeBasicGroup') {
        const bg = await this.client.invoke({ _: 'getBasicGroup', basic_group_id: chat.type.basic_group_id }) as { member_count: number };
        memberCount = bg.member_count;
        const info = await this.client.invoke({ _: 'getBasicGroupFullInfo', basic_group_id: chat.type.basic_group_id }) as any;
        description = info.description || '';
        inviteLink = typeof info.invite_link === 'string' ? info.invite_link : info.invite_link?.invite_link || '';
        if (!chat.online_member_count && info.online_member_count) chat.online_member_count = info.online_member_count;
      }
    } catch (e) { console.warn('getChatInfo member count failed:', (e as Error).message); }
    let pinnedId = this._pinnedMessageIds.get(chatId) || 0;
    if (!pinnedId) {
      try {
        const result = await this.client.invoke({
          _: 'searchChatMessages',
          chat_id: chatId,
          query: '',
          limit: 1,
          filter: { _: 'searchMessagesFilterPinned' },
        }) as { messages: { id: number }[] };
        if (result.messages?.length > 0) {
          pinnedId = result.messages[0].id;
          this._cachePinned(chatId, pinnedId);
        }
      } catch (e) { /* no pinned messages found */ }
    }
    return {
      id: chat.id,
      title: chat.title,
      unreadCount: chat.unread_count || 0,
      lastReadInboxMessageId: chat.last_read_inbox_message_id || 0,
      onlineMemberCount: chat.online_member_count || 0,
      memberCount,
      description,
      inviteLink,
      defaultRestricted,
      defaultPermissions,
      pinnedMessageId: pinnedId,
      draftText: (() => {
        try {
          const dm = (chat as any).draft_message;
          if (dm && dm.content && dm.content._ === 'draftMessageContentText') {
            return dm.content.text?.text || '';
          }
        } catch {}
        return '';
      })(),
    };
  }

  async archiveChat(chatId: number): Promise<{ ok: boolean }> {
    if (!this._ready) throw new Error('Client not ready yet');
    await this.client.invoke({
      _: 'addChatToList',
      chat_id: chatId,
      chat_list: { _: 'chatListArchive' },
    });
    return { ok: true };
  }

  async unarchiveChat(chatId: number): Promise<{ ok: boolean }> {
    if (!this._ready) throw new Error('Client not ready yet');
    await this.client.invoke({
      _: 'addChatToList',
      chat_id: chatId,
      chat_list: { _: 'chatListMain' },
    });
    return { ok: true };
  }

  async toggleChatIsMarkedAsUnread(chatId: number, isMarkedAsUnread: boolean): Promise<{ ok: boolean }> {
    if (!this._ready) throw new Error('Client not ready yet');
    await this.client.invoke({
      _: 'toggleChatIsMarkedAsUnread',
      chat_id: chatId,
      is_marked_as_unread: isMarkedAsUnread,
    });
    return { ok: true };
  }

  async muteChat(chatId: number, muteFor: number): Promise<{ ok: boolean }> {
    if (!this._ready) throw new Error('Client not ready yet');
    await this.client.invoke({
      _: 'setChatNotificationSettings',
      chat_id: chatId,
      notification_settings: {
        _: 'chatNotificationSettings',
        use_default_mute_for: false,
        mute_for: muteFor,
        use_default_sound: true,
        use_default_show_preview: true,
        use_default_mute_stories: true,
        use_default_story_sound: true,
        use_default_show_story_poster: true,
        use_default_disable_pinned_message_notifications: true,
        use_default_disable_mention_notifications: true,
      },
    });
    return { ok: true };
  }

  async unmuteChat(chatId: number): Promise<{ ok: boolean }> {
    if (!this._ready) throw new Error('Client not ready yet');
    await this.client.invoke({
      _: 'setChatNotificationSettings',
      chat_id: chatId,
      notification_settings: {
        _: 'chatNotificationSettings',
        use_default_mute_for: true,
        use_default_sound: true,
        use_default_show_preview: true,
        use_default_mute_stories: true,
        use_default_story_sound: true,
        use_default_show_story_poster: true,
        use_default_disable_pinned_message_notifications: true,
        use_default_disable_mention_notifications: true,
      },
    });
    return { ok: true };
  }

  async translateText(text: string, toLanguageCode: string): Promise<string | null> {
    if (!this._ready) throw new Error('Client not ready yet');
    try {
      const result = await this.client.invoke({
        _: 'translateText',
        text: { _: 'formattedText', text, entities: [] },
        to_language_code: toLanguageCode,
        tone: '',
      }) as { text?: string };
      return result.text || null;
    } catch (e) {
      const msg = (e as Error).message;
      console.warn('translateText failed:', msg);
      throw new Error('Translation failed: ' + msg);
    }
  }

  async setChatDraftMessage(chatId: number, text: string): Promise<boolean> {
    if (!this._ready) throw new Error('Client not ready yet');
    try {
      await this.client.invoke({
        _: 'setChatDraftMessage',
        chat_id: chatId,
        topic_id: null,
        draft_message: text.length > 0 ? {
          _: 'draftMessage',
          reply_to: null,
          date: Math.floor(Date.now() / 1000),
          content: {
            _: 'draftMessageContentText',
            text: { _: 'formattedText', text, entities: [] },
            link_preview_options: { _: 'linkPreviewOptions', is_disabled: true, url: '', force_small_media: false, force_large_media: false, show_above_text: false },
          },
          effect_id: 0,
          suggested_post_info: null,
        } : null,
      });
      return true;
    } catch (e) {
      const msg = (e as Error).message;
      console.warn('setChatDraftMessage failed:', msg);
      throw new Error('Draft save failed: ' + msg);
    }
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

  async searchMessages(chatId: number, query: string, limit = 50, filter?: string) {
    if (!this._ready) throw new Error('Client not ready yet');
    const params: Record<string, unknown> = {
      _: 'searchChatMessages',
      chat_id: chatId,
      topic_id: 0,
      query,
      limit,
      from_message_id: 0,
      offset: 0,
    };
    if (filter) params.filter = { _: filter };
    const result = await this.client.invoke(params) as { messages?: RawTdMessage[] };
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
    const [result] = await Promise.all([
      this.client.invoke({
        _: 'getChatHistory',
        chat_id: chatId,
        from_message_id: fromMessageId,
        offset,
        limit,
        only_local: false,
      }) as Promise<{ messages?: RawTdMessage[] }>,
      this.formatter.preloadAdminTitles(chatId),
    ]);
    const tdlibMs = Date.now() - t0;
    const chat = this._chats.get(chatId);
    const t1 = Date.now();
    const raw = result.messages || [];

    // Backfill interaction_info for messages that lack it (some TDLib versions
    // don't include it in getChatHistory responses)
    let backfillCount = 0;
    const MAX_BACKFILL = 5;
    for (const m of raw) {
      if (!m.interaction_info && backfillCount < MAX_BACKFILL && m.id > 0) {
        backfillCount++;
        try {
          const detailed = await this.client.invoke({
            _: 'getMessage',
            chat_id: chatId,
            message_id: m.id,
          }) as RawTdMessage;
          if (detailed.interaction_info) {
            m.interaction_info = detailed.interaction_info;
          }
        } catch {}
      }
    }

    const senderCache = raw.length > 1 ? await this.formatter.preloadSenders(raw) : null;
    let msgs = (await Promise.all(raw.map(m => this.formatter.format(m, senderCache, chatId)))).filter(Boolean) as FormattedMessage[];

    msgs.sort((a, b) => a.date - b.date);
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

    let backfillCount = 0;
    const MAX_BACKFILL = 5;
    for (const m of raw) {
      if (!m.interaction_info && backfillCount < MAX_BACKFILL && m.id > 0) {
        backfillCount++;
        try {
          const detailed = await this.client.invoke({
            _: 'getMessage',
            chat_id: chatId,
            message_id: m.id,
          }) as RawTdMessage;
          if (detailed.interaction_info) m.interaction_info = detailed.interaction_info;
        } catch {}
      }
    }

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
          can_send_basic_messages: false,
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
          can_send_basic_messages: true,
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

  async addChatMember(chatId: number, userId: number): Promise<{ ok: boolean; inviteLink?: string; error?: string }> {
    if (!this._ready) throw new Error('Client not ready yet');
    try {
      await this.client.invoke({ _: 'addChatMember', chat_id: chatId, user_id: userId });
      return { ok: true };
    } catch (e) {
      try {
        const link = await this.createChatInviteLink(chatId);
        return { ok: false, inviteLink: link.invite_link || 'failed to generate' };
      } catch {
        return { ok: false, error: (e as Error).message };
      }
    }
  }

  async searchChatMembers(chatId: number, query = '', limit = 200): Promise<any[]> {
    if (!this._ready) throw new Error('Client not ready yet');
    const [admins, members] = await Promise.all([
      this.client.invoke({
        _: 'searchChatMembers',
        chat_id: chatId,
        query,
        limit,
        filter: { _: 'chatMembersFilterAdministrators' },
      }) as Promise<{ members?: any[] }>,
      this.client.invoke({
        _: 'searchChatMembers',
        chat_id: chatId,
        query,
        limit,
        filter: { _: 'chatMembersFilterMembers' },
      }) as Promise<{ members?: any[] }>,
    ]);
    const seen = new Set<number>();
    const all = [...(admins.members || []), ...(members.members || [])];
    const deduped = all.filter((m: any) => {
      const id = m.member_id?.user_id || m.member_id?.chat_id || 0;
      if (seen.has(id)) return false;
      seen.add(id);
      return true;
    });
    return this._resolveChatMembers(deduped);
  }

  async setChatDefaultPermissions(chatId: number, permissions: Record<string, boolean>): Promise<{ ok: boolean }> {
    if (!this._ready) throw new Error('Client not ready yet');
    const perms: Record<string, unknown> = { _: 'chatPermissions' };
    perms.can_send_basic_messages = permissions.can_send_messages !== false;
    perms.can_send_audios = permissions.can_send_audios !== false;
    perms.can_send_documents = permissions.can_send_documents !== false;
    perms.can_send_photos = permissions.can_send_photos !== false;
    perms.can_send_videos = permissions.can_send_videos !== false;
    perms.can_send_video_notes = permissions.can_send_video_notes !== false;
    perms.can_send_voice_notes = permissions.can_send_voice_notes !== false;
    perms.can_send_polls = permissions.can_send_polls !== false;
    perms.can_send_other_messages = permissions.can_send_other_messages !== false;
    perms.can_add_link_previews = permissions.can_add_web_page_previews !== false;
    perms.can_change_info = permissions.can_change_info === true;
    perms.can_invite_users = permissions.can_invite_users === true;
    perms.can_pin_messages = permissions.can_pin_messages === true;
    perms.can_manage_topics = permissions.can_manage_topics === true;
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
    let creatorUserId: number | undefined;
    try {
      const me = await this.client.invoke({ _: 'getMe' }) as { id: number };
      creatorUserId = me.id;
    } catch (e) { console.warn('getChatInviteLinks: getMe failed', (e as Error).message); }
    if (!creatorUserId) return [];
    const result = await this.client.invoke({
      _: 'getChatInviteLinks',
      chat_id: chatId,
      creator_user_id: creatorUserId,
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

  // ─── Reactions ────────────────────────────────────────────────────────

  async addMessageReaction(chatId: number, messageId: number, emoji: string): Promise<{ ok: boolean; error?: string }> {
    if (!this._ready) return { ok: false, error: 'Client not ready' };
    try {
      await this.client.invoke({
        _: 'addMessageReaction',
        chat_id: chatId,
        message_id: messageId,
        reaction_type: { _: 'reactionTypeEmoji', emoji },
      });
      return { ok: true };
    } catch (e) {
      const msg = (e as Error).message;
      console.error('addMessageReaction failed:', msg);
      return { ok: false, error: msg };
    }
  }

  async removeMessageReaction(chatId: number, messageId: number, emoji: string): Promise<{ ok: boolean; error?: string }> {
    if (!this._ready) return { ok: false, error: 'Client not ready' };
    try {
      await this.client.invoke({
        _: 'removeMessageReaction',
        chat_id: chatId,
        message_id: messageId,
        reaction_type: { _: 'reactionTypeEmoji', emoji },
      });
      return { ok: true };
    } catch (e) {
      const msg = (e as Error).message;
      console.error('removeMessageReaction failed:', msg);
      return { ok: false, error: msg };
    }
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

      const chatPerms = (chat as any).permissions as Record<string, unknown> | undefined;
      const canSendByDefault = chatPerms?.can_send_basic_messages !== false;

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
        } else if (s._ === 'chatMemberStatusMember') {
          perms.can_send_messages = isChannel ? false : canSendByDefault;
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
        } else if (s._ === 'chatMemberStatusMember') {
          perms.can_send_messages = canSendByDefault;
        }
      } else if (chat.type._ === 'chatTypePrivate' || chat.type._ === 'chatTypeSecret') {
        perms.can_send_messages = true;
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
        custom_title: m.tag as string | undefined,
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
    } catch {} // saved cursor may point to a deleted message

    await this.formatter.preloadAdminTitles(chatId);

    const [olderResult, newerResult] = await Promise.all([
      this.client.invoke({
        _: 'getChatHistory', chat_id: chatId, from_message_id: messageId, offset: 0, limit: half + 1, only_local: false,
      }).catch(() => ({ messages: [] })),
      this.client.invoke({
        _: 'getChatHistory', chat_id: chatId, from_message_id: messageId, offset: -half, limit: half, only_local: false,
      }).catch(() => ({ messages: [] })),
    ]) as [{ messages?: RawTdMessage[] }, { messages?: RawTdMessage[] }];

    const allRaw = [...(olderResult.messages || []), ...(newerResult.messages || [])];

    let backfillCount = 0;
    const MAX_BACKFILL = 5;
    for (const m of allRaw) {
      if (!m.interaction_info && backfillCount < MAX_BACKFILL && m.id > 0) {
        backfillCount++;
        try {
          const detailed = await this.client.invoke({
            _: 'getMessage',
            chat_id: chatId,
            message_id: m.id,
          }) as RawTdMessage;
          if (detailed.interaction_info) m.interaction_info = detailed.interaction_info;
        } catch {}
      }
    }

    const senderCache = allRaw.length > 1 ? await this.formatter.preloadSenders(allRaw) : null;

    const centerDate = target ? target.date : 0;
    const older = (await Promise.all(
      (olderResult.messages || []).map(m => this.formatter.format(m, senderCache, chatId))
    )).filter(Boolean).filter(m => {
      const fm = m as FormattedMessage;
      if (target && fm.id === messageId) return false;
      return fm.date < centerDate || (fm.date === centerDate && fm.id < messageId);
    }).sort((a, b) => (a as FormattedMessage).date - (b as FormattedMessage).date) as FormattedMessage[];

    const newer = (await Promise.all(
      (newerResult.messages || []).map(m => this.formatter.format(m, senderCache, chatId))
    )).filter(Boolean).filter(m => {
      const fm = m as FormattedMessage;
      return fm.date > centerDate || (fm.date === centerDate && fm.id > messageId);
    }).sort((a, b) => (a as FormattedMessage).date - (b as FormattedMessage).date).slice(0, half) as FormattedMessage[];

    const allMsgs = [...older, ...(target ? [target] : []), ...newer];
    const chat = this._chats.get(chatId);
    return { chat: { id: chatId, title: chat ? chat.title : 'Unknown group' }, messages: allMsgs, targetIndex: older.length };
  }

  async getUserProfile(userId: number): Promise<Record<string, unknown> | null> {
    if (!this._ready) throw new Error('Client not ready yet');
    try {
      const [user, fullInfo] = await Promise.all([
        this.client.invoke({ _: 'getUser', user_id: userId }) as Promise<any>,
        this.client.invoke({ _: 'getUserFullInfo', user_id: userId }).catch(() => null) as Promise<any>,
      ]);
      if (!user) return null;
      // Resolve user status for "last seen"
      let status = '';
      if (user.status) {
        switch (user.status._) {
          case 'userStatusOnline':
            status = 'online';
            break;
          case 'userStatusOffline':
            status = 'offline:' + (user.status.was_online || 0);
            break;
          case 'userStatusRecently':
            status = 'recently';
            break;
          case 'userStatusLastWeek':
            status = 'last_week';
            break;
          case 'userStatusLastMonth':
            status = 'last_month';
            break;
          default:
            status = '';
        }
      }
      const gic = fullInfo?.group_in_common_count || 0;
      const profile: Record<string, unknown> = {
        id: user.id,
        firstName: user.first_name || '',
        lastName: user.last_name || '',
        username: user.usernames?.editable_username || user.usernames?.active_usernames?.[0] || '',
        phone: user.phone_number || '',
        isPremium: !!user.is_premium,
        isSupport: !!user.is_support,
        isContact: !!user.is_contact,
        isBot: user.type?._ === 'userTypeBot',
        isScam: !!user.is_scam,
        isFake: !!user.is_fake,
        isBlocked: !!fullInfo?.block_list,
        canBeCalled: !!fullInfo?.can_be_called,
        bio: fullInfo?.bio?.text || '',
        groupInCommon: gic,
        status,
        birthdate: fullInfo?.birthdate || null,
      };
      // Include common group names in the profile response
      if (gic > 0) {
        try {
          const groups = await this.getGroupsInCommon(userId);
          profile.commonGroups = groups;
        } catch (_) { /* non-critical */ }
      }
      return profile;
    } catch (e) {
      console.warn('getUserProfile failed:', (e as Error).message);
      return null;
    }
  }

  async getGroupsInCommon(userId: number): Promise<{ id: number; title: string }[]> {
    try {
      if (!this._ready) return [];
      const result = await this.client.invoke({
        _: 'getGroupsInCommon',
        user_id: userId,
        offset_chat_id: 0,
        limit: 100,
      }) as { chat_ids?: number[] };
      if (!result?.chat_ids) return [];
      const results = await Promise.allSettled(result.chat_ids.map(async (id: number) => {
        const chat = await this.client.invoke({ _: 'getChat', chat_id: id }) as { id: number; title: string };
        return { id: chat.id, title: chat.title };
      }));
      const groups = results
        .filter((r): r is PromiseFulfilledResult<{ id: number; title: string }> => r.status === 'fulfilled')
        .map(r => r.value);
      return groups;
    } catch (e) {
      console.warn('getGroupsInCommon failed:', (e as Error).message);
      return [];
    }
  }

  async blockUser(userId: number): Promise<boolean> {
    try {
      if (!this._ready) return false;
      await this.client.invoke({
        _: 'setMessageSenderBlockList',
        sender_id: { _: 'messageSenderUser', user_id: userId },
        block_list: { _: 'blockListMain' },
      });
      return true;
    } catch (e) {
      console.warn('blockUser failed:', (e as Error).message);
      return false;
    }
  }

  async unblockUser(userId: number): Promise<boolean> {
    try {
      if (!this._ready) return false;
      await this.client.invoke({
        _: 'setMessageSenderBlockList',
        sender_id: { _: 'messageSenderUser', user_id: userId },
        block_list: null,
      });
      return true;
    } catch (e) {
      console.warn('unblockUser failed:', (e as Error).message);
      return false;
    }
  }

  async addContact(userId: number): Promise<boolean> {
    try {
      if (!this._ready) return false;
      await this.client.invoke({
        _: 'addContact',
        user_id: userId,
        contact: { _: 'importedContact', phone_number: '', first_name: '', last_name: '', vcard: '' },
        share_phone_number: false,
      });
      return true;
    } catch (e) {
      console.warn('addContact failed:', (e as Error).message);
      return false;
    }
  }

  async deleteContact(userId: number): Promise<boolean> {
    try {
      if (!this._ready) return false;
      await this.client.invoke({
        _: 'deleteContacts',
        user_ids: [userId],
      });
      return true;
    } catch (e) {
      console.warn('deleteContact failed:', (e as Error).message);
      return false;
    }
  }

  async getMessageLink(chatId: number, messageId: number): Promise<string | null> {
    if (!this._ready) throw new Error('Client not ready yet');
    try {
      const result = await this.client.invoke({
        _: 'getMessageLink',
        chat_id: chatId,
        message_id: messageId,
        media_timestamp: 0,
        for_album: false,
        in_message_thread: false,
        checklist_task_id: 0,
        poll_option_id: '',
      }) as { link?: string };
      return result.link || null;
    } catch (e) {
      console.warn('getMessageLink failed:', (e as Error).message);
      return null;
    }
  }

  /**
   * Resolve a t.me message link to chat + message IDs.
   * Returns null on failure (caller can check errMsg for details).
   */
  async getMessageLinkInfo(url: string): Promise<{ chat_id: number; message_id: number; errMsg?: string } | null> {
    if (!this._ready) throw new Error('Client not ready yet');
    try {
      const result = await this.client.invoke({
        _: 'getMessageLinkInfo',
        url: url,
      }) as Record<string, unknown>;
      // TDLib error object
      if (!result || result._ === 'error') {
        const msg = (result as { message?: string }).message || 'Unknown TDLib error';
        return { chat_id: 0, message_id: 0, errMsg: msg };
      }
      // Success
      if (typeof result.chat_id === 'number' && result.message && typeof (result.message as Record<string, unknown>).id === 'number') {
        return { chat_id: result.chat_id, message_id: (result.message as Record<string, unknown>).id as number };
      }
      // Unexpected format
      return { chat_id: 0, message_id: 0, errMsg: `Unexpected response: ${JSON.stringify(result).slice(0, 200)}` };
    } catch (e) {
      const msg = (e as Error).message;
      return { chat_id: 0, message_id: 0, errMsg: msg };
    }
  }

  async getMessageMedia(chatId: number, messageId: number): Promise<{ path: string; mediaPath?: string } | null> {
    try {
      const msg = await this.client.invoke({ _: 'getMessage', chat_id: chatId, message_id: messageId }) as RawTdMessage;
      if (!msg || !msg.content) return null;
      await this.client.invoke({ _: 'openMessageContent', chat_id: chatId, message_id: messageId }).catch(() => {});

      const content = msg.content as Record<string, unknown>;
      const allIds: number[] = [];
      let targetId = 0;

      const getFileId = (obj: Record<string, unknown>): number | undefined => {
        if (typeof obj.id === 'number' && obj.id > 0) return obj.id;
        for (const field of ['photo', 'sticker', 'video', 'document', 'animation', 'voice', 'audio']) {
          const sub = obj[field] as Record<string, unknown> | undefined;
          if (sub && typeof sub.id === 'number' && sub.id > 0) return sub.id;
        }
        return undefined;
      };

      const collect = (obj: Record<string, unknown>, ...keys: string[]) => {
        for (const key of keys) {
          const val = obj[key];
          if (!val) continue;
          const arr = Array.isArray(val) ? val : [val];
          for (const item of arr) {
            const fileId = getFileId(item as Record<string, unknown>);
            if (fileId) allIds.push(fileId);
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
        for (let attempt = 0; attempt < 10; attempt++) {
          await new Promise(r => setTimeout(r, 800));
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

  async shutdown() {
    this.updates.stopListening(this.client);
    if (this._keepOnlineTimer) {
      clearTimeout(this._keepOnlineTimer);
      this._keepOnlineTimer = undefined;
    }
    if (!this._ready) return;
    try {
      await this.client.invoke({ _: 'setOption', name: 'online', value: { _: 'optionValueBoolean', value: false } });
    } catch {}
    try {
      await this.client.invoke({ _: 'close' });
    } catch {}
  }
}

export default TelegramLSPClient;
