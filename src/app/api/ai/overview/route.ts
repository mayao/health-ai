import { getAuthenticatedUserId, AuthError } from "../../../../server/http/auth-middleware";
import { jsonOk, jsonSafeError } from "../../../../server/http/safe-response";
import { generateAIOverview } from "../../../../server/services/ai-overview-service";

export const dynamic = "force-dynamic";

export async function GET(request: Request) {
  try {
    const userId = getAuthenticatedUserId(request);
    const result = await generateAIOverview(userId);
    return jsonOk(result);
  } catch (error) {
    if (error instanceof AuthError) {
      return jsonSafeError({ message: error.message, status: 401, error, context: { route: "/api/ai/overview", method: "GET" } });
    }
    return jsonSafeError({
      message: "AI 综合概览暂时不可用，请稍后重试。",
      status: 500,
      error,
      context: { route: "/api/ai/overview", method: "GET" }
    });
  }
}
