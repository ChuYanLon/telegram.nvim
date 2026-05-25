function extractText(content) {
  if (!content) return '';
  if (content._ === 'messageText') return content.text.text;
  return content._;
}

module.exports = { extractText };
