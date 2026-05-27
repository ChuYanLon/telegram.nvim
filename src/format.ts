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

    const fileInfo = this._extractFileInfo(msg.content);
    if (fileInfo) {
      formatted.filePath = fileInfo.path;
      formatted.mimeType = fileInfo.mimeType;
      if (fileInfo.fileId > 0) {
        this.invoke({ _: 'downloadFile', file_id: fileInfo.fileId, priority: 1 }).catch(() => {});
      }
    }

    return formatted;
  }

  private _extractFileInfo(content: Record<string, unknown> | null | undefined): { path: string; mimeType: string; fileId: number } | null {
    if (!content) return null;
    const t = content._ as string;
    if (t === 'messageText') return null;

    const getFileInfo = (file: Record<string, unknown> | undefined, mimeType = ''): { path: string; mimeType: string; fileId: number } | null => {
      if (!file) return null;
      const local = file['local'] as Record<string, unknown> | undefined;
      return {
        path: (local?.['path'] as string) || '',
        mimeType,
        fileId: (file['id'] as number) || 0,
      };
    };

    const mediaMap: Record<string, { key: string; fileField: string; mimeField: string }> = {
      messagePhoto:      { key: 'photo',      fileField: 'photo',    mimeField: '' },
      messageVideo:      { key: 'video',      fileField: 'video',    mimeField: 'mime_type' },
      messageDocument:   { key: 'document',   fileField: 'document', mimeField: 'mime_type' },
      messageAnimation:  { key: 'animation',  fileField: 'animation', mimeField: 'mime_type' },
      messageVoiceNote:  { key: 'voice_note', fileField: 'voice',    mimeField: 'mime_type' },
      messageVideoNote:  { key: 'video_note', fileField: 'video',    mimeField: 'mime_type' },
      messageAudio:      { key: 'audio',      fileField: 'audio',    mimeField: 'mime_type' },
    };

    const cfg = mediaMap[t];
    if (!cfg) return null;

    const media = content[cfg.key] as Record<string, unknown> | undefined;
    if (!media) return null;

    const mimeType = cfg.mimeField ? (media[cfg.mimeField] as string) || '' : '';

    if (t === 'messagePhoto') {
      const sizes = media['sizes'] as Record<string, unknown>[] | undefined;
      if (sizes && sizes.length > 0) {
        for (let i = sizes.length - 1; i >= 0; i--) {
          const photoFile = sizes[i][cfg.fileField] as Record<string, unknown> | undefined;
          const info = getFileInfo(photoFile, 'image/jpeg');
          if (info && info.path) return info;
        }
      }
      return null;
    }

    const file = media[cfg.fileField] as Record<string, unknown> | undefined;
    return getFileInfo(file, mimeType);
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
