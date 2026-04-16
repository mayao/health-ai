import { getAuthenticatedUserId, AuthError } from "../../../../server/http/auth-middleware";
import { jsonOk, jsonSafeError } from "../../../../server/http/safe-response";
import { getAppEnv } from "../../../../server/config/env";
import { getDatabase } from "../../../../server/db/sqlite";
import { getUserPreferredProvider, setUserPreferredProvider } from "../../../../server/services/llm-preference-service";
import {
  BASE_PROVIDER_ORDER,
  getDefaultPrimaryProvider,
  isProviderConfigured,
  sortProvidersByConnectivity,
  type LLMProviderName
} from "../../../../server/services/llm-provider-routing";

export const dynamic = "force-dynamic";

async function buildProviders(preferredProvider: string | null) {
  const env = getAppEnv();
  const kimiKey = process.env.HEALTH_LLM_FALLBACK_KIMI_KEY;
  const minimaxKey = process.env.HEALTH_LLM_FALLBACK_MINIMAX_KEY;
  const openaiOk = !!(env.HEALTH_LLM_API_KEY && env.HEALTH_LLM_PROVIDER === "openai-compatible" && env.HEALTH_LLM_BASE_URL);
  const anthropicOk = isProviderConfigured("anthropic", env);

  const activeProvider =
    BASE_PROVIDER_ORDER.find((name) => name === preferredProvider && isProviderConfigured(name, env)) ??
    getDefaultPrimaryProvider(env);

  const orderedProviders = await sortProvidersByConnectivity(
    BASE_PROVIDER_ORDER.filter((name) => name !== activeProvider),
    env
  );

  const providerOrder = [activeProvider, ...orderedProviders].filter(Boolean) as LLMProviderName[];

  const providersByName = {
    anthropic: {
      name: "anthropic" as const,
      label: "Claude（主通道）",
      isConfigured: anthropicOk,
      isPrimary: activeProvider === "anthropic",
      model: anthropicOk ? (env.HEALTH_LLM_MODEL ?? "claude-sonnet-4-20250514") : null
    },
    openai_compatible: {
      name: "openai_compatible" as const,
      label: "OpenAI 兼容",
      isConfigured: openaiOk,
      isPrimary: activeProvider === "openai_compatible",
      model: openaiOk ? (env.HEALTH_LLM_MODEL ?? null) : null
    },
    kimi: {
      name: "kimi" as const,
      label: "Kimi（月之暗面）",
      isConfigured: !!kimiKey,
      isPrimary: activeProvider === "kimi",
      model: kimiKey ? (process.env.HEALTH_LLM_FALLBACK_KIMI_MODEL ?? "kimi-latest") : null
    },
    minimax: {
      name: "minimax" as const,
      label: "MiniMax",
      isConfigured: !!minimaxKey && !!process.env.HEALTH_LLM_FALLBACK_MINIMAX_BASE_URL,
      isPrimary: activeProvider === "minimax",
      model: minimaxKey ? (process.env.HEALTH_LLM_FALLBACK_MINIMAX_MODEL ?? "minimax-2.7-highspped") : null
    }
  } as const satisfies Record<LLMProviderName, {
    name: LLMProviderName;
    label: string;
    isConfigured: boolean;
    isPrimary: boolean;
    model: string | null;
  }>;

  const providers = providerOrder.map((name) => providersByName[name]);
  const missingProviders = (Object.keys(providersByName) as LLMProviderName[])
    .filter((name) => !providerOrder.includes(name))
    .map((name) => providersByName[name]);

  return {
    providers: [...providers, ...missingProviders],
    activeProvider
  };
}

export async function GET(request: Request) {
  try {
    const userId = getAuthenticatedUserId(request);
    const db = getDatabase();
    const preferredProvider = getUserPreferredProvider(db, userId);
    return jsonOk(await buildProviders(preferredProvider));
  } catch (error) {
    if (error instanceof AuthError) return jsonSafeError({ message: error.message, status: 401, error, context: { route: "/api/ai/model-status" } });
    return jsonSafeError({ message: "获取模型状态失败", status: 500, error, context: { route: "/api/ai/model-status" } });
  }
}

export async function POST(request: Request) {
  try {
    const userId = getAuthenticatedUserId(request);
    const body = (await request.json()) as { provider?: string };
    const provider = body.provider ?? null;

    const validProviders: LLMProviderName[] = ["anthropic", "openai_compatible", "kimi", "minimax"];
    if (provider && !validProviders.includes(provider as LLMProviderName)) {
      return jsonSafeError({ message: "无效的模型提供商", status: 400, error: new Error("invalid provider"), context: { route: "/api/ai/model-status" } });
    }

    const db = getDatabase();
    setUserPreferredProvider(db, userId, provider);

    return jsonOk(await buildProviders(provider));
  } catch (error) {
    if (error instanceof AuthError) return jsonSafeError({ message: error.message, status: 401, error, context: { route: "/api/ai/model-status" } });
    return jsonSafeError({ message: "设置模型偏好失败", status: 500, error, context: { route: "/api/ai/model-status" } });
  }
}
