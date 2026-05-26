import type { RawTdMessage, FormattedMessage, SenderInfo } from './types';
import type { Resolver } from './resolve';

export function extractText(content: { _: string; text?: { text: string }; caption?: { text: string }; [key: string]: unknown } | null | undefined): string {
  if (!content) return '';
  if (content._ === 'messageText') return content.text!.text;
  if (content.caption?.text) return content.caption.text;
  return '';
}

export class MessageFormatter {
  constructor(private resolver: Resolver, private invoke: (q: unknown) => Promise<unknown>) {}

  async format(msg: RawTdMessage | null, senderCache?: Map<string, SenderInfo>): Promise<FormattedMessage | null> {
    if (!msg) return null;

    let sender: SenderInfo | undefined | null;
    if (senderCache && msg.sender_id) {
      const key = this._senderKey(msg.sender_id);
      sender = key ? senderCache.get(key) : undefined;
    } else {
      sender = undefined;
    }
    if (!sender) {
      sender = await this.resolver.resolveSender(msg.sender_id);
    }

    const formatted: FormattedMessage = {
      id: msg.id,
      type: msg.content ? msg.content._ : 'unknown',
      text: extractText(msg.content),
      sender: sender ?? null,
      date: msg.date,
      own: msg.is_outgoing || false,
    };

    if (msg.content?._ === 'messageChatAddMembers' && msg.content.member_user_ids) {
      formatted.memberUserIds = msg.content.member_user_ids;
      formatted.addedMemberNames = await Promise.all(
        msg.content.member_user_ids.map((id: number) => this.resolver.getUserName(id))
      );
    }

    const replyTo = await this._formatReplyTo(msg);
    if (replyTo) formatted.replyTo = replyTo;
    return formatted;
  }

  private async _formatReplyTo(msg: RawTdMessage): Promise<FormattedMessage['replyTo'] | null> {
    if (!msg.reply_to || msg.reply_to._ !== 'messageReplyToMessage') return null;
    const r = msg.reply_to;
    const replyTo: FormattedMessage['replyTo'] = { id: r.message_id };

    if (r.origin_sender_id) {
      replyTo.sender = await this.resolver.resolveSender(r.origin_sender_id);
    }
    if (!replyTo.sender && r.origin_sender_name) {
      replyTo.sender = { id: null, name: r.origin_sender_name };
    }

    const origChatId = r.chat_id || msg.chat_id;
    try {
      const orig = await this.invoke({ _: 'getMessage', chat_id: origChatId, message_id: r.message_id }) as RawTdMessage | null;
      if (orig) {
        replyTo.text = extractText(orig.content);
        if (!replyTo.sender) {
          replyTo.sender = await this.resolver.resolveSender(orig.sender_id);
        }
      }
    } catch { /* ignore */ }
    if (r.chat_id && r.chat_id !== msg.chat_id) {
      replyTo.chat_id = r.chat_id;
    }
    return replyTo;
  }

  private _senderKey(senderId: { _: string; user_id?: number; chat_id?: number } | null): string | null {
    if (!senderId) return null;
    if (senderId._ === 'messageSenderUser') return `u:${senderId.user_id}`;
    if (senderId._ === 'messageSenderChat') return `c:${senderId.chat_id}`;
    return null;
  }

  preloadSenders(messages: RawTdMessage[]): Promise<Map<string, SenderInfo>> {
    return this.resolver.preloadSenders(messages, this._senderKey.bind(this));
  }
}
