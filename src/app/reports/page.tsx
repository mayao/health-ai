import { headers } from "next/headers";

import { ReportCard } from "../../components/report-card";
import { SiteHeader } from "../../components/site-header";
import { AuthError, getAuthenticatedUserIdFromHeaders } from "../../server/http/auth-middleware";
import { getReportsIndexData } from "../../server/services/report-service";

export const dynamic = "force-dynamic";

export default async function ReportsPage() {
  try {
    const userId = getAuthenticatedUserIdFromHeaders(await headers());
    const reports = await getReportsIndexData(undefined, userId);

    return (
      <main className="app-shell">
        <SiteHeader generatedAt={reports.generatedAt} />

        <section className="hero-banner">
          <div className="hero-copy">
            <p className="panel-kicker">Reports</p>
            <h2>把结构化分析和 LLM 洞察整理成可浏览的健康经营报告。</h2>
            <p>
              周报强调本周变化、风险提示和下周最优先动作，月报强调趋势、改善/恶化排行和联动发现。
            </p>
          </div>
        </section>

        <section className="reports-grid">
          <section className="panel-card">
            <div className="panel-head">
              <div>
                <p className="panel-kicker">Weekly</p>
                <h2>周报历史</h2>
                <p className="panel-description">默认保留最近几期周报快照，支持继续扩展 PDF 导出。</p>
              </div>
            </div>
            <div className="stack-list">
              {reports.weeklyReports.map((report) => (
                <ReportCard key={report.id} report={report} />
              ))}
            </div>
          </section>

          <section className="panel-card">
            <div className="panel-head">
              <div>
                <p className="panel-kicker">Monthly</p>
                <h2>月报历史</h2>
                <p className="panel-description">月报更适合看趋势延续性、联动发现和行动优先级。</p>
              </div>
            </div>
            <div className="stack-list">
              {reports.monthlyReports.map((report) => (
                <ReportCard key={report.id} report={report} />
              ))}
            </div>
          </section>
        </section>
      </main>
    );
  } catch (error) {
    if (!(error instanceof AuthError)) {
      throw error;
    }

    return (
      <main className="app-shell">
        <SiteHeader />
        <section className="panel-card">
          <div className="panel-head">
            <div>
              <p className="panel-kicker">Protected</p>
              <h2>报告页需要登录后访问</h2>
              <p className="panel-description">
                为避免误读到共享账号数据，Web 报告页现在只会在带鉴权上下文时加载真实内容。
              </p>
            </div>
          </div>
        </section>
      </main>
    );
  }
}
