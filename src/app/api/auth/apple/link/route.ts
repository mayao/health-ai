import { z } from "zod";

import { getAuthenticatedUserId, AuthError } from "../../../../../server/http/auth-middleware";
import { jsonOk, jsonSafeError } from "../../../../../server/http/safe-response";
import { linkAppleIdentity } from "../../../../../server/services/auth-service";
import { AppleIdentityError } from "../../../../../server/services/apple-auth-service";

export const dynamic = "force-dynamic";

const appleLinkSchema = z.object({
  identityToken: z.string().min(1).optional(),
  identity_token: z.string().min(1).optional(),
  authorizationCode: z.string().optional(),
  authorization_code: z.string().optional(),
  email: z.string().email().optional().or(z.literal("").transform(() => undefined)),
  displayName: z.string().optional(),
  display_name: z.string().optional(),
}).refine((value) => value.identityToken || value.identity_token, {
  message: "缺少 Apple 身份令牌"
});

function logAppleAuthFailure(route: string, request: Request, error: AppleIdentityError) {
  console.error("[apple-auth]", {
    route,
    kind: error.kind,
    status: error.status,
    kid: error.metadata.kid ?? "",
    acceptedAudiences: error.metadata.acceptedAudiences?.join(",") ?? "",
    tokenAudiences: error.metadata.tokenAudiences?.join(",") ?? "",
    cacheHit: String(Boolean(error.metadata.cacheHit)),
    usedStaleCache: String(Boolean(error.metadata.usedStaleCache)),
    upstreamStatus: error.metadata.upstreamStatus?.toString() ?? "",
    hostname: request.headers.get("host") ?? "",
    runtimeHost: process.env.HOSTNAME ?? ""
  });
}

export async function POST(request: Request) {
  try {
    const currentUserId = getAuthenticatedUserId(request);
    const body = appleLinkSchema.parse(await request.json());
    const result = await linkAppleIdentity(currentUserId, {
      identityToken: body.identityToken || body.identity_token!,
      authorizationCode: body.authorizationCode || body.authorization_code,
      email: body.email,
      displayName: body.displayName || body.display_name
    });
    return jsonOk(result);
  } catch (error) {
    if (error instanceof z.ZodError) {
      return jsonSafeError({
        message: "Apple 绑定请求无效，请重新尝试。",
        status: 400,
        error,
        context: { route: "/api/auth/apple/link", method: "POST" }
      });
    }

    if (error instanceof AppleIdentityError) {
      logAppleAuthFailure("/api/auth/apple/link", request, error);
      const message =
        error.status >= 500
          ? "Apple 绑定服务暂时不可用，请稍后再试。"
          : "Apple 授权已失效或返回无效，请重新尝试。";
      return jsonSafeError({
        message,
        status: error.status,
        error,
        context: {
          route: "/api/auth/apple/link",
          method: "POST",
          error_kind: error.kind
        }
      });
    }

    const message = error instanceof Error ? error.message : "Apple 账号绑定失败，请重试";
    return jsonSafeError({
      message,
      status: error instanceof AuthError ? 401 : 500,
      error,
      context: { route: "/api/auth/apple/link", method: "POST" }
    });
  }
}
