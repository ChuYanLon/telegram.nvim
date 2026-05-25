import { describe, it, expect, beforeAll, vi } from 'vitest';

vi.mock('dotenv', () => ({ default: { config: () => ({}) } }));
vi.mock('tdl', () => ({
  default: {
    configure: () => {},
    createClient: () => ({
      on: () => {},
      invoke: async () => ({ value: '1.8.64' }),
      login: async () => {},
      close: async () => {},
    }),
  },
}));

let client;

beforeAll(async () => {
  process.env.TG_API_ID = '1';
  process.env.TG_API_HASH = 'test';
  const mod = await import('../src/tdlib-client');
  client = new mod.default();
});

describe('_extractText', () => {
  it('returns empty string for null/undefined', () => {
    expect(client._extractText(null)).toBe('');
    expect(client._extractText(undefined)).toBe('');
  });

  it('extracts text from messageText', () => {
    expect(
      client._extractText({ _: 'messageText', text: { text: 'hello world' } }),
    ).toBe('hello world');
  });

  it('returns type name for non-text messages', () => {
    expect(client._extractText({ _: 'messagePhoto' })).toBe('messagePhoto');
    expect(client._extractText({ _: 'messageSticker' })).toBe('messageSticker');
    expect(client._extractText({ _: 'messageDocument' })).toBe('messageDocument');
    expect(client._extractText({ _: 'messageAudio' })).toBe('messageAudio');
  });
});

describe('_formatMessage', () => {
  it('formats a basic text message', async () => {
    const msg = {
      id: 123,
      content: { _: 'messageText', text: { text: 'hi' } },
      sender_id: { _: 'messageSenderUser', user_id: 1 },
      date: 1000000,
      is_outgoing: false,
      reply_to: null,
    };
    const result = await client._formatMessage(msg);
    expect(result.id).toBe(123);
    expect(result.text).toBe('hi');
    expect(result.date).toBe(1000000);
    expect(result.own).toBe(false);
    expect(result.type).toBe('messageText');
  });

  it('returns null for null message', async () => {
    expect(await client._formatMessage(null)).toBeNull();
  });

  it('includes replyTo when message has reply', async () => {
    const msg = {
      id: 456,
      content: { _: 'messageText', text: { text: 'reply test' } },
      sender_id: { _: 'messageSenderUser', user_id: 1 },
      date: 2000000,
      is_outgoing: true,
      reply_to: {
        _: 'messageReplyToMessage',
        message_id: 1,
        chat_id: 10,
        origin_sender_id: { _: 'messageSenderUser', user_id: 2 },
      },
    };
    const result = await client._formatMessage(msg);
    expect(result.id).toBe(456);
    expect(result.replyTo).toBeDefined();
    expect(result.replyTo.id).toBe(1);
    expect(result.own).toBe(true);
  });
});
