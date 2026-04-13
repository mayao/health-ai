import type { Metadata } from "next";
import type { ReactNode } from "react";

import { legalMeta, type LegalSection } from "../../content/legal";

export function buildLegalMetadata(
  title: string,
  description: string
): Metadata {
  return {
    title: `${title} | ${legalMeta.appName}`,
    description
  };
}

export function LegalPage({
  title,
  subtitle,
  sections,
  footer
}: {
  title: string;
  subtitle: string;
  sections: LegalSection[];
  footer?: ReactNode;
}) {
  return (
    <main className="app-shell" style={{ maxWidth: 960 }}>
      <article
        className="panel-card"
        style={{
          padding: 32,
          borderRadius: 28,
          display: "grid",
          gap: 22
        }}
      >
        <header style={{ display: "grid", gap: 10 }}>
          <span className="site-kicker">{legalMeta.appName}</span>
          <h1 style={{ fontSize: "clamp(2rem, 4vw, 3.2rem)", letterSpacing: "-0.04em" }}>{title}</h1>
          <p className="panel-description" style={{ lineHeight: 1.8 }}>
            {subtitle}
          </p>
          <p className="site-timestamp">生效日期：{legalMeta.effectiveDate}</p>
        </header>

        {sections.map((section) => (
          <section
            key={section.title}
            style={{
              padding: 24,
              borderRadius: 22,
              background: "var(--surface-soft)",
              border: "1px solid var(--line)",
              display: "grid",
              gap: 12
            }}
          >
            <h2 style={{ fontSize: "1.2rem" }}>{section.title}</h2>
            {section.paragraphs.map((paragraph) => (
              <p key={paragraph} style={{ lineHeight: 1.9, color: "var(--muted)" }}>
                {paragraph}
              </p>
            ))}
            {section.bullets?.length ? (
              <ul style={{ display: "grid", gap: 8, color: "var(--muted)" }}>
                {section.bullets.map((bullet) => (
                  <li key={bullet} style={{ lineHeight: 1.8 }}>
                    {bullet}
                  </li>
                ))}
              </ul>
            ) : null}
          </section>
        ))}

        <footer
          style={{
            padding: 24,
            borderRadius: 22,
            background: "rgba(15, 118, 110, 0.08)",
            border: "1px solid rgba(15, 118, 110, 0.12)",
            display: "grid",
            gap: 10
          }}
        >
          <h2 style={{ fontSize: "1.1rem" }}>联系 {legalMeta.teamName}</h2>
          <p style={{ lineHeight: 1.8, color: "var(--muted)" }}>
            如果你对本页面内容、账号使用或隐私申请有疑问，可以通过邮箱联系我们：{" "}
            <a href={`mailto:${legalMeta.supportEmail}`} style={{ color: "var(--brand-deep)", textDecoration: "underline" }}>
              {legalMeta.supportEmail}
            </a>
            。
          </p>
          {footer}
        </footer>
      </article>
    </main>
  );
}
