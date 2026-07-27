import type { RawTdMessage, FormattedMessage, SenderInfo, Reaction } from './types';
import type { Resolver } from './resolve';

interface Entity { offset: number; length: number; type: { _: string; url?: string; language?: string } }

function getEntities(src: { text?: string; entities?: unknown[] }): Entity[] {
  const raw = src.entities;
  if (!Array.isArray(raw)) return [];
  return raw.filter((e): e is Entity => {
    if (!e || typeof e !== 'object') return false;
    const ent = e as Record<string, unknown>;
    return typeof ent.offset === 'number' && typeof ent.length === 'number' && ent.type && typeof ent.type === 'object';
  });
}

export function extractText(content: { _: string; text?: { text: string }; caption?: { text: string }; [key: string]: unknown } | null | undefined): string {
  if (!content) return '';
  const src = content._ === 'messageText' ? content.text : content.caption;
  if (!src) return '';
  const plain = src.text ?? '';

  const entities = getEntities(src as { text?: string; entities?: unknown[] });
  if (entities.length === 0) return plain;

  const markup: { offset: number; length: number; before: string; after: string }[] = [];
  for (const e of entities) {
    let before = '', after = '';
    switch (e.type._) {
      case 'textEntityTypeBold':        before = '**'; after = '**'; break;
      case 'textEntityTypeItalic':      before = '*'; after = '*'; break;
      case 'textEntityTypeCode':        before = '`'; after = '`'; break;
      case 'textEntityTypePre':
      case 'textEntityTypePreCode':     before = '```' + (e.type.language || '') + '\n'; after = '\n```'; break;
      case 'textEntityTypeStrikethrough': before = '~~'; after = '~~'; break;
      case 'textEntityTypeSpoiler': before = '||'; after = '||'; break;
      case 'textEntityTypeTextUrl':     before = '['; after = '](' + (e.type.url || '') + ')'; break;
      default: continue;
    }
    markup.push({ offset: e.offset, length: e.length, before, after });
  }
  if (markup.length === 0) return plain;

  markup.sort((a, b) => b.offset - a.offset);
  let text = plain;
  for (const m of markup) {
    text = text.slice(0, m.offset) + m.before + text.slice(m.offset);
    text = text.slice(0, m.offset + m.before.length + m.length) + m.after + text.slice(m.offset + m.before.length + m.length);
  }
  return text;
}

export class MessageFormatter {
  private _adminTitles = new Map<number, Map<number, string>>();

  constructor(private resolver: Resolver, private invoke: (q: unknown) => Promise<unknown>) {}

  async preloadAdminTitles(chatId: number) {
    if (this._adminTitles.has(chatId)) return;
    try {
      const result = await this.invoke({
        _: 'getChatAdministrators',
        chat_id: chatId,
      }) as { administrators?: { user_id: number; custom_title: string }[] };
      const titles = new Map<number, string>();
      for (const a of result.administrators || []) {
        titles.set(a.user_id, a.custom_title || 'Administrator');
      }
      this._adminTitles.set(chatId, titles);
    } catch {}
  }

  async format(msg: RawTdMessage | null, senderCache?: Map<string, SenderInfo>, chatId?: number): Promise<FormattedMessage | null> {
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
    if (sender && chatId) {
      const titles = this._adminTitles.get(chatId);
      if (titles && sender.id) {
        const uid = typeof sender.id === 'number' ? sender.id : Number(sender.id);
        const ct = titles.get(uid);
        if (ct) sender.custom_title = ct;
      }
    }

    const formatted: FormattedMessage = {
      id: msg.id,
      type: msg.content ? msg.content._ : 'unknown',
      text: extractText(msg.content),
      sender: sender ?? null,
      date: msg.date,
      own: msg.is_outgoing || false,
      containsMention: msg.contains_mention || false,
    };

    if (msg.content?._ === 'messageAnimatedEmoji') {
      const emoji = (msg.content as any).emoji as string | undefined;
      if (emoji) formatted.text = emoji;
    }

    // Enhanced display for special message types that lack text/caption content
    if (!formatted.text && msg.content) {
      const c = msg.content as Record<string, unknown>;
      switch (c._) {
        case 'messageCall': {
          const call = msg.content as any;
          const dur = call.duration || 0;                // duration:int32
          const reason = call.discard_reason?._ || '';    // discard_reason:CallDiscardReason
          const isVideo = call.is_video || false;          // is_video:Bool
          const type = isVideo ? 'Video call' : 'Call';
          if (dur > 0) {
            const m = Math.floor(dur / 60);
            const s = dur % 60;
            formatted.text = `${type} (${m > 0 ? `${m}m ` : ''}${s}s)`;
          } else if (reason === 'callDiscardReasonMissed') {
            formatted.text = `Missed ${type.toLowerCase()}`;
          } else if (reason === 'callDiscardReasonDeclined') {
            formatted.text = `Declined ${type.toLowerCase()}`;
          } else if (reason === 'callDiscardReasonBusy') {
            formatted.text = 'Busy';
          } else {
            formatted.text = type;
          }
          break;
        }
        case 'messageInvoice': {
          const inv = msg.content as any;
          const amt = ((inv.total_amount || 0) / 100).toFixed(2);  // total_amount:int53
          const curr = inv.currency || '';                          // currency:string
          const pi = inv.product_info;                               // product_info:productInfo
          const title = pi?.title || '';
          const display = title ? `🧾 ${title}` : '🧾 Invoice';
          formatted.text = amt ? `${display}\n💰 ${amt} ${curr}` : display;
          break;
        }
        case 'messageGiveaway':
        case 'messagePremiumGiveaway': {
          const gw = msg.content as any;
          const winners = gw.winner_count || 0;  // winner_count:int32 (top-level)
          const line = `🎉 ${winners} winner${winners !== 1 ? 's' : ''}`;
          formatted.text = gw.prize?.months ? `${line}\n🎁 ${gw.prize.months}mo Premium` : line;
          break;
        }
        case 'messageContact': {
          const mc = msg.content as any;
          const ct = mc.contact as any;  // contact:contact
          const name = ct ? [ct.first_name, ct.last_name].filter(Boolean).join(' ') : '';
          const phone = ct?.phone_number || '';
          const display = name || phone || 'Unknown';
          formatted.text = `👤 ${display}`;
          if (phone) formatted.text += `\n📞 ${phone}`;
          break;
        }
        case 'messageDice': {
          const dice = msg.content as any;
          formatted.text = `${dice.emoji || '🎲'} ${dice.value || 0}`;
          break;
        }
        case 'messageLocation': {
          const loc = msg.content as any;
          const lat = loc.location?.latitude?.toFixed(4) || '?';
          const lng = loc.location?.longitude?.toFixed(4) || '?';
          formatted.text = `📍 ${lat}, ${lng}`;
          formatted.text += `\n🗺️ https://www.openstreetmap.org/?mlat=${lat}&mlon=${lng}`;
          break;
        }
        case 'messagePoll': {
          const poll = msg.content as any;
          const pollData = poll.poll as any;
          const q = pollData?.question;
          const qText = typeof q === 'string' ? q : (q?.text || '');
          formatted.text = `[Poll] ${qText}`;
          if (pollData) {
            formatted.pollInfo = {
              question: qText,
              options: (pollData.options || []).map((o: any) => ({
                id: o.id,
                text: o.text?.text || '',
                voterCount: o.voter_count || 0,
                votePercentage: o.vote_percentage || 0,
                isChosen: o.is_chosen || false,
              })),
              totalVoterCount: pollData.total_voter_count || 0,
              isAnonymous: !!pollData.is_anonymous,
              allowsMultipleAnswers: !!pollData.allows_multiple_answers,
              isClosed: !!pollData.is_closed,
              canGetVoters: !!pollData.can_get_voters,
            };
          }
          break;
        }
        case 'messageGame': {
          const game = msg.content as any;
          const gTitle = game.game?.title || '';  // game:game → title:string
          formatted.text = gTitle ? `🎮 ${gTitle}` : '🎮 Game';
          break;
        }
        case 'messageVenue': {
          const v = msg.content as any;
          const venue = v.venue as any;
          const title = venue?.title || 'Venue';
          const addr = venue?.address || '';
          formatted.text = `📍 ${title}`;
          if (addr) formatted.text += `, ${addr}`;
          if (venue?.location) {
            const lat = venue.location.latitude?.toFixed(4) || '';
            const lng = venue.location.longitude?.toFixed(4) || '';
            if (lat && lng) formatted.text += `\n🗺️ https://www.openstreetmap.org/?mlat=${lat}&mlon=${lng}`;
          }
          break;
        }
        case 'messageLiveLocation': {
          const ll = msg.content as any;
          const loc = ll.location?.location as any;
          const exp = ll.expires_in || 0;
          const lat = loc?.latitude?.toFixed(4) || '?';
          const lng = loc?.longitude?.toFixed(4) || '?';
          formatted.text = `📍 Live: ${lat}, ${lng}`;
          if (exp > 0) formatted.text += `\n⏱️ ${exp}s remaining`;
          formatted.text += `\n🗺️ https://www.openstreetmap.org/?mlat=${lat}&mlon=${lng}`;
          break;
        }
        case 'messageStory': {
          const s = msg.content as any;
          formatted.text = `📱 Story${s.via_mention ? ' (via mention)' : ''}`;
          break;
        }
        case 'messageChatBoost': {
          const boost = msg.content as any;
          formatted.text = `🔋 Chat boosted ×${boost.boost_count || 1}`;
          break;
        }
        case 'messageGameScore': {
          const gs = msg.content as any;
          formatted.text = `🎮 Score: +${gs.score || 0}`;
          break;
        }
        case 'messageProximityAlertTriggered': {
          const pa = msg.content as any;
          const dist = pa.distance || 0;
          const distStr = dist >= 1000 ? `${(dist/1000).toFixed(1)}km` : `${dist}m`;
          formatted.text = `📍 Proximity alert — ${distStr}`;
          break;
        }
        case 'messagePaymentSuccessful': {
          const ps = msg.content as any;
          const amt = ((ps.total_amount || 0) / 100).toFixed(2);
          formatted.text = `✅ Payment: ${amt} ${ps.currency || ''}`.trim();
          if (ps.invoice_name) formatted.text += `\n🧾 ${ps.invoice_name}`;
          break;
        }
        case 'messageScreenshotTaken': {
          formatted.text = '📸 Screenshot taken';
          break;
        }
        case 'messageVideoChatScheduled': {
          const vcs = msg.content as any;
          const start = vcs.start_date || 0;
          const dateStr = start > 0 ? new Date(start * 1000).toLocaleString() : 'soon';
          formatted.text = `📅 Video chat scheduled\n🕐 ${dateStr}`;
          break;
        }
        case 'messageVideoChatStarted': {
          formatted.text = '🔊 Video chat started';
          break;
        }
        case 'messageVideoChatEnded': {
          const vce = msg.content as any;
          const dur = vce.duration || 0;
          const m = Math.floor(dur / 60);
          const s = dur % 60;
          formatted.text = `🔇 Video chat ended${dur > 0 ? ` (${m > 0 ? `${m}m ` : ''}${s}s)` : ''}`;
          break;
        }
        case 'messageForumTopicEdited': {
          const fte = msg.content as any;
          formatted.text = fte.name ? `📌 Topic renamed: ${fte.name}` : '📌 Topic updated';
          break;
        }
        case 'messageChatShared': {
          const cs = msg.content as any;
          const chat = cs.chat as any;
          const chatId = chat?.chat_id;
          const chatTitle = chat?.title || '?';
          formatted.text = `💬 Chat shared: ${chatTitle}`;
          if (chatId) formatted.sharedInfo = { chatId, chatTitle };
          break;
        }
        case 'messageUsersShared': {
          const us = msg.content as any;
          const users = us.users as any[] || [];
          const names = users.map((u: any) => [u.first_name, u.last_name].filter(Boolean).join(' ') || `user_${u.user_id}`);
          const ids = users.map((u: any) => u.user_id).filter(Boolean);
          formatted.text = `👥 Users shared: ${names.join(', ') || '?'}`;
          if (ids.length > 0) formatted.sharedInfo = { userIds: ids, userNames: names };
          break;
        }
      }
    }

    // Gift types — these have text:formattedText, so extractText already set formatted.text
    // Override with structured display that includes gifter info
    if (msg.content?._ === 'messageGiftedPremium') {
      const gp = msg.content as any;
      const gifterId = gp.gifter_user_id;
      const gifterName = gifterId ? await this.resolver.getUserName(gifterId) : 'Someone';
      const months = gp.month_count || gp.day_count || 0;
      const unit = gp.month_count ? 'mo' : 'day';
      formatted.text = `⭐ ${gifterName} gifted Premium (${months} ${unit})`;
    } else if (msg.content?._ === 'messageGiftedStars') {
      const gs = msg.content as any;
      const gifterId2 = gs.gifter_user_id;
      const gifterName2 = gifterId2 ? await this.resolver.getUserName(gifterId2) : 'Someone';
      formatted.text = `⭐ ${gifterName2} gifted ${gs.star_count || 0} Stars`;
    } else if (msg.content?._ === 'messagePremiumGiftCode') {
      const pgc = msg.content as any;
      const months2 = pgc.month_count || 0;
      formatted.text = `🎁 Gift code: ${months2}mo Premium${pgc.is_unclaimed ? ' (unclaimed)' : ''}`;
    } else if (msg.content?._ === 'messageGift') {
      const gift = msg.content as any;
      const g = gift.gift as any;
      const senderId = gift.sender_id?.user_id;
      const senderName = senderId ? await this.resolver.getUserName(senderId) : 'Someone';
      const giftName = g?.type || 'a gift';
      formatted.text = `🎁 ${senderName} sent ${giftName}`;
    }

    if (msg.content?._ === 'messageChatAddMembers' && msg.content.member_user_ids) {
      formatted.memberUserIds = msg.content.member_user_ids;
      formatted.addedMemberNames = await Promise.all(
        msg.content.member_user_ids.map((id: number) => this.resolver.getUserName(id))
      );
    }

    const viewCount = msg.views || msg.interaction_info?.view_count || 0;
    if (viewCount > 0) formatted.views = viewCount;
    if (msg.interaction_info?.forward_count) formatted.forwardCount = msg.interaction_info.forward_count;

    if (msg.is_outgoing && msg.chat_id) {
      this.invoke({
        _: 'getMessageReadDate',
        chat_id: msg.chat_id,
        message_id: msg.id,
      }).then((readResult: any) => {
        if (readResult?._ === 'messageReadDateResultReadDate' && readResult.read_date) {
          formatted.readDate = readResult.read_date;
        }
      }).catch(() => {});
    }

    if (msg.edit_date) formatted.editDate = msg.edit_date;

    if (msg.content?._ === 'messageText') {
      const content = msg.content as any;
      const lp = content.link_preview as { url?: string; title?: string; description?: string; site_name?: string } | undefined;
      if (lp?.url) {
        formatted.linkPreview = {
          url: lp.url,
          title: lp.title,
          description: lp.description,
          siteName: lp.site_name,
        };
      }
    }

    if (msg.forward_info?.origin) {
      const origin = msg.forward_info.origin;
      let name = '';
      if (origin._ === 'messageOriginUser') {
        const uid = (origin as any).sender_user_id as number | undefined;
        if (uid) name = this.resolver._users.get(uid) || await this.resolver.getUserName(uid);
      } else if (origin._ === 'messageOriginChat' || origin._ === 'messageOriginChannel') {
        name = (origin as any).sender_name || (origin as any).author_signature || '';
      } else if (origin._ === 'messageOriginHiddenUser') {
        name = (origin as any).sender_name || 'Hidden';
      }
      if (name) formatted.forwardInfo = { type: origin._, name };
    }

    if (msg.interaction_info?.reactions?.reactions?.length) {
      formatted.reactions = msg.interaction_info.reactions.reactions.map((r) => ({
        emoji: r.type.emoji,
        count: r.total_count,
        is_chosen: r.is_chosen,
      }));
    }

    const replyTo = await this._formatReplyTo(msg);
    if (replyTo) formatted.replyTo = replyTo;

    const fileInfo = this._extractFileInfo(msg.content);
    if (fileInfo) {
      formatted.filePath = fileInfo.path;
      if (fileInfo.mediaPath) formatted.mediaPath = fileInfo.mediaPath;
      formatted.mimeType = fileInfo.mimeType;
    }
    if (msg.content && msg.content._ && msg.content._ !== 'messageText') {
      this.invoke({ _: 'openMessageContent', chat_id: msg.chat_id, message_id: msg.id }).catch(() => {});
      if (fileInfo && fileInfo.fileId > 0) {
        this.invoke({ _: 'downloadFile', file_id: fileInfo.fileId, priority: 1 }).catch(() => {});
        if (fileInfo.priorityFileId && fileInfo.priorityFileId !== fileInfo.fileId) {
          this.invoke({ _: 'downloadFile', file_id: fileInfo.priorityFileId, priority: 2 }).catch(() => {});
        }
      }
    }

    return formatted;
  }

  private _extractFileInfo(content: Record<string, unknown> | null | undefined): { path: string; mediaPath?: string; mimeType: string; fileId: number; priorityFileId?: number } | null {
    if (!content) return null;
    const t = content._ as string;
    if (t === 'messageText') return null;

    const getFileInfo = (file: Record<string, unknown> | undefined, mimeType = ''): { path: string; mimeType: string; fileId: number } | null => {
      if (!file) return null;
      const local = file['local'] as Record<string, unknown> | undefined;
      const rawId = file['id'];
      return {
        path: (local?.['path'] as string) || '',
        mimeType,
        fileId: (typeof rawId === 'number' ? rawId : Number(rawId)) || 0,
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
      messageSticker:    { key: 'sticker',    fileField: 'sticker',  mimeField: '' },
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
        const lastFile = (lastSize[cfg.fileField] || lastSize['sizes']) as Record<string, unknown> | Record<string, unknown>[] | undefined;
        if (lastFile) {
          const file = Array.isArray(lastFile) ? (lastFile as Record<string, unknown>[])[0] : lastFile;
          const rawId = file?.['id'];
          lastId = (typeof rawId === 'number' ? rawId : Number(rawId)) || 0;
        }

        for (let i = 0; i < sizes.length; i++) {
          const src = (sizes[i][cfg.fileField] || sizes[i]['sizes']) as Record<string, unknown> | Record<string, unknown>[] | undefined;
          if (!src) continue;
          const photoFile = Array.isArray(src) ? (src as Record<string, unknown>[])[0] : src;
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
    const mainInfo = file ? getFileInfo(file, mimeType) : null;

    const thumb = media['thumbnail'] as Record<string, unknown> | undefined;
    const thumbInfo = thumb ? getFileInfo(thumb['file'] as Record<string, unknown> | undefined, 'image/jpeg') : null;

    // For non-photo media: filePath = thumbnail (for inline display), mediaPath = original file
    if (t !== 'messagePhoto') {
      if (thumbInfo || mainInfo) {
        const result: any = { path: thumbInfo?.path || '', mimeType: 'image/jpeg', fileId: thumbInfo?.fileId || 0 };
        if (mainInfo?.path) result.mediaPath = mainInfo.path;
        if (thumbInfo?.fileId) result.priorityFileId = mainInfo?.fileId || 0;
        return result;
      }
      return null;
    }

    if (mainInfo && mainInfo.path) return mainInfo;
    if (mainInfo && mainInfo.fileId > 0) return mainInfo;
    if (thumbInfo) return thumbInfo;

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
    } catch (e) { console.warn('_formatReplyTo getMessage failed:', (e as Error).message); }
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
