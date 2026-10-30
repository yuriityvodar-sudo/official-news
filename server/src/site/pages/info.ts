// About, Privacy Policy, Terms of Use and Contact & Support (#88): the app's
// own pages (info_pages.dart), with their texts from its ARB files, in all five
// languages, plus what only the website needs to say about itself.
import { POLICY_UPDATED, SUPPORT_EMAIL } from "../app-texts.generated";
import { fullDate } from "../dates";
import { type Html, html } from "../html";
import { type Page, SITE_NAME } from "../layout";
import { SITE_LANGS, type SiteLang, type TextKey, publisher, publisherDetails, t, text } from "../texts";
import { type InfoPage, infoPath } from "../urls";

interface Section {
  heading?: TextKey;
  paragraphs: Html[];
}

const p = (lang: SiteLang, key: TextKey) => t(lang, key);

function sections(lang: SiteLang, page: InfoPage): Section[] {
  const by = publisher(lang);
  switch (page) {
    case "about":
      return [
        { paragraphs: [p(lang, "aboutIntro")] },
        { heading: "aboutSourcesHeading", paragraphs: [p(lang, "aboutSources1"), p(lang, "aboutSources2")] },
        { heading: "aboutIndependentHeading", paragraphs: [p(lang, "aboutIndependent"), t(lang, "aboutPublishedBy", { publisher: by })] },
      ];
    case "privacy":
      return [
        { paragraphs: [p(lang, "privacyIntro")] },
        { heading: "privacyPhoneHeading", paragraphs: [p(lang, "privacyPhone")] },
        {
          heading: "privacyLoadingHeading",
          paragraphs: [p(lang, "privacyLoadingServer"), p(lang, "privacyLoadingCountry"), p(lang, "privacyLoadingPictures"), p(lang, "privacyLoadingPages")],
        },
        { heading: "privacyAnalyticsHeading", paragraphs: [p(lang, "privacyAnalytics")] },
        { heading: "privacyNotificationsHeading", paragraphs: [p(lang, "privacyNotifications")] },
        { heading: "privacyAiHeading", paragraphs: [p(lang, "privacyAi")] },
        { heading: "privacyChatHeading", paragraphs: [p(lang, "privacyChat")] },
        { heading: "privacySupportHeading", paragraphs: [p(lang, "privacySupport")] },
        // The website's own part: the ARB texts describe the app.
        {
          heading: "siteHeading",
          paragraphs: [p(lang, "siteData"), p(lang, "siteBanner")],
        },
        {
          heading: "privacyRightsHeading",
          paragraphs: [
            t(lang, "privacyRights", { contactSupport: html`<a href="${infoPath(lang, "support")}">${text(lang, "contactSupport")}</a>` }),
            t(lang, "privacyController", { publisher: publisherDetails(lang) }),
          ],
        },
        { heading: "privacyChangesHeading", paragraphs: [p(lang, "privacyChanges")] },
      ];
    case "terms":
      return [
        { paragraphs: [p(lang, "termsIntro1"), p(lang, "termsIntro2")] },
        { heading: "termsContentHeading", paragraphs: [p(lang, "termsContent")] },
        { heading: "termsNoGuaranteeHeading", paragraphs: [p(lang, "termsNoGuarantee")] },
        { heading: "termsSubscriptionHeading", paragraphs: [p(lang, "termsSubscription")] },
        { heading: "termsPublisherHeading", paragraphs: [t(lang, "termsPublisher", { publisher: publisherDetails(lang) })] },
      ];
    case "support":
      // The app writes to us from its own screen (#220); the website gives the e-mail (supportEmail in info_pages.dart).
      return [
        {
          paragraphs: [
            p(lang, "supportMessages"),
            p(lang, "supportMistakes"),
            t(lang, "emailUs", { email: html`<a href="mailto:${SUPPORT_EMAIL}">${SUPPORT_EMAIL}</a>` }),
          ],
        },
      ];
  }
}

const TITLES: Record<InfoPage, TextKey> = { about: "aboutTitle", privacy: "privacyPolicy", terms: "termsOfUse", support: "contactSupport" };

/** The policies' header: their date, that they cover this website, and on a translation that the English one prevails. */
function policyHeader(lang: SiteLang, page: InfoPage): Html {
  const english = html`<a href="${infoPath("en", page)}" hreflang="en" lang="en">English</a>`;
  return html`<p class="meta">${t(lang, "lastUpdated", { date: fullDate(lang, new Date(`${POLICY_UPDATED}T12:00:00Z`)) })}</p>
<p>${t(lang, "siteCovers")}</p>
${lang === "en" ? "" : html`<p>${t(lang, "prevails", { link: english })}</p>`}`;
}

export function infoPage(lang: SiteLang, origin: string, page: InfoPage): Page {
  const body = html`<div class="info"><h1 class="page-title">${t(lang, TITLES[page])}</h1>
${page === "privacy" || page === "terms" ? policyHeader(lang, page) : ""}
${sections(lang, page).map(
  (s) => html`${s.heading ? html`<h2>${t(lang, s.heading)}</h2>` : ""}
${s.paragraphs.map((para) => html`<p>${para}</p>`)}
`,
)}</div>`;
  return {
    lang,
    kind: page,
    title: `${text(lang, TITLES[page])} · ${SITE_NAME}`,
    canonical: origin + infoPath(lang, page),
    alternates: [
      ...SITE_LANGS.map((l) => ({ hreflang: l, href: origin + infoPath(l, page) })),
      { hreflang: "x-default", href: origin + infoPath("en", page) },
    ],
    switcher: SITE_LANGS.map((l) => ({ lang: l, path: infoPath(l, page) })),
    body,
  };
}
