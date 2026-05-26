interface TdMessageContent {
  _: string;
  text?: { text: string };
  caption?: { text: string };
  [key: string]: unknown;
}

export function extractText(content: TdMessageContent | null | undefined): string {
  if (!content) return '';
  if (content._ === 'messageText') return content.text!.text;
  if (content.caption?.text) return content.caption.text;
  return '';
}
