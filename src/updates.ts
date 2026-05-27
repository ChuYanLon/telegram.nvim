import type { TdUpdate, RawTdMessage, RawTdChat, BroadcastFn } from './types';
import type { MessageFormatter } from './format';
import type { Resolver } from './resolve';

export class UpdateDispatcher {
  constructor(
    private formatter: MessageFormatter,
    private resolver: Resolver,
    private chats: Map<number, RawTdChat>,
    private getBroadcast: () => BroadcastFn | undefined,
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
        case 'updateChatMember':
          await this.handleChatMemberUpdate(update);
          break;
        default:
          console.log(update);
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

  async handleChatMemberUpdate(update: TdUpdate) {
    const broadcast = this.getBroadcast();
    if (typeof broadcast !== 'function') return;
    const chat = this.chats.get(update.chat_id!);
    const memberUserId = update.member!.user_id;
    const actorUserId = update.actor_user_id!;
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
}
