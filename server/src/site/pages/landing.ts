// `/` (#88): one fixed page in English that leads to each language's list. It
// never looks at Accept-Language (the cache key has no headers) and never
// redirects, and it reads nothing from D1.
import { html } from "../html";
import { type Page, SITE_NAME } from "../layout";
import { LANGUAGE_NAMES, SITE_LANGS, t } from "../texts";
import { listPath } from "../urls";

export function landingPage(origin: string): Page {
  const lang = "en";
  return {
    lang,
    kind: "landing",
    title: SITE_NAME,
    canonical: `${origin}/`,
    switcher: [],
    body: html`<div class="info"><h1 class="page-title">${SITE_NAME}</h1>
<p>${t(lang, "aboutIntro")}</p>
<ul class="choose">${SITE_LANGS.map(
      (l) =>
        html`<li><a href="${listPath(l)}" hreflang="${l}" lang="${l}"><span>${t(l, "latestLink")}</span><span class="meta">${LANGUAGE_NAMES[l].nativeName}</span></a></li>`,
    )}</ul></div>`,
  };
}
