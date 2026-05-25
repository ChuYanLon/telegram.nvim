const { describe, it, before, mock } = require('node:test');
const assert = require('node:assert/strict');

let client;

before(() => {
  mock.module('dotenv', {
    namedExports: { config: () => ({}) },
  });
  mock.module('tdl', {
    defaultExport: {
      configure: () => {},
      createClient: () => ({
        on: () => {},
        invoke: async () => ({}),
        close: async () => {},
      }),
    },
  });
  process.env.TG_API_ID = '1';
  process.env.TG_API_HASH = 'test';

  const TelegramLSPClient = require('../src/tdlib-client');
  client = new TelegramLSPClient();
});

describe('_extractText', () => {
  it('returns empty string for null/undefined', () => {
    assert.equal(client._extractText(null), '');
    assert.equal(client._extractText(undefined), '');
  });

  it('extracts text from messageText', () => {
    assert.equal(
      client._extractText({ _: 'messageText', text: { text: 'hello world' } }),
      'hello world'
    );
  });

  it('returns type name for non-text messages', () => {
    assert.equal(client._extractText({ _: 'messagePhoto' }), 'messagePhoto');
    assert.equal(client._extractText({ _: 'messageSticker' }), 'messageSticker');
    assert.equal(client._extractText({ _: 'messageDocument' }), 'messageDocument');
    assert.equal(client._extractText({ _: 'messageAudio' }), 'messageAudio');
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
    assert.equal(result.id, 123);
    assert.equal(result.text, 'hi');
    assert.equal(result.date, 1000000);
    assert.equal(result.own, false);
    assert.equal(result.type, 'messageText');
  });

  it('returns null for null message', async () => {
    assert.equal(await client._formatMessage(null), null);
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
    assert.equal(result.id, 456);
    assert.ok(result.replyTo);
    assert.equal(result.replyTo.id, 1);
    assert.equal(result.own, true);
  });
});
