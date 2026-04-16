/**
 * Normalize Anthropic "messages" endpoint URLs for:
 * - Official API: https://api.anthropic.com/v1/messages
 * - Internal Deepgate style: http://host/.../api  → .../api/v1/messages
 * - Already explicit .../api/v1  → .../api/v1/messages
 */
export function resolveAnthropicMessagesUrl(rawBaseUrl: string): string {
  const base = rawBaseUrl.trim().replace(/\/$/, "");
  if (!base) {
    return "https://api.anthropic.com/v1/messages";
  }
  if (base.endsWith("/messages")) {
    return base;
  }
  if (/\/api$/i.test(base)) {
    return `${base}/v1/messages`;
  }
  if (/\/v1\/anthropic$/i.test(base)) {
    return base.replace(/\/v1\/anthropic$/i, "/v1/messages");
  }
  return `${base}/messages`;
}
