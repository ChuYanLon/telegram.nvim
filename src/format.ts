import type { RawTdMessage, FormattedMessage, SenderInfo } from './types';
import type { Resolver } from './resolve';

export function extractText(content: { _: string; text?: { text: string }; caption?: { text: string }; [key: string]: unknown } | null | undefined): string {
  if (!content) return '';
  if (content._ === 'messageText') return content.text!.text;
  if (content.caption?.text) return content.caption.text;
  return '';
}

export class MessageFormatter {
  fileMap: Map<number, Set<number>> = new Map();
  _pendingMessages: Map<number, RawTdMessage> = new Map();

  constructor(private resolver: Resolver, private invoke: (q: unknown) => Promise<unknown>) {}

  async format(msg: RawTdMessage | null, senderCache?: Map<string, SenderInfo>): Promise<FormattedMessage | null> {
    if (!msg) return null;

    this._pendingMessages.set(msg.id, msg);

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
        if (!this.fileMap.has(fileInfo.fileId)) {
          this.fileMap.set(fileInfo.fileId, new Set());
        }
        this.fileMap.get(fileInfo.fileId)!.add(msg.id);
        this.invoke({ _: 'downloadFile', file_id: fileInfo.fileId, priority: 1 }).catch(() => {});
      }
      if (fileInfo.priorityFileId && fileInfo.priorityFileId !== fileInfo.fileId) {
        if (!this.fileMap.has(fileInfo.priorityFileId)) {
          this.fileMap.set(fileInfo.priorityFileId, new Set());
        }
        this.fileMap.get(fileInfo.priorityFileId)!.add(msg.id);
        this.invoke({ _: 'downloadFile', file_id: fileInfo.priorityFileId, priority: 2 }).catch(() => {});
      }
    } else if (msg.content && msg.content._ && msg.content._ !== 'messageText') {
      this.invoke({ _: 'openMessageContent', chat_id: msg.chat_id, message_id: msg.id }).catch(() => {});
    }

    return formatted;
  }

  async _scheduleHighResDownload(messageId: number) {
    const msgs = this._pendingMessages;
    if (!msgs) return;
    const msg = msgs.get(messageId);
    if (!msg) return;
    const fresh = await this.invoke({ _: 'getMessage', chat_id: msg.chat_id, message_id: msg.id }).catch(() => null) as RawTdMessage | null;
    if (!fresh) return;
    msgs.set(messageId, fresh);
    const info = this._extractFileInfo(fresh.content);
    if (!info || !info.priorityFileId) return;
    const prevFileId = info.fileId;
    const targetFileId = info.priorityFileId;
    if (targetFileId > 0 && targetFileId !== prevFileId) {
      if (!this.fileMap.has(targetFileId)) {
        this.fileMap.set(targetFileId, new Set());
      }
      this.fileMap.get(targetFileId)!.add(messageId);
      this.invoke({ _: 'downloadFile', file_id: targetFileId, priority: 2 }).catch(() => {});
    }
  }

  private _extractFileInfo(content: Record<string, unknown> | null | undefined): { path: string; mimeType: string; fileId: number; priorityFileId?: number } | null {
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
      let firstId = 0;
      let lastId = 0;
      const sizes = media['sizes'] as Record<string, unknown>[] | undefined;
      if (sizes && sizes.length > 0) {
        const lastSize = sizes[sizes.length - 1];
        const lastFile = lastSize[cfg.fileField] as Record<string, unknown> | undefined;
        if (lastFile) lastId = (lastFile['id'] as number) || 0;

        for (let i = 0; i < sizes.length; i++) {
          const photoFile = sizes[i][cfg.fileField] as Record<string, unknown> | undefined;
          const info = getFileInfo(photoFile, 'image/jpeg');
          if (info) {
            if (firstId === 0) firstId = info.fileId;
            if (info.path) return { path: info.path, mimeType: info.mimeType, fileId: info.fileId, priorityFileId: lastId };
          }
        }
      }
      if (firstId > 0) return { path: '', mimeType: 'image/jpeg', fileId: firstId, priorityFileId: lastId };
      return null;
    }

    const file = media[cfg.fileField] as Record<string, unknown> | undefined;
    if (file) {
      const info = getFileInfo(file, mimeType);
      if (info && info.path) return info;
      if (info && info.fileId > 0) return info;
    }

    const thumb = media['thumbnail'] as Record<string, unknown> | undefined;
    if (thumb) {
      const thumbFile = thumb['file'] as Record<string, unknown> | undefined;
      const info = getFileInfo(thumbFile, 'image/jpeg');
      if (info) return info;
    }

    return null;
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
