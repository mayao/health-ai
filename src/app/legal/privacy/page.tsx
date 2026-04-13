import { LegalPage, buildLegalMetadata } from "../legal-page";
import { legalMeta, privacySections } from "../../../content/legal";

export const metadata = buildLegalMetadata(
  "隐私政策",
  "了解 Health AI 如何处理账号信息、健康数据、上传内容以及隐私申请。"
);

export default function PrivacyPolicyPage() {
  return (
    <LegalPage
      title="隐私政策"
      subtitle="本政策用于说明 Health AI 团队在你使用 Health AI 时，如何处理与你相关的个人信息和健康数据。"
      sections={privacySections}
      footer={
        <p style={{ lineHeight: 1.8, color: "var(--muted)" }}>
          如需提交访问、导出、更正或删除数据申请，请发送邮件至{" "}
          <a href={`mailto:${legalMeta.supportEmail}`} style={{ color: "var(--brand-deep)", textDecoration: "underline" }}>
            {legalMeta.supportEmail}
          </a>
          ，并尽量附上你的账号信息和申请内容。
        </p>
      }
    />
  );
}
