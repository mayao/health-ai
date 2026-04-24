import type { DatabaseSync } from "node:sqlite";

import { getAppEnv } from "../config/env";
import { getDatabase } from "../db/sqlite";
import { getHealthHomePageData } from "./health-home-service";

export interface AIOverviewResult {
  headline: string;
  summary: string;
  sections: AIOverviewSection[];
  actionPlan: string[];
  provider: string;
  model: string;
  generatedAt: string;
  disclaimer: string;
  cached?: boolean;
}

interface AIOverviewSection {
  title: string;
  icon: string;
  items: string[];
}

// ─── In-memory cache ────────────────────────────────────────────────────────
const overviewCache = new Map<string, { result: AIOverviewResult; expiresAt: number }>();
const CACHE_TTL_MS = 30 * 60 * 1000; // 30 minutes

// ─── Build prompt from user data ────────────────────────────────────────────
function buildUserProfileForLLM(payload: Awaited<ReturnType<typeof getHealthHomePageData>>): string {
  const parts: string[] = [];

  parts.push("## 当前健康概况");
  parts.push(`综合评估：${payload.overviewDigest.headline}`);
  parts.push(`核心摘要：${payload.overviewDigest.summary}`);

  if (payload.overviewDigest.goodSignals.length > 0) {
    parts.push("\n## 积极信号");
    payload.overviewDigest.goodSignals.forEach((s, i) => parts.push(`${i + 1}. ${s}`));
  }

  if (payload.overviewDigest.needsAttention.length > 0) {
    parts.push("\n## 需要关注");
    payload.overviewDigest.needsAttention.forEach((s, i) => parts.push(`${i + 1}. ${s}`));
  }

  if (payload.overviewDigest.longTermRisks.length > 0) {
    parts.push("\n## 长期风险背景");
    payload.overviewDigest.longTermRisks.forEach((s, i) => parts.push(`${i + 1}. ${s}`));
  }

  if (payload.annualExam) {
    parts.push("\n## 最近体检报告");
    parts.push(`体检时间：${payload.annualExam.latestRecordedAt}`);
    if (payload.annualExam.abnormalMetricLabels.length > 0) {
      parts.push(`异常项目：${payload.annualExam.abnormalMetricLabels.join("、")}`);
    }
    if (payload.annualExam.improvedMetricLabels.length > 0) {
      parts.push(`改善项目：${payload.annualExam.improvedMetricLabels.join("、")}`);
    }
    payload.annualExam.metrics.slice(0, 10).forEach(m => {
      const flag = m.abnormalFlag ? `【${m.abnormalFlag}】` : "";
      parts.push(`- ${m.label}：${m.latestValue} ${m.unit} ${flag}${m.referenceRange ? `（参考范围：${m.referenceRange}）` : ""}`);
    });
  }

  if (payload.geneticFindings.length > 0) {
    parts.push("\n## 基因检测结果");
    payload.geneticFindings.forEach(f => {
      parts.push(`- **${f.traitLabel}**（${f.dimension}）：${f.plainMeaning ?? f.summary}。建议：${f.practicalAdvice ?? f.suggestion}`);
    });
  }

  if (payload.dimensionAnalyses.length > 0) {
    parts.push("\n## 各维度详细分析");
    payload.dimensionAnalyses.forEach(d => {
      parts.push(`### ${d.title}`);
      parts.push(`摘要：${d.summary}`);
      if (d.actionPlan.length > 0) {
        parts.push(`建议：${d.actionPlan.join("；")}`);
      }
    });
  }

  if (payload.sourceDimensions.length > 0) {
    parts.push("\n## 数据源维度");
    payload.sourceDimensions.forEach(d => {
      parts.push(`- ${d.label}：${d.summary}（${d.highlight}）`);
    });
  }

  if (payload.keyReminders.length > 0) {
    parts.push("\n## 关键提醒");
    payload.keyReminders.slice(0, 5).forEach(r => {
      parts.push(`- ${r.title}：${r.summary}`);
    });
  }

  parts.push(`\n## 最新日报摘要`);
  parts.push(`标题：${payload.latestNarrative.output.headline}`);
  parts.push(`优先行动：${payload.latestNarrative.output.priority_actions.join("；")}`);

  return parts.join("\n");
}

const SYSTEM_PROMPT = `你是一个专业的个人健康数据分析师。基于用户的完整健康数据，生成一份综合性的 AI 健康概览。

要求：
1. 必须基于实际数据：每个结论都引用具体数值和趋势，不要泛泛而谈
2. 覆盖所有维度：体检指标、血脂趋势、体重/体脂、运动/睡眠、基因背景
3. 使用中文回复
4. 返回纯 JSON 格式，不要任何 markdown、代码块或解释文字，只返回 JSON 本身
5. 每个 section 的 items 应是 2-4 条简洁的字符串（每条 50 字以内）
6. actionPlan 应包含 3-5 条具体行动建议

JSON 格式（直接输出此结构，不要添加其他文字）：
{"headline":"一句话总结（50字以内，引用关键数据）","summary":"2-3句话综合评估（150字以内）","sections":[{"title":"改善趋势","icon":"📈","items":["简洁描述"]},{"title":"重点关注","icon":"⚠️","items":["简洁描述"]},{"title":"基因与长期风险","icon":"🧬","items":["简洁描述"]},{"title":"生活方式评估","icon":"🏃","items":["简洁描述"]}],"actionPlan":["具体行动建议"]}`;

// ─── Direct LLM call (not via callLLMWithFallbacks, to avoid ECONNRESET issues) ─────
async function callKimiDirect(
  systemPrompt: string,
  userPrompt: string
): Promise<{ text: string; provider: string; model: string } | null> {
  const kimiKey = process.env.HEALTH_LLM_FALLBACK_KIMI_KEY;
  if (!kimiKey) return null;

  const model = process.env.HEALTH_LLM_FALLBACK_KIMI_MODEL ?? "kimi-latest";
  const isKimiKey = kimiKey.startsWith("sk-kimi-");
  const baseUrl = isKimiKey ? "https://api.kimi.com/coding/v1" : "https://api.moonshot.cn/v1";
  const headers: Record<string, string> = {
    "Content-Type": "application/json",
    Authorization: `Bearer ${kimiKey}`,
  };
  if (isKimiKey) headers["User-Agent"] = "KimiCLI/1.3";

  // Retry up to 2 times with back-off
  for (let attempt = 0; attempt < 2; attempt++) {
    try {
      const ctrl = new AbortController();
      const timer = setTimeout(() => ctrl.abort(), 45_000);

      const response = await fetch(`${baseUrl}/chat/completions`, {
        method: "POST",
        signal: ctrl.signal,
        headers,
        body: JSON.stringify({
          model,
          max_tokens: 2048,
          messages: [
            { role: "system", content: systemPrompt },
            { role: "user", content: userPrompt }
          ]
        })
      });
      clearTimeout(timer);

      if (!response.ok) throw new Error(`Kimi API ${response.status}`);

      const data = (await response.json()) as {
        choices?: Array<{ message?: { content?: string } }>;
        model?: string;
      };
      const text = data.choices?.[0]?.message?.content?.trim();
      if (text) return { text, provider: "kimi", model: data.model ?? model };

      // empty content — try next attempt
      console.warn(`[AI Overview] Kimi returned empty content, attempt ${attempt + 1}`);
    } catch (error) {
      const msg = error instanceof Error ? error.message : String(error);
      console.warn(`[AI Overview] Kimi attempt ${attempt + 1} failed: ${msg}`);
      if (attempt === 0) await new Promise(r => setTimeout(r, 2000)); // wait 2s before retry
    }
  }
  return null;
}

async function callAnthropicDirect(
  systemPrompt: string,
  userPrompt: string
): Promise<{ text: string; provider: string; model: string } | null> {
  const env = getAppEnv();
  if (env.HEALTH_LLM_PROVIDER !== "anthropic" || !env.HEALTH_LLM_API_KEY) return null;

  const model = env.HEALTH_LLM_MODEL ?? "claude-sonnet-4-20250514";

  try {
    const ctrl = new AbortController();
    const timer = setTimeout(() => ctrl.abort(), 45_000);

    const response = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      signal: ctrl.signal,
      headers: {
        "Content-Type": "application/json",
        "x-api-key": env.HEALTH_LLM_API_KEY,
        "anthropic-version": "2023-06-01"
      },
      body: JSON.stringify({
        model,
        max_tokens: 2048,
        system: systemPrompt,
        messages: [{ role: "user", content: userPrompt }]
      })
    });
    clearTimeout(timer);

    if (!response.ok) throw new Error(`Anthropic API ${response.status}`);

    const data = (await response.json()) as {
      content?: Array<{ type: string; text?: string }>;
      model?: string;
    };
    const text = data.content?.find(c => c.type === "text")?.text?.trim();
    if (text) return { text, provider: "anthropic", model: data.model ?? model };
  } catch (error) {
    const msg = error instanceof Error ? error.message : String(error);
    console.warn(`[AI Overview] Anthropic failed: ${msg}`);
  }
  return null;
}

function parseOverviewJSON(text: string): {
  headline?: string;
  summary?: string;
  sections?: AIOverviewSection[];
  actionPlan?: string[];
} | null {
  // Try multiple strategies to extract JSON
  const strategies = [
    // 1. Direct parse (text is pure JSON)
    text.trim(),
    // 2. Strip markdown code fences
    text.replace(/^```(?:json)?\s*/m, "").replace(/\s*```\s*$/m, "").trim(),
    // 3. Extract first JSON object between { and last }
    (() => {
      const start = text.indexOf("{");
      const end = text.lastIndexOf("}");
      return start >= 0 && end > start ? text.slice(start, end + 1) : "";
    })(),
  ];

  for (const candidate of strategies) {
    if (!candidate) continue;
    try {
      const parsed = JSON.parse(candidate);
      if (parsed && typeof parsed === "object" && (parsed.headline || parsed.summary || parsed.sections)) {
        return parsed;
      }
    } catch {
      // try next strategy
    }
  }
  return null;
}

/**
 * Generate an LLM-powered comprehensive health overview.
 * Uses caching (30 min TTL) and retry with fallback chain: Kimi → Anthropic → rule-based.
 */
export async function generateAIOverview(
  userId: string = "user-self",
  database: DatabaseSync = getDatabase()
): Promise<AIOverviewResult> {
  // Check cache first
  const cached = overviewCache.get(userId);
  if (cached && cached.expiresAt > Date.now()) {
    return { ...cached.result, cached: true };
  }

  const payload = await getHealthHomePageData(database, userId);
  const userProfile = buildUserProfileForLLM(payload);

  // Try Kimi first, then Anthropic
  let llmResult: { text: string; provider: string; model: string } | null = null;

  llmResult = await callKimiDirect(SYSTEM_PROMPT, userProfile);
  if (!llmResult) {
    llmResult = await callAnthropicDirect(SYSTEM_PROMPT, userProfile);
  }

  if (llmResult) {
    const parsed = parseOverviewJSON(llmResult.text);
    const result: AIOverviewResult = parsed
      ? {
          headline: parsed.headline ?? payload.overviewDigest.headline,
          summary: parsed.summary ?? payload.overviewDigest.summary,
          sections: parsed.sections ?? [],
          actionPlan: parsed.actionPlan ?? payload.overviewDigest.actionPlan,
          provider: llmResult.provider,
          model: llmResult.model,
          generatedAt: new Date().toISOString(),
          disclaimer: payload.disclaimer
        }
      : {
          headline: payload.overviewDigest.headline,
          summary: llmResult.text.slice(0, 500),
          sections: [
            {
              title: "AI 分析",
              icon: "🤖",
              items: llmResult.text.split("\n").filter(l => l.trim().length > 0).slice(0, 10)
            }
          ],
          actionPlan: payload.overviewDigest.actionPlan,
          provider: llmResult.provider,
          model: llmResult.model,
          generatedAt: new Date().toISOString(),
          disclaimer: payload.disclaimer
        };

    // Cache the successful result
    overviewCache.set(userId, { result, expiresAt: Date.now() + CACHE_TTL_MS });
    return result;
  }

  // All LLM providers failed — return rule-based fallback (no cache)
  return {
    headline: payload.overviewDigest.headline,
    summary: payload.overviewDigest.summary,
    sections: [
      { title: "改善趋势", icon: "📈", items: payload.overviewDigest.goodSignals },
      { title: "重点关注", icon: "⚠️", items: payload.overviewDigest.needsAttention },
      { title: "长期风险", icon: "🧬", items: payload.overviewDigest.longTermRisks }
    ],
    actionPlan: payload.overviewDigest.actionPlan,
    provider: "rule-based",
    model: "local-fallback",
    generatedAt: new Date().toISOString(),
    disclaimer: payload.disclaimer
  };
}
