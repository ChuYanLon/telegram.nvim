import { describe, it, expect, beforeAll } from 'vitest';
import FakeTdClient from './fake-td-client';

let client;

beforeAll(async () => {
  process.env.TG_TDLIB_PATH = '/dev/null';
  const { default: TelegramLSPClient } = await import('../src/tdlib-client');
  const fake = new FakeTdClient();
  fake.addUser({ id: 1, first_name: 'Alice', last_name: null });
  fake.addUser({ id: 2, first_name: 'Bob', last_name: 'Lee' });
  fake.addChat({ id: -1001, title: 'Test Group' });
  client = new TelegramLSPClient({ client: fake });
  // Pre-populate internal caches so resolveSender works
  client._users.set(1, 'Alice');
  client._users.set(2, 'Bob Lee');
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
