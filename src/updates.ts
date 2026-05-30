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
  ) {}

  listen(tdClient: { on: (event: string, handler: (update: TdUpdate) => void) => void }) {
    tdClient.on('update', async (update: TdUpdate) => {
      switch (update._) {
        case 'updateNewChat':
          this.chats.set((update.chat as RawTdChat).id, update.chat as RawTdChat);
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
        default:
          this.broadcastRaw(update);
      }
    });
  }

  async handleNewMessage(msg: RawTdMessage) {
    const broadcast = this.getBroadcast();
    if (typeof broadcast !== 'function') return;
    const chat = this.chats.get(msg.chat_id);
    const formatted = await this.formatter.format(msg);
    broadcast({
      event: 'newMessage',
      chat: { id: msg.chat_id, title: chat ? chat.title : 'Unknown group' },
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
      user_id: sender ? sender.id : null,
      user_name: sender ? sender.name : 'unknown',
      action: update.action,
    });
  }

  handleChatOnlineMemberCount(update: TdUpdate) {
    const broadcast = this.getBroadcast();
    if (typeof broadcast !== 'function') return;
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

  async handleChatMemberUpdate(update: TdUpdate) {
    const broadcast = this.getBroadcast();
    if (typeof broadcast !== 'function') return;
    const chat = this.chats.get(update.chat_id!);
    if (!chat) return;
    if (!update.member || update.actor_user_id == null) return;
    const memberUserId = update.member.user_id;
    const actorUserId = update.actor_user_id;
    const memberName = await this.resolver.getUserName(memberUserId);
    const actorName = actorUserId === memberUserId
      ? memberName
      : await this.resolver.getUserName(actorUserId);
    broadcast({
      event: 'chatMember',
      chat_id: update.chat_id,
      chat_title: chat ? chat.title : 'Unknown',
      member: { id: memberUserId, name: memberName },
      actor: { id: actorUserId, name: actorName },
      old_status: update.old_status,
      new_status: update.new_status,
    });
  }

  async handleMessageContentUpdate(update: TdUpdate) {
    const broadcast = this.getBroadcast();
    if (typeof broadcast !== 'function') return;
    const chatId = update.chat_id!;
    const messageId = update.message_id as number;
    if (!chatId || !messageId) return;
    const newContent = update.new_content as { _: string; text?: { text: string }; caption?: { text: string } } | undefined;
    if (!newContent) return;
    const chat = this.chats.get(chatId);
    broadcast({
      event: 'messageContentUpdated',
      chat_id: chatId,
      message_id: messageId,
      chat_title: chat ? chat.title : 'Unknown',
      text: extractText(newContent),
      type: newContent._,
    });
  }

  async handleDeleteMessages(update: TdUpdate) {
    const broadcast = this.getBroadcast();
    if (typeof broadcast !== 'function') return;
    const chatId = update.chat_id!;
    const messageIds = update.message_ids as number[];
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
    const chatId = update.chat_id!;
    if (!chatId) return;
    const rawMsg = update.last_message as RawTdMessage | null;
    const chat = this.chats.get(chatId);
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
    broadcast({
      event: 'chatPermissions',
      chat_id: update.chat_id,
      default_restricted: perms?.can_send_basic_messages === false,
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
}
