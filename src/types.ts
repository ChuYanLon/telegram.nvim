export interface SenderInfo {
  id: number | string | null;
  name: string;
}

export interface FormattedMessage {
  id: number;
  type: string;
  text: string;
  sender: SenderInfo | null;
  date: number;
  own: boolean;
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
  reply_to: {
    _: string;
    message_id: number;
    origin_sender_id?: { _: string; user_id?: number; chat_id?: number };
    origin_sender_name?: string;
    chat_id?: number;
  } | null;
  views?: number;
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
  online_member_count?: number;
  last_message?: RawTdMessage | null;
  pinned_message_id?: number;
  positions?: { list: { _: string }; order: string }[];
  permissions?: Record<string, unknown>;
}

export interface GroupInfo {
  id: number;
  title: string;
  unreadCount: number;
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
  onlineMemberCount: number;
  lastMessage?: FormattedMessage | null;
  memberCount?: number;
  owner?: SenderInfo | null;
  description?: string;
  userId?: number;
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
