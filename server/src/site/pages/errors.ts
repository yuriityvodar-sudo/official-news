// 404 and 500 pages (#88). They never repeat the address that was asked for.
import { html } from "../html";
import { type Page, SITE_NAME } from "../layout";
import { type SiteLang, t, text } from "../texts";
import { listPath } from "../urls";

export function notFoundPage(lang: SiteLang): Page {
  return {
    lang,
    kind: "not-found",
    title: `${text(lang, "notFound")} · ${SITE_NAME}`,
    switcher: [],
    body: html`<div class="info"><h1 class="page-title">${t(lang, "notFound")}</h1>
<p><a href="${listPath(lang)}">${t(lang, "latestLink")}</a></p></div>`,
  };
}

export function errorPage(lang: SiteLang): Page {
  return {
    lang,
    kind: "error",
    title: `${text(lang, "error")} · ${SITE_NAME}`,
    switcher: [],
    body: html`<div class="info"><h1 class="page-title">${t(lang, "error")}</h1>
<p>${t(lang, "errorText")}</p>
<p><a href="${listPath(lang)}">${t(lang, "latestLink")}</a></p></div>`,
  };
}
