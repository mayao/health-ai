/**
 * Normalize Anthropic-compatible gateway base URLs to the Messages API endpoint.
 * Accepts roots like `https://host/.../api` or already-suffixed `.../v1/messages`.
 */
export function resolveAnthropicMessagesUrl(baseUrl: string): string {
  const u = baseUrl.trim().replace(/\/$/, "");
  if (/\/v1\/messages$/i.test(u)) return u;
  if (/\/api$/i.test(u)) return `${u}/v1/messages`;
  if (/\/v1$/i.test(u)) return `${u}/messages`;
  return `${u}/v1/messages`;
}
