import assert from "node:assert/strict";
import test from "node:test";

import { runPendingMigrations } from "../db/migration-runner";
import { seedDatabase } from "../db/seed";
import { createInMemoryDatabase } from "../db/sqlite";
import { getCoverageSummary } from "../repositories/health-repository";
import { getHealthHomePageData } from "./health-home-service";

test("health home service returns overview cards, charts and latest narrative", async () => {
  const database = createInMemoryDatabase();
  seedDatabase(database);
  runPendingMigrations(database);

  const data = await getHealthHomePageData(database, "user-self");

  assert.ok(data.overviewCards.length >= 10);
  assert.equal(data.sourceDimensions.length, 7);
  assert.ok(data.overviewHeadline.includes("年度体检"));
  assert.ok(data.overviewDigest.headline.length > 0);
  assert.ok(data.overviewDigest.summary.includes("运动与睡眠方面："));
  assert.ok(data.overviewDigest.summary.includes("饮食方面："));
  assert.ok(data.overviewDigest.goodSignals.length > 0);
  assert.ok(data.overviewDigest.needsAttention.length > 0);
  assert.ok(data.dimensionAnalyses.length >= 6);
  assert.ok(data.dimensionAnalyses.some((item) => item.key === "integrated"));
  assert.ok(data.dimensionAnalyses.some((item) => item.key === "activity_recovery"));
  assert.ok(data.dimensionAnalyses.some((item) => item.key === "diet"));
  assert.ok(data.importOptions.length === 6);
  assert.ok(data.charts.lipid.data.length > 0);
  assert.ok(data.charts.recovery.data.length > 0);
  assert.ok(data.charts.diet.data.length > 0);
  assert.ok(data.charts.activity.lines.some((line) => line.key === "activeEnergy"));
  assert.ok(data.charts.activity.lines.some((line) => line.key === "restingHeartRate"));
  assert.ok(data.charts.activity.lines.some((line) => line.key === "heartRateVariability"));
  assert.ok(data.charts.activity.lines.some((line) => line.key === "oxygenSaturation"));
  assert.equal(data.charts.activity.lines.some((line) => line.key === "activeKcal"), false);
  assert.ok(data.keyReminders.length > 0);
  assert.ok(data.keyReminders.some((item) => item.title.includes("体检") || item.title.includes("基因")));
  assert.ok(data.keyReminders.some((item) => typeof item.indicatorMeaning === "string"));
  assert.ok(data.keyReminders.some((item) => typeof item.practicalAdvice === "string"));
  assert.ok((data.annualExam?.latestTitle ?? "").length > 0);
  assert.ok(data.annualExam?.metrics.some((metric) => typeof metric.meaning === "string"));
  assert.ok((data.geneticFindings?.length ?? 0) >= 5);
  assert.ok(data.geneticFindings.some((item) => typeof item.plainMeaning === "string"));
  assert.ok(data.latestNarrative.output.priority_actions.length > 0);
  assert.ok(Array.isArray(data.latestReports));
});

test("health home service isolates multi-user genetic coverage and summary copy", async () => {
  const database = createInMemoryDatabase();
  seedDatabase(database);
  runPendingMigrations(database);

  database
    .prepare(`
      INSERT INTO users (id, display_name, sex, birth_year, height_cm, note)
      VALUES (?, ?, ?, ?, ?, ?)
    `)
    .run("user-guest", "访客账号", "female", 1992, 165, "用于验证多用户隔离");

  database
    .prepare(`
      INSERT INTO genetic_findings (
        id, user_id, source_id, gene_symbol, variant_id, trait_code, risk_level,
        evidence_level, summary, suggestion, recorded_at, raw_payload_json
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `)
    .run(
      "gene-guest-only",
      "user-guest",
      "source-gene-report",
      "TEST1",
      "rs-guest-only",
      "guest.unique_trait",
      "high",
      "A",
      "访客账号的专属基因结论。",
      "仅用于测试隔离。",
      "2026-03-19T10:00:00+08:00",
      JSON.stringify({ testOnly: true })
    );

  const selfCoverage = getCoverageSummary(database, "user-self");
  const guestCoverage = getCoverageSummary(database, "user-guest");

  assert.equal(selfCoverage.find((item) => item.kind === "genetic_panel")?.count, 6);
  assert.equal(guestCoverage.find((item) => item.kind === "genetic_panel")?.count, 1);

  const selfData = await getHealthHomePageData(database, "user-self");
  const guestData = await getHealthHomePageData(database, "user-guest");

  assert.ok(selfData.geneticFindings.every((item) => item.id !== "gene-guest-only"));
  assert.ok(guestData.geneticFindings.some((item) => item.id === "gene-guest-only"));
  assert.ok(
    guestData.overviewDigest.summary.includes("缺少") ||
      guestData.overviewDigest.summary.includes("积累") ||
      guestData.overviewDigest.summary.includes("基因") ||
      guestData.overviewDigest.summary.includes("优先处理")
  );
});
