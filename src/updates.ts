import type { TdUpdate, RawTdMessage, RawTdChat, FormattedMessage, BroadcastFn } from './types';
import { extractText } from './format';
import type { MessageFormatter } from './format';
import type { Resolver } from './resolve';

export class UpdateDispatcher {
  constructor(
    private formatter: MessageFormatter,
    private resolver: Resolver,
    private chats: Map<number, RawTdChat>,
    private getBroadcast: () => BroadcastFn | undefined,
    private invoke: (q: unknown) => Promise<unknown>,
    private pinnedMessageIds: Map<number, number>,
  ) {}

  private _updateHandler: ((update: TdUpdate) => void) | null = null;

  listen(tdClient: { on: (event: string, handler: (update: TdUpdate) => void) => void; off?: (event: string, handler: (update: TdUpdate) => void) => void }) {
    this._updateHandler = async (update: TdUpdate) => {
      try {
      switch (update._) {
        case 'updateNewChat':
          const chatId = (update.chat as RawTdChat).id;
          if (!this.chats.has(chatId) && this.chats.size >= 500) {
            const first = this.chats.keys().next().value;
            if (first !== undefined) this.chats.delete(first);
          }
          this.chats.set(chatId, update.chat as RawTdChat);
          this.broadcastRaw(update);
          break;
        case 'updateNewMessage':
          await this.handleNewMessage(update.message as RawTdMessage);
          break;
        case 'updateUserChatAction':
          await this.handleUserChatAction(update);
          break;
        case 'updateChatAction':
          await this.handleChatAction(update);
          break;
        case 'updateChatOnlineMemberCount':
          this.handleChatOnlineMemberCount(update);
          break;
        case 'updateMessageSendSucceeded':
          await this.handleMessageSendSucceeded(update);
          break;
        case 'updateChatMember':
          await this.handleChatMemberUpdate(update);
          break;
        case 'updateMessageContent':
          await this.handleMessageContentUpdate(update);
          break;
        case 'updateDeleteMessages':
          await this.handleDeleteMessages(update);
          break;
        case 'updateChatLastMessage':
          await this.handleChatLastMessage(update);
          break;
        case 'updateChatReadInbox':
          this.handleChatReadInbox(update);
          break;
        case 'updateChatUnreadMentionCount':
          this.handleChatUnreadMentionCount(update);
          break;
        case 'updateChatTitle':
          this.handleChatTitle(update);
          break;
        case 'updateChatPermissions':
          this.handleChatPermissions(update);
          break;
        case 'updateUser':
          this.handleUserUpdate(update);
          break;
        case 'updateUserStatus':
          this.handleUserStatusUpdate(update);
          break;
        case 'updateSupergroup':
        case 'updateBasicGroup':
          this.handleGroupUpdate(update);
          break;
        case 'updateSupergroupFullInfo':
        case 'updateBasicGroupFullInfo':
          this.handleGroupFullInfoUpdate(update);
          break;
        case 'updateChatPosition':
          this.handleChatPositionUpdate(update);
          break;
        case 'updateMessageSendFailed':
          this.handleMessageSendFailed(update);
          break;
        case 'updateMessageIsPinned':
          this.handleMessageIsPinned(update);
          break;
        case 'updateMessageInteractionInfo':
          this.handleMessageInteractionInfo(update);
          break;
        case 'updateMessageReactions':
          this.handleMessageReactions(update);
          break;
        case 'updateMessageReadDate':
          this.handleMessageReadDate(update);
          break;
        case 'updateConnectionState':
          this.handleConnectionState(update);
          break;
        case 'updateAuthorizationState':
          this.handleAuthorizationState(update);
          break;
        default:
          this.broadcastRaw(update);
      }
      } catch (e) { console.error('Update handler error:', (e as Error).message); }
    };
    tdClient.on('update', this._updateHandler);
  }

  stopListening(tdClient: { off?: (event: string, handler: (update: TdUpdate) => void) => void }) {
    if (tdClient.off && this._updateHandler) {
      tdClient.off('update', this._updateHandler);
    }
    this._updateHandler = null;
  }

  async handleNewMessage(msg: RawTdMessage) {
    const broadcast = this.getBroadcast();
    if (typeof broadcast !== 'function') return;
    const chat = this.chats.get(msg.chat_id);
    if (msg.chat_id) this.formatter.preloadAdminTitles(msg.chat_id).catch(() => {});
    const formatted = await this.formatter.format(msg, undefined, msg.chat_id);
    let chat_type = 'group';
    if (chat) {
      const t = chat.type._;
      if (t === 'chatTypePrivate' || t === 'chatTypeSecret') chat_type = 'private';
      else if (t === 'chatTypeSupergroup' && chat.type.is_channel) chat_type = 'channel';
    }
    broadcast({
      event: 'newMessage',
      chat: { id: msg.chat_id, title: chat ? chat.title : 'Unknown', type: chat_type },
      ...formatted,
    });
  }

  async handleUserChatAction(update: TdUpdate) {
    const broadcast = this.getBroadcast();
    if (typeof broadcast !== 'function') return;
    const userName = update.user_id ? await this.resolver.getUserName(update.user_id) : 'unknown';
    broadcast({
      event: 'userAction',
      chat_id: update.chat_id,
      user_id: update.user_id,
      user_name: userName,
      action: update.action,
    });
  }

  async handleChatAction(update: TdUpdate) {
    const broadcast = this.getBroadcast();
    if (typeof broadcast !== 'function') return;
    const sender = update.sender_id ? await this.resolver.resolveSender(update.sender_id) : null;
    broadcast({
      event: 'userAction',
      chat_id: update.chat_id,
      user_id: sender ? sender.id : 0,
      user_name: sender ? sender.name : 'unknown',
      action: update.action,
    });
  }

  handleChatOnlineMemberCount(update: TdUpdate) {
    const broadcast = this.getBroadcast();
    if (typeof broadcast !== 'function') return;
    const chat = update.chat_id && this.chats.get(update.chat_id);
    if (chat) chat.online_member_count = update.online_member_count;
    broadcast({
      event: 'chatOnlineMemberCount',
      chat_id: update.chat_id,
      online_member_count: update.online_member_count,
    });
  }

  async handleMessageSendSucceeded(update: TdUpdate) {
    const broadcast = this.getBroadcast();
    if (typeof broadcast !== 'function') return;
    const msg = update.message as RawTdMessage;
    if (!msg) return;
    const formatted = await this.formatter.format(msg);
    if (!formatted) return;
    const chat = this.chats.get(msg.chat_id);
    broadcast({
      event: 'messageSendSucceeded',
      old_message_id: update.old_message_id,
      chat: { id: msg.chat_id, title: chat ? chat.title : 'Unknown group' },
      ...formatted,
    });
  }

  handleMessageSendFailed(update: TdUpdate) {
    const broadcast = this.getBroadcast();
    if (typeof broadcast !== 'function') return;
    const msg = update.message as RawTdMessage | undefined;
    if (!msg) return;
    const old_id = update.old_message_id;
    const chat = this.chats.get(msg.chat_id);
    broadcast({
      event: 'messageSendFailed',
      old_message_id: old_id,
      chat_id: msg.chat_id,
      chat_title: chat ? chat.title : 'Unknown',
      error_message: update.error_message as string || 'Unknown error',
    });
  }

  async handleChatMemberUpdate(update: TdUpdate) {
    const broadcast = this.getBroadcast();
    if (typeof broadcast !== 'function') return;
    if (!update.chat_id) return;
    const chat = this.chats.get(update.chat_id);
    if (!chat) return;
    if (!update.member || update.actor_user_id == null) return;
    const memberId = update.member.user_id || 0;
    const actorUserId = update.actor_user_id;
    if (!memberId) return;
    const memberName = await this.resolver.getUserName(memberId);
    const actorName = actorUserId === memberId
      ? memberName
      : await this.resolver.getUserName(actorUserId);
    broadcast({
      event: 'chatMember',
      chat_id: update.chat_id!,
      chat_title: chat ? chat.title : 'Unknown',
      member: { id: memberId, name: memberName },
      actor: { id: actorUserId, name: actorName },
      old_status: update.old_status,
      new_status: update.new_status,
    });
  }

  async handleMessageContentUpdate(update: TdUpdate) {
    const broadcast = this.getBroadcast();
    if (typeof broadcast !== 'function') return;
    const chatId = update.chat_id;
    const messageId = update.message_id;
    if (!chatId || !messageId) return;
    const newContent = update.new_content as { _: string; text?: { text: string }; caption?: { text: string }; link_preview?: { url?: string; title?: string; description?: string; site_name?: string } } | undefined;
    if (!newContent) return;
    const chat = this.chats.get(chatId);
    const payload: Record<string, unknown> = {
      event: 'messageContentUpdated',
      chat_id: chatId,
      message_id: messageId,
      chat_title: chat ? chat.title : 'Unknown',
      text: extractText(newContent),
      type: newContent._,
    };
    const fileInfo = this.formatter.getFileInfo(newContent as Record<string, unknown>);
    if (fileInfo) {
      if (fileInfo.path) payload.filePath = fileInfo.path;
      if (fileInfo.mediaPath) payload.mediaPath = fileInfo.mediaPath;
      if (fileInfo.mimeType) payload.mimeType = fileInfo.mimeType;
    }
    const lp = newContent.link_preview;
    if (lp?.url) {
      payload.linkPreview = { url: lp.url, title: lp.title, description: lp.description, siteName: lp.site_name };
    }
    broadcast(payload);
  }

  async handleDeleteMessages(update: TdUpdate) {
    const broadcast = this.getBroadcast();
    if (typeof broadcast !== 'function') return;
    const chatId = update.chat_id;
    const messageIds = update.message_ids as number[] | undefined;
    if (!chatId || !messageIds) return;
    broadcast({
      event: 'messagesDeleted',
      chat_id: chatId,
      message_ids: messageIds,
      is_permanent: update.is_permanent,
    });
  }

  async handleChatLastMessage(update: TdUpdate) {
    const broadcast = this.getBroadcast();
    if (typeof broadcast !== 'function') return;
    const chatId = update.chat_id;
    if (!chatId) return;
    const rawMsg = update.last_message as RawTdMessage | null;
    const chat = this.chats.get(chatId);
    if (chat && rawMsg) chat.last_message = rawMsg;
    let formatted = null as FormattedMessage | null;
    if (rawMsg) {
      formatted = await this.formatter.format(rawMsg);
    }
    broadcast({
      event: 'chatLastMessageUpdated',
      chat_id: chatId,
      chat_title: chat ? chat.title : 'Unknown',
      last_message: formatted,
    });
  }

  handleChatReadInbox(update: TdUpdate) {
    const broadcast = this.getBroadcast();
    if (typeof broadcast !== 'function') return;
    const chat = update.chat_id && this.chats.get(update.chat_id);
    if (chat && update.unread_count !== undefined) chat.unread_count = update.unread_count as number;
    broadcast({
      event: 'chatReadInbox',
      chat_id: update.chat_id,
      last_read_inbox_message_id: update.last_read_inbox_message_id,
      unread_count: update.unread_count,
    });
  }

  handleChatTitle(update: TdUpdate) {
    const broadcast = this.getBroadcast();
    if (typeof broadcast !== 'function') return;
    const chat = update.chat_id && this.chats.get(update.chat_id);
    if (chat) chat.title = update.title as string;
    broadcast({
      event: 'chatTitle',
      chat_id: update.chat_id,
      title: update.title,
    });
  }

  handleChatPermissions(update: TdUpdate) {
    const broadcast = this.getBroadcast();
    if (typeof broadcast !== 'function') return;
    const perms = (update as any).permissions as Record<string, unknown> | undefined;
    const chat = update.chat_id && this.chats.get(update.chat_id as number);
    if (chat && perms) chat.permissions = perms;
    broadcast({
      event: 'chatPermissions',
      chat_id: update.chat_id,
      default_restricted: perms?.can_send_basic_messages === false,
      can_send_messages: perms?.can_send_basic_messages !== false,
    });
  }

  handleMessageIsPinned(update: TdUpdate) {
    const broadcast = this.getBroadcast();
    if (typeof broadcast !== 'function') return;
    const chatId = update.chat_id as number;
    const messageId = update.message_id as number;
    const isPinned = update.is_pinned as boolean;
    if (chatId && messageId) {
      if (isPinned) {
        if (!this.pinnedMessageIds.has(chatId) && this.pinnedMessageIds.size >= 200) {
          const first = this.pinnedMessageIds.keys().next().value;
          if (first !== undefined) this.pinnedMessageIds.delete(first);
        }
        this.pinnedMessageIds.set(chatId, messageId);
      } else if (this.pinnedMessageIds.get(chatId) === messageId) {
        this.pinnedMessageIds.delete(chatId);
      }
    }
    broadcast({
      event: 'ChatPinnedMessage',
      chat_id: chatId,
      pinned_message_id: isPinned ? messageId : 0,
    });
  }

  handleConnectionState(update: TdUpdate) {
    const broadcast = this.getBroadcast();
    if (typeof broadcast !== 'function') return;
    const connState = update.state as { _: string } | undefined;
    if (!connState) return;
    broadcast({
      event: 'connectionState',
      state: connState._,
    });
  }

  handleAuthorizationState(update: TdUpdate) {
    const state = update.authorization_state as { _: string } | undefined;
    if (!state) return;
    if (state._ === 'authorizationStateClosed' || state._ === 'authorizationStateLoggingOut') {
      this.chats.clear();
      this.resolver._users.clear();
      this.pinnedMessageIds.clear();
    }
    const broadcast = this.getBroadcast();
    if (typeof broadcast !== 'function') return;
    broadcast({ event: 'authState', state: state._ });
  }

  handleUserUpdate(update: TdUpdate) {
    const broadcast = this.getBroadcast();
    if (typeof broadcast !== 'function') return;
    const user = update.user as { id: number; first_name?: string; last_name?: string } | undefined;
    if (!user) return;
    const name = [user.first_name, user.last_name].filter(Boolean).join(' ') || `user_${user.id}`;
    this.resolver.setUser(user.id, name);
    broadcast({
      event: 'userUpdate',
      user_id: user.id,
      name,
    });
  }

  handleUserStatusUpdate(update: TdUpdate) {
    const broadcast = this.getBroadcast();
    if (typeof broadcast !== 'function') return;
    const userId = update.user_id as number | undefined;
    const status = update.status as { _: string; was_online?: number; expires?: number } | undefined;
    if (!userId || !status) return;
    const isOnline = status._ === 'userStatusOnline';
    broadcast({
      event: 'userStatus',
      user_id: userId,
      status: status._,
      was_online: status.was_online || 0,
      expires: status.expires || 0,
      is_online: isOnline,
    });
  }

  handleGroupUpdate(update: TdUpdate) {
    const broadcast = this.getBroadcast();
    if (typeof broadcast !== 'function') return;
    const group = (update.supergroup || update.basic_group) as { status?: { _: string }; member_count?: number; is_active?: boolean } | undefined;
    if (!group) return;
    const groupId = (update.supergroup_id || update.basic_group_id) as number | undefined;
    if (!groupId) return;
    let chatId: number | undefined;
    for (const [id, chat] of this.chats) {
      if (chat.type.supergroup_id === groupId || chat.type.basic_group_id === groupId) {
        chatId = id;
        break;
      }
    }
    if (!chatId) return;
    const status = group.status?._ || '';
    if (status === 'chatMemberStatusLeft' || status === 'chatMemberStatusBanned') {
      broadcast({ event: 'chatGroupRemoved', chat_id: chatId });
    }
    if (group.member_count !== undefined) {
      broadcast({ event: 'chatGroupInfo', chat_id: chatId, description: '', member_count: group.member_count });
    }
  }

  handleGroupFullInfoUpdate(update: TdUpdate) {
    const broadcast = this.getBroadcast();
    if (typeof broadcast !== 'function') return;
    const info = (update.supergroup_full_info || update.basic_group_full_info) as { description?: string; member_count?: number } | undefined;
    if (!info) return;
    const groupId = (update.supergroup_id || update.basic_group_id) as number | undefined;
    if (!groupId) return;
    let chatId: number | undefined;
    for (const [id, chat] of this.chats) {
      if (chat.type.supergroup_id === groupId || chat.type.basic_group_id === groupId) {
        chatId = id;
        break;
      }
    }
    if (!chatId) return;
    broadcast({
      event: 'chatGroupInfo',
      chat_id: chatId,
      description: info.description || '',
      member_count: info.member_count || 0,
    });
  }

  handleChatPositionUpdate(update: TdUpdate) {
    const broadcast = this.getBroadcast();
    if (typeof broadcast !== 'function') return;
    const pos = update.position as { list?: { _: string }; order?: string; is_pinned?: boolean } | undefined;
    if (!pos) return;
    broadcast({
      event: 'chatPosition',
      chat_id: update.chat_id,
      order: pos.order,
      is_pinned: pos.is_pinned || false,
      list: pos.list?._,
    });
  }

  broadcastRaw(update: TdUpdate) {
    const broadcast = this.getBroadcast();
    if (typeof broadcast !== 'function') return;
    const event = update._.replace(/^update/, '');
    broadcast({ event, ...update });
  }

  handleChatUnreadMentionCount(update: TdUpdate) {
    const broadcast = this.getBroadcast();
    if (typeof broadcast !== 'function') return;
    broadcast({
      event: 'chatUnreadMentionCount',
      chat_id: update.chat_id,
      unread_mention_count: update.unread_mention_count,
    });
  }

  handleMessageInteractionInfo(update: TdUpdate) {
    const broadcast = this.getBroadcast();
    if (typeof broadcast !== 'function') return;
    const info = update.interaction_info as { view_count?: number; forward_count?: number; reactions?: any } | undefined;
    if (!info) return;
    const payload: Record<string, unknown> = {
      event: 'messageInteractionInfo',
      chat_id: update.chat_id,
      message_id: update.message_id,
    };
    if (info.view_count !== undefined) payload.view_count = info.view_count;
    if (info.forward_count !== undefined) payload.forward_count = info.forward_count;
    if (info.reactions?.reactions) {
      payload.reactions = info.reactions.reactions.map((r: any) => ({
        emoji: r.type?.emoji || '',
        count: r.total_count,
        is_chosen: r.is_chosen,
      }));
    }
    broadcast(payload);
  }

  handleMessageReadDate(update: TdUpdate) {
    const broadcast = this.getBroadcast();
    if (typeof broadcast !== 'function') return;
    broadcast({
      event: 'messageReadDate',
      chat_id: update.chat_id,
      message_id: update.message_id,
      read_date: update.read_date,
    });
  }

  handleMessageReactions(update: TdUpdate) {
    const broadcast = this.getBroadcast();
    if (typeof broadcast !== 'function') return;
    const rawReactions = update.reactions as { type: { _: string; emoji: string }; total_count: number; is_chosen: boolean }[] | undefined;
    if (!rawReactions) return;
    broadcast({
      event: 'messageReactions',
      chat_id: update.chat_id,
      message_id: update.message_id,
      reactions: rawReactions.map(r => ({
        emoji: r.type?.emoji || '',
        count: r.total_count,
        is_chosen: r.is_chosen,
      })),
    });
  }
}
