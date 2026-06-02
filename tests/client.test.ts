import { describe, it, expect, beforeAll, beforeEach, afterEach } from 'vitest';
import FakeTdClient from './fake-td-client';

let client;

beforeAll(async () => {
  process.env.TG_TDLIB_PATH = '/dev/null';
  const { default: TelegramLSPClient } = await import('../src/client');
  const fake = new FakeTdClient();
  fake.addUser({ id: 1, first_name: 'Alice', last_name: null });
  fake.addUser({ id: 2, first_name: 'Bob', last_name: 'Lee' });
  fake.addUser({ id: 3, first_name: 'Charlie', last_name: null });
  fake.addChat({ id: -1001, title: 'Test Group' });
  fake.addChat({ id: -1002, title: 'Private Chat', type: { _: 'chatTypePrivate' } });
  client = new TelegramLSPClient({ client: fake });
  // Pre-populate internal caches so resolveSender works
  client.resolver._users.set(1, 'Alice');
  client.resolver._users.set(2, 'Bob Lee');
  client.resolver._users.set(3, 'Charlie');
  client._chats.set(-1001, { id: -1001, title: 'Test Group' });
});

describe('_extractText', () => {
  it('returns empty string for null', () => {
    expect(client._extractText(null)).toBe('');
  });

  it('extracts text from messageText', () => {
    expect(client._extractText({ _: 'messageText', text: { text: 'hi' } })).toBe('hi');
  });

  it('returns empty string for non-text messages without caption', () => {
    expect(client._extractText({ _: 'messagePhoto' })).toBe('');
  });

  it('extracts caption from media messages', () => {
    expect(client._extractText({ _: 'messagePhoto', caption: { text: 'a photo' } })).toBe('a photo');
  });
});

describe('_resolveSender', () => {
  it('resolves a user sender', async () => {
    const result = await client._resolveSender({ _: 'messageSenderUser', user_id: 1 });
    expect(result).toEqual({ id: 1, name: 'Alice' });
  });

  it('resolves another user', async () => {
    const result = await client._resolveSender({ _: 'messageSenderUser', user_id: 2 });
    expect(result).toEqual({ id: 2, name: 'Bob Lee' });
  });

  it('resolves a chat sender', async () => {
    const result = await client._resolveSender({ _: 'messageSenderChat', chat_id: -1001 });
    expect(result).toEqual({ id: -1001, name: 'Test Group' });
  });
});

describe('_formatMessage', () => {
  it('formats a basic text message', async () => {
    const msg = {
      id: 1,
      content: { _: 'messageText', text: { text: 'hello' } },
      sender_id: { _: 'messageSenderUser', user_id: 1 },
      date: 1000000,
      is_outgoing: false,
      reply_to: null,
    };
    const result = await client._formatMessage(msg);
    expect(result).toEqual({
      id: 1,
      type: 'messageText',
      text: 'hello',
      sender: { id: 1, name: 'Alice' },
      date: 1000000,
      own: false,
    });
  });

  it('formats an outgoing message', async () => {
    const msg = {
      id: 2,
      content: { _: 'messageText', text: { text: 'outgoing' } },
      sender_id: { _: 'messageSenderUser', user_id: 1 },
      date: 2000000,
      is_outgoing: true,
      reply_to: null,
    };
    const result = await client._formatMessage(msg);
    expect(result.own).toBe(true);
  });

  it('includes replyTo when message has reply', async () => {
    const msg = {
      id: 3,
      content: { _: 'messageText', text: { text: 'reply' } },
      sender_id: { _: 'messageSenderUser', user_id: 1 },
      date: 3000000,
      is_outgoing: false,
      reply_to: {
        _: 'messageReplyToMessage',
        message_id: 99,
        chat_id: -1001,
        origin_sender_id: { _: 'messageSenderUser', user_id: 2 },
      },
    };
    const result = await client._formatMessage(msg);
    expect(result.replyTo).toBeDefined();
    expect(result.replyTo.id).toBe(99);
    expect(result.replyTo.sender).toEqual({ id: 2, name: 'Bob Lee' });
  });

  it('returns null for null message', async () => {
    expect(await client._formatMessage(null)).toBeNull();
  });
});

describe('_formatReplyTo', () => {
  it('returns null when no reply', async () => {
    const result = await client._formatReplyTo({ reply_to: null });
    expect(result).toBeNull();
  });

  it('returns origin_sender_name fallback when no sender resolved', async () => {
    const msg = {
      reply_to: {
        _: 'messageReplyToMessage',
        message_id: 5,
        chat_id: -1001,
        origin_sender_name: 'TelegramUser',
      },
    };
    const result = await client._formatReplyTo(msg);
    expect(result).toEqual({ id: 5, chat_id: -1001, sender: { id: null, name: 'TelegramUser' }, text: '' });
  });
});

describe('handleUserChatAction', () => {
  afterEach(() => {
    delete global.broadcast;
  });

  it('broadcasts userAction with resolved user name', async () => {
    let broadcastData = null;
    global.broadcast = (data) => { broadcastData = data; };
    await client.handleUserChatAction({
      chat_id: -1001,
      user_id: 1,
      action: { _: 'chatActionTyping' },
    });
    expect(broadcastData).toEqual({
      event: 'userAction',
      chat_id: -1001,
      user_id: 1,
      user_name: 'Alice',
      action: { _: 'chatActionTyping' },
    });
  });

  it('falls back to unknown when user_id is missing', async () => {
    let broadcastData = null;
    global.broadcast = (data) => { broadcastData = data; };
    await client.handleUserChatAction({
      chat_id: -1001,
      action: { _: 'chatActionCancel' },
    });
    expect(broadcastData).toEqual({
      event: 'userAction',
      chat_id: -1001,
      user_id: undefined,
      user_name: 'unknown',
      action: { _: 'chatActionCancel' },
    });
  });

  it('does nothing when global.broadcast is not set', async () => {
    let called = false;
    global.broadcast = () => { called = true; };
    delete global.broadcast;
    await client.handleUserChatAction({ chat_id: -1001, user_id: 1, action: { _: 'chatActionTyping' } });
    expect(called).toBe(false);
  });
});

describe('handleChatAction', () => {
  afterEach(() => {
    delete global.broadcast;
  });

  it('broadcasts userAction with sender resolved from messageSenderUser', async () => {
    let broadcastData = null;
    global.broadcast = (data) => { broadcastData = data; };
    await client.handleChatAction({
      chat_id: -1001,
      sender_id: { _: 'messageSenderUser', user_id: 2 },
      action: { _: 'chatActionRecordingVideo' },
    });
    expect(broadcastData).toEqual({
      event: 'userAction',
      chat_id: -1001,
      user_id: 2,
      user_name: 'Bob Lee',
      action: { _: 'chatActionRecordingVideo' },
    });
  });

  it('broadcasts userAction with sender resolved from messageSenderChat', async () => {
    let broadcastData = null;
    global.broadcast = (data) => { broadcastData = data; };
    await client.handleChatAction({
      chat_id: -1001,
      sender_id: { _: 'messageSenderChat', chat_id: -1001 },
      action: { _: 'chatActionChoosingContact' },
    });
    expect(broadcastData).toEqual({
      event: 'userAction',
      chat_id: -1001,
      user_id: -1001,
      user_name: 'Test Group',
      action: { _: 'chatActionChoosingContact' },
    });
  });

  it('falls back to unknown when sender_id is missing', async () => {
    let broadcastData = null;
    global.broadcast = (data) => { broadcastData = data; };
    await client.handleChatAction({
      chat_id: -1001,
      action: { _: 'chatActionCancel' },
    });
    expect(broadcastData).toEqual({
      event: 'userAction',
      chat_id: -1001,
      user_id: 0,
      user_name: 'unknown',
      action: { _: 'chatActionCancel' },
    });
  });

  it('does nothing when global.broadcast is not set', async () => {
    let called = false;
    global.broadcast = () => { called = true; };
    delete global.broadcast;
    await client.handleChatAction({ chat_id: -1001, sender_id: { _: 'messageSenderUser', user_id: 1 }, action: { _: 'chatActionTyping' } });
    expect(called).toBe(false);
  });
});

describe('_formatMessage with messageChatAddMembers', () => {
  it('includes memberUserIds and addedMemberNames for add-members messages', async () => {
    const msg = {
      id: 10,
      content: {
        _: 'messageChatAddMembers',
        member_user_ids: [2],
      },
      sender_id: { _: 'messageSenderUser', user_id: 1 },
      date: 4000000,
      is_outgoing: false,
      reply_to: null,
    };
    const result = await client._formatMessage(msg);
    expect(result.memberUserIds).toEqual([2]);
    expect(result.addedMemberNames).toEqual(['Bob Lee']);
  });

  it('handles multiple added members', async () => {
    const msg = {
      id: 11,
      content: {
        _: 'messageChatAddMembers',
        member_user_ids: [2, 3],
      },
      sender_id: { _: 'messageSenderUser', user_id: 1 },
      date: 5000000,
      is_outgoing: false,
      reply_to: null,
    };
    const result = await client._formatMessage(msg);
    expect(result.memberUserIds).toEqual([2, 3]);
    expect(result.addedMemberNames).toEqual(['Bob Lee', 'Charlie']);
  });

  it('does not inject fields for non-add-members messages', async () => {
    const msg = {
      id: 12,
      content: { _: 'messageText', text: { text: 'hi' } },
      sender_id: { _: 'messageSenderUser', user_id: 1 },
      date: 6000000,
      is_outgoing: false,
      reply_to: null,
    };
    const result = await client._formatMessage(msg);
    expect(result.memberUserIds).toBeUndefined();
    expect(result.addedMemberNames).toBeUndefined();
  });
});

describe('getChat', () => {
  beforeEach(() => {
    client._ready = true;
  });

  it('returns memberCount for supergroup chats', async () => {
    const result = await client.getChat(-1001);
    expect(result.id).toBe(-1001);
    expect(result.title).toBe('Test Group');
    expect(result.memberCount).toBe(42);
  });

  it('returns 0 memberCount for non-group chats without throwing', async () => {
    const result = await client.getChat(-1002);
    expect(result.id).toBe(-1002);
    expect(result.title).toBe('Private Chat');
    expect(result.memberCount).toBe(0);
  });

  it('returns 0 memberCount for unknown chats without throwing', async () => {
    const result = await client.getChat(-9999);
    expect(result.id).toBe(-9999);
    expect(result.title).toBe('Unknown Group');
    expect(result.memberCount).toBe(0);
  });

  it('returns pinnedMessageId from search when pinned message exists', async () => {
    const fake = client.client as FakeTdClient;
    fake.setPinnedMessage(-1001, 42);
    const result = await client.getChat(-1001);
    expect(result.pinnedMessageId).toBe(42);
  });

  it('returns 0 pinnedMessageId when no pinned message', async () => {
    const result = await client.getChat(-1002);
    expect(result.pinnedMessageId).toBe(0);
  });
});

describe('handleNewMessage', () => {
  afterEach(() => {
    delete global.broadcast;
  });

  it('broadcasts newMessage event', async () => {
    let broadcastData = null;
    global.broadcast = (data) => { broadcastData = data; };
    const msg = {
      id: 20,
      chat_id: -1001,
      content: { _: 'messageText', text: { text: 'hello world' } },
      sender_id: { _: 'messageSenderUser', user_id: 1 },
      date: 7000000,
      is_outgoing: false,
      reply_to: null,
    };
    await client.handleNewMessage(msg);
    expect(broadcastData).toMatchObject({
      event: 'newMessage',
      chat: { id: -1001, title: 'Test Group' },
      id: 20,
      text: 'hello world',
      sender: { id: 1, name: 'Alice' },
    });
  });

  it('does nothing when global.broadcast is not set', async () => {
    let called = false;
    global.broadcast = () => { called = true; };
    delete global.broadcast;
    await client.handleNewMessage({
      id: 21, chat_id: -1001,
      content: { _: 'messageText', text: { text: 'x' } },
      sender_id: { _: 'messageSenderUser', user_id: 1 },
      date: 8000000, is_outgoing: false, reply_to: null,
    });
    expect(called).toBe(false);
  });
});

describe('handleChatOnlineMemberCount', () => {
  afterEach(() => {
    delete global.broadcast;
  });

  it('broadcasts online member count', () => {
    let broadcastData = null;
    global.broadcast = (data) => { broadcastData = data; };
    client.handleChatOnlineMemberCount({
      chat_id: -1001,
      online_member_count: 7,
    });
    expect(broadcastData).toEqual({
      event: 'chatOnlineMemberCount',
      chat_id: -1001,
      online_member_count: 7,
    });
  });

  it('does nothing when global.broadcast is not set', () => {
    let called = false;
    global.broadcast = () => { called = true; };
    delete global.broadcast;
    client.handleChatOnlineMemberCount({ chat_id: -1001, online_member_count: 3 });
    expect(called).toBe(false);
  });
});

describe('handleChatMemberUpdate', () => {
  afterEach(() => {
    delete global.broadcast;
  });

  it('broadcasts chatMember with actor and member', async () => {
    let broadcastData = null;
    global.broadcast = (data) => { broadcastData = data; };
    await client.handleChatMemberUpdate({
      chat_id: -1001,
      member: { user_id: 2 },
      actor_user_id: 1,
      old_status: { _: 'chatMemberStatusLeft' },
      new_status: { _: 'chatMemberStatusMember' },
    });
    expect(broadcastData).toMatchObject({
      event: 'chatMember',
      chat_id: -1001,
      chat_title: 'Test Group',
      member: { id: 2, name: 'Bob Lee' },
      actor: { id: 1, name: 'Alice' },
    });
  });

  it('uses same name for actor when actor is the member (self-join)', async () => {
    let broadcastData = null;
    global.broadcast = (data) => { broadcastData = data; };
    await client.handleChatMemberUpdate({
      chat_id: -1001,
      member: { user_id: 1 },
      actor_user_id: 1,
      old_status: { _: 'chatMemberStatusLeft' },
      new_status: { _: 'chatMemberStatusMember' },
    });
    expect(broadcastData).toMatchObject({
      member: { id: 1, name: 'Alice' },
      actor: { id: 1, name: 'Alice' },
    });
  });

  it('does nothing when global.broadcast is not set', async () => {
    let called = false;
    global.broadcast = () => { called = true; };
    delete global.broadcast;
    await client.handleChatMemberUpdate({
      chat_id: -1001, member: { user_id: 1 }, actor_user_id: 1,
      old_status: { _: 'chatMemberStatusLeft' }, new_status: { _: 'chatMemberStatusMember' },
    });
    expect(called).toBe(false);
  });
});
