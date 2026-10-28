// The page around every page of the site (#88): one HTML document with its
// CSS and icons inline, so a page view is one Worker request (LyFi lesson 2):
// no stylesheet, script, font or image to fetch, and the data: icon stops the
// browser's automatic /favicon.ico request. Colours and the serif from the
// app's theme (app/lib/core/theme.dart: Georgia, not the system's New York),
// light and dark; if #66 changes the app's font, change it here too.
import { type Html, html, raw } from "./html";
import { TAB_ICON } from "./icon";
import { LANGUAGE_NAMES, type SiteLang, publisher, t, text } from "./texts";
import { INFO_PAGES, type InfoPage, infoPath, listPath } from "./urls";

/** The App Store app (docs/setup.md); Safari shows its Smart App Banner. */
export const APP_STORE_ID = "6822820350";

export const SITE_NAME = "Outer News";

// Headings hyphenate only long words (12+ characters in Chrome, 5 on each
// side in WebKit, which has no word minimum): "Datenschutzer-klärung" instead
// of a break with no hyphen, but no hyphen in every other line of a headline.
// Red small text on white is #D1102F (about 5.5:1), not the app's #FA2D48
// (about 3.8:1, under WCAG AA); in dark mode the app's red on black.
// The filter chips are the app's (feed_filters.dart, after the prototype's
// review, 16 Oct): iOS's tertiarySystemFill on the page (`--fill`, #EFEFF0 on
// white, #1C1C1F on black). One that is on stays that chip, its short label
// or icon and chevron in the app's filterRed (`--on`): #C41230 light (about
// 5.2:1 on the chip), #FF3B55 dark (about 4.85:1; on the lighter #2C2C2E of
// `--chip`, the article's country tile, it would be 4.0:1, under AA for 15px
// text), also the menus' checkmark. `.vh` keeps the full name for screen readers. A filter menu
// (pages/filters.ts) opens over the list, under the chips, so neither chip
// moves (#89 review): on a phone the row's full width, from 720px under its
// own chip, 320px wide; the page scrolls as usual to a long one. A
// transparent backdrop (the open chip's ::before) closes it on a click
// outside, without a script, and it hides while keyboard focus is in the
// page outside the filter bar (Tab past the menu), so it never covers it.
export const CSS = `:root{color-scheme:light dark;--bg:#fff;--text:#000;--secondary:#6c6c70;--separator:#e5e5ea;--accent:#d1102f;--chip:#e3e8ef;--card:#f2f2f7;--verified:#1a8cff;--fill:rgba(118,118,128,.12);--on:#c41230;--menu:#fff;--band:#f2f2f7;--shadow:rgba(0,0,0,.16)}
@media (prefers-color-scheme:dark){:root{--bg:#000;--text:#fff;--secondary:#98989f;--separator:#38383a;--accent:#fa2d48;--fill:rgba(118,118,128,.24);--on:#ff3b55;--chip:#2c2c2e;--card:#1c1c1e;--menu:#1c1c1e;--band:#000;--shadow:rgba(0,0,0,.6)}}
*{box-sizing:border-box}
html{-webkit-text-size-adjust:100%;text-size-adjust:100%}
body{margin:0;display:flex;flex-direction:column;min-height:100vh;min-height:100dvh;background:var(--bg);color:var(--text);font:16px/1.45 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,"Helvetica Neue",Arial,sans-serif;overflow-wrap:break-word}
a{color:var(--accent)}
a:focus-visible{outline:2px solid var(--accent);outline-offset:2px;border-radius:4px}
.wrap{max-width:680px;margin:0 auto;padding:0 16px}
.skip{position:absolute;left:-9999px;top:8px;background:var(--bg);color:var(--text);padding:10px 14px;border-radius:8px;z-index:1}
.skip:focus{left:16px}
.serif,h1,.lead,.body,.item .title{font-family:Georgia,"Times New Roman",serif}
h1,h2,.item .title{-webkit-hyphens:auto;hyphens:auto;hyphenate-limit-chars:12 5 5;-webkit-hyphenate-limit-before:5;-webkit-hyphenate-limit-after:5}
.top{border-bottom:.5px solid var(--separator);padding:4px 0 10px}
.bar{display:flex;align-items:center;justify-content:space-between;flex-wrap:wrap;column-gap:12px}
.brand{display:inline-flex;align-items:center;gap:8px;min-height:44px;font:700 20px/1.1 Georgia,"Times New Roman",serif;color:var(--text);text-decoration:none}

.langs{display:flex;flex-wrap:wrap;margin-right:-10px}
.langs a{display:inline-flex;align-items:center;justify-content:center;min-width:44px;min-height:44px;padding:0 6px;font-size:13px;font-weight:600;letter-spacing:.3px;color:var(--secondary);text-decoration:none}
.langs a[aria-current]{color:var(--text);text-decoration:underline 2px var(--accent);text-underline-offset:6px}
.note{margin:0;font-size:13px;color:var(--secondary)}
main{padding:20px 0 28px}
.meta{font-size:14px;color:var(--secondary)}
.publisher{display:flex;align-items:center;gap:12px;margin:0 0 18px}
.cc{flex:none;display:grid;place-items:center;width:40px;height:40px;border-radius:10px;background:var(--chip);color:var(--text);font-size:14px;font-weight:700;letter-spacing:.5px}
.publisher b{display:block;font-size:14px;font-weight:600}
.seal{width:15px;height:15px;vertical-align:-3px;color:var(--verified)}
.kind{margin:0 0 4px;font-size:13px;font-weight:700;letter-spacing:.8px;text-transform:uppercase;color:var(--accent)}
h1{margin:0 0 10px;font-size:31px;line-height:1.15;font-weight:700}
.ai{display:flex;align-items:center;gap:6px;margin:0 0 4px}
.ai svg{width:15px;height:15px;flex:none}
.lead{margin:20px 0 14px;font-size:20px;line-height:1.45;color:var(--secondary)}
.body p{margin:0 0 14px;font-size:19px;line-height:1.5}
.notice{margin:18px 0;padding:14px 16px;border-radius:12px;background:var(--card);font-size:14px;color:var(--secondary)}
.official{display:flex;align-items:center;justify-content:space-between;gap:10px;min-height:44px;margin:18px 0;padding:14px 14px 14px 16px;border:1px solid var(--separator);border-radius:14px;color:var(--text);text-decoration:none}
.official b{display:block;font-size:14px;font-weight:600}
.official svg{width:24px;height:24px;flex:none;color:var(--accent)}
.small{margin:0 0 6px;font-size:13px;color:var(--secondary)}
.small a{color:inherit}
.page-title{margin:0 0 4px;font-size:34px;font-weight:800;line-height:1.1}
.section{margin:26px 0 0;font-size:22px;font-weight:800;color:var(--accent)}
.filters{position:relative;display:flex;flex-wrap:wrap;gap:0 8px;margin:8px 0 0}
.pick>summary{display:flex;align-items:center;min-height:44px;list-style:none;cursor:pointer;border-radius:18px}
.pick>summary::-webkit-details-marker{display:none}
.pick>summary:focus-visible{outline:2px solid var(--accent);outline-offset:2px}
.chip-link{display:inline-flex;align-items:center;max-width:100%;min-height:44px;text-decoration:none;border-radius:18px}
.chip-link:focus-visible{border-radius:18px}
.chip{display:inline-flex;align-items:center;gap:6px;max-width:100%;min-height:34px;padding:0 12px;border-radius:17px;background:var(--fill);color:var(--text);font-size:15px;font-weight:600}
.chip.on{color:var(--on)}
.chip svg{flex:none}
.chip .glyph{display:block;width:18px;height:18px}
.chip .chev{width:12px;height:12px;margin-left:-2px}
.chip .label{overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.vh{position:absolute;width:1px;height:1px;margin:-1px;padding:0;overflow:hidden;clip:rect(0 0 0 0);clip-path:inset(50%);white-space:nowrap;border:0}
.pick[open] .chev{transform:rotate(180deg)}
.menu{position:absolute;z-index:2;left:0;right:0;top:100%;padding:6px 0;background:var(--menu);border:.5px solid var(--separator);border-radius:14px;box-shadow:0 10px 30px var(--shadow)}
.pick[open]>summary::before{content:"";position:fixed;inset:0;z-index:1;cursor:default}
body:has(main :focus-visible:not(.filters *),footer :focus-visible) .pick[open] .menu{display:none}
.menu ul{list-style:none;margin:0;padding:0}
.menu ul+ul{border-top:6px solid var(--band)}
.menu li+li{border-top:.5px solid var(--separator)}
.menu a{display:flex;align-items:center;gap:12px;min-height:44px;padding:8px 16px;color:var(--text);text-decoration:none;font-size:16px}
.menu a>span:not(.glyph){flex:1}
.menu .glyph{display:block;width:18px;height:18px;flex:none;color:var(--secondary)}
.menu a:hover{background:var(--card)}
.menu a:focus-visible{outline-offset:-2px}
.menu .check{width:18px;height:18px;flex:none;color:var(--on)}
.items{list-style:none;margin:0;padding:0}
.item{padding:14px 0;border-bottom:.5px solid var(--separator)}
.item .kind{margin-bottom:2px}
.item .title{display:block;font-size:21px;line-height:1.2;font-weight:700;color:var(--text);text-decoration:none}
.item .title:hover{text-decoration:underline}
.item p{margin:6px 0 4px}
.more{display:inline-flex;align-items:center;min-height:44px;margin-top:8px;font-weight:600}
.info h2{margin:24px 0 6px;font-size:17px;font-weight:600}
.info p,.info li{font-size:16px;line-height:1.5}
.info p{margin:0 0 12px}
.choose{list-style:none;margin:16px 0;padding:0}
.choose li{border-bottom:.5px solid var(--separator)}
.choose a{display:flex;justify-content:space-between;gap:12px;min-height:48px;align-items:center;color:var(--text);text-decoration:none;font-weight:600}
main{flex:1 0 auto}
footer{border-top:.5px solid var(--separator);padding:8px 0 40px;font-size:13px;color:var(--secondary)}
footer nav{display:flex;flex-wrap:wrap;column-gap:18px}
footer nav a{display:inline-flex;align-items:center;min-height:44px;color:var(--text);text-decoration:none}
footer p{margin:8px 0 0}
.leadstory .title{display:block;font:700 30px/1.15 Georgia,"Times New Roman",serif;color:var(--text);text-decoration:none}
.leadstory .title:hover{text-decoration:underline}
.leadstory .dek{margin:14px 0 8px;font-size:17px;line-height:1.5}
.front{margin-top:18px}
.latest-head{display:flex;align-items:baseline;justify-content:space-between;gap:12px;margin-top:26px}
.latest-head .section{margin:0;font-family:Georgia,"Times New Roman",serif}
.row{display:grid;grid-template-columns:52px 1fr;column-gap:12px}
.row .when{padding-top:2px;font-size:14px;color:var(--secondary);font-variant-numeric:tabular-nums}
.row .title{font-size:18px}
.front .title,.cards .title,.more-rows .title{-webkit-hyphens:manual;hyphens:manual;text-wrap:balance}
.more-rows{margin-top:28px}
.front .title,.cards .title{-webkit-hyphens:manual;hyphens:manual;text-wrap:balance}
.row .meta{margin:6px 0 0;font-size:13px}
.cards{list-style:none;margin:28px 0 0;padding:0;display:grid;gap:14px}
.card{display:flex;flex-direction:column;padding:20px 22px;border-radius:16px;background:var(--card)}
.card .kind{margin-bottom:6px}
.card .title{display:block;font:700 20px/1.25 Georgia,"Times New Roman",serif;color:var(--text);text-decoration:none}
.card .title:hover{text-decoration:underline}
.card .dek{margin:12px 0 0;font-size:15px;line-height:1.5}
.card .meta{margin:auto 0 0;padding-top:18px;font-size:13px}
@media (min-width:720px){h1{font-size:36px}.page-title{font-size:40px}.pick{position:relative}.menu{right:auto;width:320px}}
@media (min-width:960px){body:has(.front) .wrap{max-width:1120px;padding:0 32px}.top .wrap{display:flex;flex-wrap:wrap;align-items:center;column-gap:16px}.top .bar{display:contents}.top .brand{order:1}.top .note{order:2}.top .langs{order:3;margin-left:auto}.front-head{display:flex;align-items:center;justify-content:space-between;gap:24px;padding-bottom:18px;border-bottom:.5px solid var(--separator)}.front-head .filters{margin:0;flex:none}.page-title{font-size:56px}.front{display:grid;grid-template-columns:minmax(0,1.25fr) minmax(0,1fr);column-gap:48px;margin-top:24px}.leadstory .title{font-size:44px;line-height:1.1}.leadstory .dek{font-size:18px}.latest-head{margin-top:0}.cards{grid-template-columns:repeat(3,minmax(0,1fr));margin-top:40px}.card.wide{grid-column:span 2}.card.wide .title{font-size:30px;line-height:1.15}.card{min-height:200px}.more-rows{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));column-gap:48px;margin-top:36px}}
@media (min-width:720px) and (max-width:959px){.cards{grid-template-columns:repeat(2,minmax(0,1fr))}.card.wide{grid-column:span 2}}`;

let styleHash: Promise<string> | undefined;

/** `sha256-…` of CSS, for the Content-Security-Policy; worked out once per Worker instance. */
export function cssHash(): Promise<string> {
  styleHash ??= crypto.subtle.digest("SHA-256", new TextEncoder().encode(CSS)).then((digest) => {
    let binary = "";
    for (const byte of new Uint8Array(digest)) binary += String.fromCharCode(byte);
    return `sha256-${btoa(binary)}`;
  });
  return styleHash;
}

/** Our own mark: a building with columns, in the app's red. Never a source's picture. */
export const SEAL = raw(
  `<svg class="seal" viewBox="0 0 16 16" aria-hidden="true"><circle cx="8" cy="8" r="7" fill="currentColor"/><path d="M4.8 8.2 7 10.4l4.2-4.6" fill="none" stroke="#fff" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/></svg>`,
);
export const SPARKLE = raw(
  `<svg viewBox="0 0 16 16" fill="currentColor" aria-hidden="true"><path d="M7 1.5 8.3 5.2 12 6.5 8.3 7.8 7 11.5 5.7 7.8 2 6.5l3.7-1.3z"/><path d="M12.5 10l.6 1.4 1.4.6-1.4.6-.6 1.4-.6-1.4-1.4-.6 1.4-.6z"/></svg>`,
);
export const ARROW = raw(
  `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M14 4h6v6"/><path d="M20 4 11 13"/><path d="M19 14v5a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V6a1 1 0 0 1 1-1h5"/></svg>`,
);

export interface Alternate {
  /** A language code, or `x-default`. */
  hreflang: string;
  href: string;
}

export interface Page {
  lang: SiteLang;
  /** Which page, for robotsFor(). */
  kind: string;
  title: string;
  /** For link previews when it differs from the title: an article's headline with the AI label. */
  ogTitle?: string;
  description?: string;
  /** Absolute URLs from SITE_ORIGIN. */
  canonical?: string;
  alternates?: Alternate[];
  /** The language switcher: the languages this page exists in, with their paths. */
  switcher: { lang: SiteLang; path: string }[];
  ogType?: "article" | "website";
  body: Html;
}

const footer = (lang: SiteLang) => {
  const names: Record<InfoPage, string> = {
    about: text(lang, "aboutTitle"),
    privacy: text(lang, "privacyPolicy"),
    terms: text(lang, "termsOfUse"),
    support: text(lang, "contactSupport"),
  };
  return html`<footer><div class="wrap">
<nav aria-label="${SITE_NAME}">${INFO_PAGES.map((page) => html`<a href="${infoPath(lang, page)}">${names[page]}</a>`)}</nav>
<p>${t(lang, "aboutPublishedBy", { publisher: publisher(lang) })}</p>
</div></footer>`;
};

/** The whole document; `robots` is the page's robotsFor(), also sent as X-Robots-Tag. Error pages pass no canonical and no alternates. */
export function layout(page: Page, robots: string): Html {
  const { lang } = page;
  const description = page.description ?? text(lang, "aboutIntro");
  // The link preview's picture needs an absolute URL: the canonical's origin (error pages have none).
  const origin = page.canonical ? new URL(page.canonical).origin : "";
  const switcher = page.switcher.length
    ? html`<nav class="langs" aria-label="${text(lang, "language")}">${page.switcher.map(
        (item) =>
          html`<a href="${item.path}" hreflang="${item.lang}" lang="${item.lang}" title="${LANGUAGE_NAMES[item.lang].nativeName}"${
            item.lang === lang ? raw(' aria-current="true"') : ""
          }>${LANGUAGE_NAMES[item.lang].shortLabel}</a>`,
      )}</nav>`
    : "";
  return html`<!doctype html>
<html lang="${lang}" dir="ltr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${page.title}</title>
<meta name="description" content="${description}">
<meta name="robots" content="${robots}">
${page.canonical ? html`<link rel="canonical" href="${page.canonical}">\n` : ""}${(page.alternates ?? []).map(
    (a) => html`<link rel="alternate" hreflang="${a.hreflang}" href="${a.href}">\n`,
  )}<meta property="og:site_name" content="${SITE_NAME}">
<meta property="og:title" content="${page.ogTitle ?? page.title}">
<meta property="og:description" content="${description}">
<meta property="og:type" content="${page.ogType ?? "website"}">
${page.canonical ? html`<meta property="og:url" content="${page.canonical}">\n` : ""}${origin ? html`<meta property="og:image" content="${origin}/icon-512.png">\n<meta property="og:image:width" content="512">\n<meta property="og:image:height" content="512">\n` : ""}<meta name="twitter:card" content="summary">
<meta name="apple-itunes-app" content="app-id=${APP_STORE_ID}">
<meta name="color-scheme" content="light dark">
<meta name="theme-color" content="#ffffff" media="(prefers-color-scheme: light)">
<meta name="theme-color" content="#000000" media="(prefers-color-scheme: dark)">
<link rel="icon" href="${TAB_ICON}" type="image/png">
<link rel="apple-touch-icon" href="/apple-touch-icon.png">
<style>${raw(CSS)}</style>
</head>
<body>
<a class="skip" href="#main">${t(lang, "skip")}</a>
<header class="top"><div class="wrap">
<div class="bar"><a class="brand" href="${listPath(lang)}"><span>${SITE_NAME}</span></a>${switcher}</div>
<p class="note">${t(lang, "independentNote")}</p>
</div></header>
<main id="main"><div class="wrap">
${page.body}
</div></main>
${footer(lang)}
</body>
</html>
`;
}
