import { LegalPage, buildLegalMetadata } from "../legal-page";
import { termsSections } from "../../../content/legal";

export const metadata = buildLegalMetadata(
  "用户协议",
  "了解 Health AI 的服务定位、使用方式、数据授权范围和用户责任。"
);

export default function TermsPage() {
  return (
    <LegalPage
      title="用户协议"
      subtitle="本协议用于说明你在使用 Health AI 时，应如何理解本服务的定位、功能边界和使用规则。"
      sections={termsSections}
    />
  );
}
