export interface SenderInfo {
  id: number | string | null;
  name: string;
  custom_title?: string;
}

export interface Reaction {
  emoji: string;
  count: number;
  is_chosen: boolean;
}

export interface FormattedMessage {
  id: number;
  type: string;
  text: string;
  sender: SenderInfo | null;
  date: number;
  own: boolean;
  containsMention: boolean;
  replyTo?: {
    id: number;
    sender?: SenderInfo | null;
    text?: string;
    chat_id?: number;
  };
  memberUserIds?: number[];
  addedMemberNames?: string[];
  filePath?: string;
  mediaPath?: string;
  mimeType?: string;
  views?: number;
  forwardCount?: number;
  readDate?: number;
  editDate?: number;
  reactions?: Reaction[];
}

export interface RawTdMessage {
  id: number;
  chat_id: number;
  content: {
    _: string;
    text?: { text: string };
    caption?: { text: string };
    member_user_ids?: number[];
    [key: string]: unknown;
  };
  sender_id: { _: string; user_id?: number; chat_id?: number } | null;
  date: number;
  is_outgoing: boolean;
  contains_mention?: boolean;
  reply_to: {
    _: string;
    message_id: number;
    origin_sender_id?: { _: string; user_id?: number; chat_id?: number };
    origin_sender_name?: string;
    chat_id?: number;
  } | null;
  views?: number;
  edit_date?: number;
  interaction_info?: {
    _: string;
    view_count?: number;
    forward_count?: number;
    reactions?: {
      _: string;
      reactions: {
        _: string;
        type: { _: string; emoji: string };
        total_count: number;
        is_chosen: boolean;
        recent_sender_ids?: { _: string; user_id?: number; chat_id?: number }[];
      }[];
      are_tags?: boolean;
    };
    [key: string]: unknown;
  };
}

export interface RawTdChat {
  id: number;
  title: string;
  type: {
    _: string;
    supergroup_id?: number;
    basic_group_id?: number;
    is_channel?: boolean;
    user_id?: number;
  };
  unread_count?: number;
  unread_mention_count?: number;
  last_read_inbox_message_id?: number;
  online_member_count?: number;
  last_message?: RawTdMessage | null;
  positions?: { list: { _: string }; order: string }[];
  permissions?: Record<string, unknown>;
}

export interface GroupInfo {
  id: number;
  title: string;
  unreadCount: number;
  unreadMentionCount: number;
  onlineMemberCount: number;
  lastMessage?: FormattedMessage | null;
  memberCount?: number;
  owner?: SenderInfo | null;
  description?: string;
}

export interface ChatInfo {
  id: number;
  title: string;
  type: 'group' | 'private' | 'channel';
  unreadCount: number;
  unreadMentionCount: number;
  onlineMemberCount: number;
  lastMessage?: FormattedMessage | null;
  memberCount?: number;
  owner?: SenderInfo | null;
  description?: string;
  userId?: number;
  isSaved?: boolean;
}

export interface AuthState {
  state: string;
  hint: string | null;
  error: string | null;
  canInput: boolean;
}

export interface TdUpdate {
  _: string;
  chat_id?: number;
  user_id?: number;
  member?: { user_id: number };
  actor_user_id?: number;
  old_status?: { _: string };
  new_status?: { _: string };
  action?: { _: string };
  sender_id?: { _: string; user_id?: number; chat_id?: number };
  online_member_count?: number;
  message?: RawTdMessage;
  chat?: RawTdChat;
  [key: string]: unknown;
}

export type BroadcastFn = (data: unknown) => void;

declare global {
  var broadcast: BroadcastFn | undefined;
}
