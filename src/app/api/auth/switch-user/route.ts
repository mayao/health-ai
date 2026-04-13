import { z } from "zod";

import { getAuthenticatedUserId, AuthError } from "../../../../server/http/auth-middleware";
import { jsonOk, jsonSafeError } from "../../../../server/http/safe-response";
import { switchToUser, canUserSwitch } from "../../../../server/services/auth-service";

export const dynamic = "force-dynamic";

const switchUserSchema = z.object({
  target_user_id: z.string().min(1, "请指定目标用户"),
});

export async function POST(request: Request) {
  try {
    const currentUserId = getAuthenticatedUserId(request);

    // Backend permission enforcement: only allowed users can switch
    if (!canUserSwitch(currentUserId)) {
      return jsonSafeError({
        message: "当前账号没有切换用户的权限",
        status: 403,
        error: new Error("Forbidden"),
        context: { route: "/api/auth/switch-user", method: "POST" },
      });
    }

    const body = switchUserSchema.parse(await request.json());
    const result = switchToUser(body.target_user_id);
    return jsonOk(result);
  } catch (error) {
    if (error instanceof AuthError) {
      return jsonSafeError({ message: error.message, status: 401, error, context: { route: "/api/auth/switch-user", method: "POST" } });
    }
    const message = error instanceof Error ? error.message : "切换用户失败";
    return jsonSafeError({
      message,
      status: error instanceof z.ZodError ? 400 : 500,
      error,
      context: { route: "/api/auth/switch-user", method: "POST" },
    });
  }
}
