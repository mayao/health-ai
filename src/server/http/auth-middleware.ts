import { getAppEnv } from "../config/env";
import { validateToken, AuthError, getSingleUserModeUserId } from "../services/auth-service";

export { AuthError };

function getAuthenticatedUserIdFromRequestHeaders(headers: Headers): string {
  const env = getAppEnv();

  if (!env.HEALTH_AUTH_ENABLED) {
    const singleUserId = getSingleUserModeUserId();
    if (!singleUserId) {
      throw new AuthError("服务端未启用登录，且未显式开启单人模式，已拒绝请求以防止数据串号。");
    }

    return singleUserId;
  }

  const authHeader = headers.get("Authorization");
  if (!authHeader?.startsWith("Bearer ")) {
    throw new AuthError("请先登录");
  }

  const token = authHeader.slice(7);
  return validateToken(token);
}

/**
 * Extract authenticated user ID from request.
 * In multi-user mode, missing auth is rejected instead of falling back to a shared account.
 */
export function getAuthenticatedUserId(request: Request): string {
  return getAuthenticatedUserIdFromRequestHeaders(request.headers);
}

/**
 * Extract Bearer token from request (for logout etc).
 */
export function extractBearerToken(request: Request): string | null {
  const authHeader = request.headers.get("Authorization");
  if (!authHeader?.startsWith("Bearer ")) return null;
  return authHeader.slice(7);
}

export function getAuthenticatedUserIdFromHeaders(headers: Headers): string {
  return getAuthenticatedUserIdFromRequestHeaders(headers);
}
