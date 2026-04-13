import { getAuthenticatedUserId, AuthError } from "../../../../../server/http/auth-middleware";
import {
  healthAIChatRequestSchema,
  streamHealthAIReply
} from "../../../../../server/services/ai-chat-service";

export const dynamic = "force-dynamic";

export async function POST(request: Request) {
  try {
    const userId = getAuthenticatedUserId(request);
    const payload = healthAIChatRequestSchema.parse(await request.json());

    const { stream, provider, model } = await streamHealthAIReply(payload, userId);

    return new Response(stream, {
      headers: {
        "Content-Type": "text/event-stream",
        "Cache-Control": "no-cache, no-transform",
        Connection: "keep-alive",
        "X-LLM-Provider": provider,
        "X-LLM-Model": model
      }
    });
  } catch (error) {
    if (error instanceof AuthError) {
      return new Response(JSON.stringify({ error: { message: error.message } }), {
        status: 401,
        headers: { "Content-Type": "application/json" }
      });
    }
    const msg = error instanceof Error ? error.message : "未知错误";
    console.error("[AI Chat Stream] Error:", msg);
    return new Response(JSON.stringify({ error: { message: `AI 对话暂时不可用：${msg}` } }), {
      status: 500,
      headers: { "Content-Type": "application/json" }
    });
  }
}
