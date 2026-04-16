import { headers } from "next/headers";
import Link from "next/link";
import { notFound } from "next/navigation";

import { ReportDetail } from "../../../components/report-detail";
import { SiteHeader } from "../../../components/site-header";
import { AuthError, getAuthenticatedUserIdFromHeaders } from "../../../server/http/auth-middleware";
import { getReportSnapshotDetail } from "../../../server/services/report-service";

export const dynamic = "force-dynamic";

export default async function ReportDetailPage({
  params
}: {
  params: Promise<{ snapshotId: string }>;
}) {
  const { snapshotId } = await params;
  let report;

  try {
    const userId = getAuthenticatedUserIdFromHeaders(await headers());
    report = await getReportSnapshotDetail(decodeURIComponent(snapshotId), undefined, userId);
  } catch (error) {
    if (error instanceof AuthError) {
      return (
        <main className="app-shell">
          <SiteHeader />
          <section className="panel-card">
            <div className="panel-head">
              <div>
                <p className="panel-kicker">Protected</p>
                <h2>报告详情需要登录后访问</h2>
                <p className="panel-description">
                  为避免跨用户误读，此页面在没有鉴权上下文时不会直接加载真实报告。
                </p>
              </div>
            </div>
          </section>
        </main>
      );
    }

    throw error;
  }

  if (!report) {
    notFound();
  }

  return (
    <main className="app-shell">
      <SiteHeader generatedAt={report.createdAt} />
      <div className="back-link-row">
        <Link href="/reports" className="report-link">
          返回报告列表
        </Link>
      </div>
      <ReportDetail report={report} />
    </main>
  );
}
