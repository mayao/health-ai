import { getAuthenticatedUserId, AuthError } from "../../../../server/http/auth-middleware";
import { jsonOk, jsonSafeError } from "../../../../server/http/safe-response";
import {
  healthAIChatRequestSchema,
  replyWithHealthAI,
  streamHealthAIReply
} from "../../../../server/services/ai-chat-service";

export const dynamic = "force-dynamic";

export async function POST(request: Request) {
  try {
    const userId = getAuthenticatedUserId(request);
    const body = await request.json();
    const payload = healthAIChatRequestSchema.parse(body);

    // Check if client requests streaming (via body.stream or Accept header)
    const wantStream =
      body.stream === true ||
      request.headers.get("accept")?.includes("text/event-stream");

    if (wantStream) {
      const { stream, provider, model } = await streamHealthAIReply(payload, userId);
      return new Response(stream, {
        headers: {
          "Content-Type": "text/event-stream",
          "Cache-Control": "no-cache",
          Connection: "keep-alive",
          "X-AI-Provider": provider,
          "X-AI-Model": model,
        },
      });
    }

    return jsonOk(await replyWithHealthAI(payload, userId));
  } catch (error) {
    if (error instanceof AuthError) {
      return jsonSafeError({ message: error.message, status: 401, error, context: { route: "/api/ai/chat", method: "POST" } });
    }
    const msg = error instanceof Error ? error.message : "未知错误";
    console.error("[AI Chat] Error:", msg, error);
    return jsonSafeError({
      message: `AI 对话暂时不可用：${msg}`,
      status: 500,
      error,
      context: { route: "/api/ai/chat", method: "POST" }
    });
  }
}
