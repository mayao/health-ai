import type { AppEnv } from "../config/env";

import { resolveAnthropicMessagesUrl } from "../llm/anthropic-messages-url";

export type LLMProviderName = "anthropic" | "openai_compatible" | "kimi" | "minimax";

export const BASE_PROVIDER_ORDER: LLMProviderName[] = [
  "anthropic",
  "kimi",
  "minimax",
  "openai_compatible"
];

export function isKimiCodingKey(apiKey?: string | null): boolean {
  return !!apiKey?.startsWith("sk-kimi-");
}

export function getKimiOpenAIHeaders(apiKey?: string | null): Record<string, string> | undefined {
  if (!isKimiCodingKey(apiKey)) return undefined;
  return { "User-Agent": "KimiCLI/1.3" };
}

export function isProviderConfigured(provider: LLMProviderName, env: AppEnv): boolean {
  switch (provider) {
    case "kimi":
      return !!(
        process.env.HEALTH_LLM_FALLBACK_KIMI_KEY &&
        (
          process.env.HEALTH_LLM_FALLBACK_KIMI_BASE_URL ||
          process.env.HEALTH_LLM_FALLBACK_KIMI_KEY.startsWith("sk-kimi-") ||
          process.env.HEALTH_LLM_FALLBACK_KIMI_KEY.startsWith("sk-")
        )
      );
    case "minimax":
      return !!(
        process.env.HEALTH_LLM_FALLBACK_MINIMAX_KEY &&
        process.env.HEALTH_LLM_FALLBACK_MINIMAX_BASE_URL
      );
    case "anthropic":
      return !!(env.HEALTH_LLM_API_KEY && (!env.HEALTH_LLM_PROVIDER || env.HEALTH_LLM_PROVIDER === "anthropic"));
    case "openai_compatible":
      return !!(env.HEALTH_LLM_API_KEY && env.HEALTH_LLM_PROVIDER === "openai-compatible" && env.HEALTH_LLM_BASE_URL);
  }
}

export function getDefaultPrimaryProvider(env: AppEnv): LLMProviderName | null {
  return BASE_PROVIDER_ORDER.find((p) => isProviderConfigured(p, env)) ?? null;
}

export function getProviderPriority(
  env: AppEnv,
  preferredProvider?: string | null
): LLMProviderName[] {
  const preferred = BASE_PROVIDER_ORDER.find(
    (p) => p === preferredProvider && isProviderConfigured(p, env)
  );

  const ordered = preferred
    ? [preferred, ...BASE_PROVIDER_ORDER.filter((p) => p !== preferred)]
    : BASE_PROVIDER_ORDER;

  return ordered.filter((p) => isProviderConfigured(p, env));
}

export async function sortProvidersByConnectivity(
  providers: LLMProviderName[],
  env: AppEnv
): Promise<LLMProviderName[]> {
  const probeResults = await Promise.all(
    providers.map(async (provider) => ({
      provider,
      ...(await probeProvider(provider, env))
    }))
  );

  return probeResults
    .sort((left, right) => {
      if (left.reachable !== right.reachable) return left.reachable ? -1 : 1;
      return left.latencyMs - right.latencyMs;
    })
    .map((item) => item.provider);
}

async function probeProvider(
  provider: LLMProviderName,
  env: AppEnv
): Promise<{ reachable: boolean; latencyMs: number }> {
  const target = probeTargetFor(provider, env);
  if (!target) return { reachable: false, latencyMs: Number.POSITIVE_INFINITY };

  const startedAt = Date.now();
  try {
    await fetch(target, {
      method: "GET",
      signal: AbortSignal.timeout(2_500)
    });
    return { reachable: true, latencyMs: Date.now() - startedAt };
  } catch {
    return { reachable: false, latencyMs: Number.POSITIVE_INFINITY };
  }
}

function probeTargetFor(provider: LLMProviderName, env: AppEnv): string | null {
  switch (provider) {
    case "kimi": {
      const kimiKey = process.env.HEALTH_LLM_FALLBACK_KIMI_KEY;
      if (!kimiKey) return null;
      if (process.env.HEALTH_LLM_FALLBACK_KIMI_BASE_URL) {
        return process.env.HEALTH_LLM_FALLBACK_KIMI_BASE_URL;
      }
      return kimiKey.startsWith("sk-kimi-") ? "https://api.kimi.com" : "https://api.moonshot.cn";
    }
    case "minimax":
      return process.env.HEALTH_LLM_FALLBACK_MINIMAX_BASE_URL ?? null;
    case "anthropic":
      if (!isProviderConfigured("anthropic", env)) {
        return null;
      }
      return resolveAnthropicMessagesUrl(env.HEALTH_LLM_BASE_URL ?? "https://api.anthropic.com/v1/messages");
    case "openai_compatible":
      return env.HEALTH_LLM_BASE_URL ?? null;
  }
}
