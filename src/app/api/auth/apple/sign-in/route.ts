import { z } from "zod";

import { jsonOk, jsonSafeError } from "../../../../../server/http/safe-response";
import { signInWithApple } from "../../../../../server/services/auth-service";
import { AppleIdentityError } from "../../../../../server/services/apple-auth-service";

export const dynamic = "force-dynamic";

const appleAuthSchema = z.object({
  identityToken: z.string().min(1).optional(),
  identity_token: z.string().min(1).optional(),
  authorizationCode: z.string().optional(),
  authorization_code: z.string().optional(),
  email: z.string().email().optional().or(z.literal("").transform(() => undefined)),
  displayName: z.string().optional(),
  display_name: z.string().optional(),
  deviceId: z.string().min(8).optional(),
  device_id: z.string().min(8).optional(),
  deviceLabel: z.string().optional(),
  device_label: z.string().optional(),
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
    const body = appleAuthSchema.parse(await request.json());
    const result = await signInWithApple(
      {
        identityToken: body.identityToken || body.identity_token!,
        authorizationCode: body.authorizationCode || body.authorization_code,
        email: body.email,
        displayName: body.displayName || body.display_name,
        deviceId: body.deviceId || body.device_id
      },
      body.deviceLabel || body.device_label
    );
    return jsonOk(result);
  } catch (error) {
    if (error instanceof z.ZodError) {
      return jsonSafeError({
        message: "Apple 登录请求无效，请重新尝试。",
        status: 400,
        error,
        context: { route: "/api/auth/apple/sign-in", method: "POST" }
      });
    }

    if (error instanceof AppleIdentityError) {
      logAppleAuthFailure("/api/auth/apple/sign-in", request, error);
      const message =
        error.status >= 500
          ? "Apple 登录服务暂时不可用，请稍后重试或先使用本机快速进入。"
          : "Apple 授权已失效或返回无效，请重新尝试。";
      return jsonSafeError({
        message,
        status: error.status,
        error,
        context: {
          route: "/api/auth/apple/sign-in",
          method: "POST",
          error_kind: error.kind
        }
      });
    }

    const message = error instanceof Error ? error.message : "Apple 登录失败，请重试";
    return jsonSafeError({
      message,
      status: 500,
      error,
      context: { route: "/api/auth/apple/sign-in", method: "POST" }
    });
  }
}
