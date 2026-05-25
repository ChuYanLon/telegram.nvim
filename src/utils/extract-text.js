function extractText(content) {
  if (!content) return '';
  if (content._ === 'messageText') return content.text.text;
  if (content.caption && content.caption.text) return content.caption.text;
  return '';
}

module.exports = { extractText };
