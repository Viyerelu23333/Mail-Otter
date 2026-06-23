import { stripHtml, normalizeText } from './TextContentUtil';

function toCrlf(value: string): string {
  return value.replace(/\r\n/g, '\n').replace(/\r/g, '\n').replace(/\n/g, '\r\n');
}

function buildAlternativeMimeBody(textBody: string, htmlBody: string, boundary: string): string {
  return [
    `--${boundary}`,
    'Content-Type: text/plain; charset=utf-8',
    'Content-Transfer-Encoding: 8bit',
    '',
    toCrlf(textBody),
    `--${boundary}`,
    'Content-Type: text/html; charset=utf-8',
    'Content-Transfer-Encoding: 8bit',
    '',
    toCrlf(htmlBody),
    `--${boundary}--`,
    '',
  ].join('\r\n');
}

function extractTextFromRaw(raw: string): string {
  const boundary = /boundary="?([^";\r\n]+)"?/i.exec(raw)?.[1];
  if (!boundary) {
    const headerEnd = raw.indexOf('\r\n\r\n');
    const body = headerEnd >= 0 ? raw.slice(headerEnd + 4) : raw;
    return normalizeText(stripHtml(body)).trim();
  }
  const parts = raw.split(`--${boundary}`);
  for (const part of parts) {
    if (!part.trim() || part.trim() === '--') continue;
    const partHeaderEnd = part.indexOf('\r\n\r\n');
    if (partHeaderEnd < 0) continue;
    const partHeaders = part.slice(0, partHeaderEnd).toLowerCase();
    const partBody = part.slice(partHeaderEnd + 4);
    if (partHeaders.includes('text/plain')) {
      return normalizeText(partBody.split(`\r\n--${boundary}`)[0]).trim();
    }
  }
  for (const part of parts) {
    const partHeaderEnd = part.indexOf('\r\n\r\n');
    if (partHeaderEnd < 0) continue;
    const partHeaders = part.slice(0, partHeaderEnd).toLowerCase();
    const partBody = part.slice(partHeaderEnd + 4);
    if (partHeaders.includes('text/html')) {
      return normalizeText(stripHtml(partBody.split(`\r\n--${boundary}`)[0])).trim();
    }
  }
  return '';
}

export { toCrlf, buildAlternativeMimeBody, extractTextFromRaw };
