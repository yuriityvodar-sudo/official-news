// Google Analytics on the website, after the visitor's yes (Yurii, 28 Oct:
// one analytics place for the website and the app; the website is the web
// stream "Outer News website" of the app's Google Analytics property). Nothing
// from Google loads until the visitor taps OK: a small inline script
// shows the notice, keeps the answer in the browser (localStorage, no cookie
// of ours) and only then adds Google's tag. Pages stay one cached HTML for
// everyone; the choice is made in each browser.
//
// A cookie wall (Yurii, 30 Oct): on articles and lists the notice covers the
// page until the visitor accepts, with a general message and Details, the
// privacy policy, which names Google Analytics. On the information pages it is
// a bar at the bottom, so Details can be read before accepting.
import { type Html, html, raw } from "./html";
import { type SiteLang, t } from "./texts";
import { infoPath } from "./urls";

/** The web stream's Measurement ID (not a secret; docs/setup.md). */
export const GA_ID = "G-D0H8XW2SWJ";

const KEY = "outer-news-analytics";

/**
 * Cloudflare Web Analytics' site token for outernews.app (not a secret: it is
 * in every page; docs/setup.md). Its cookieless beacon counts every visit,
 * with no consent needed (#60). The page carries it itself: the beacon
 * Cloudflare injected by its automatic setup sent its reports to the site's own
 * `/cdn-cgi/rum`, which answered browsers 503, so nothing was ever counted
 * (checked in Chrome, 5 Nov); this one reports to cloudflareinsights.com,
 * which the Content-Security-Policy allows.
 */
export const CF_BEACON_TOKEN = "fb37b546b2f04316b704be572af32492";

/** Cloudflare's beacon, for every visitor (no cookies, nothing personal). */
const BEACON = `<script defer src="https://static.cloudflareinsights.com/beacon.min.js" data-cf-beacon='${JSON.stringify({ token: CF_BEACON_TOKEN })}'></script>`;

/**
 * Shows the notice until the visitor accepts (covering the page when it is a
 * wall); loads Google's tag after the yes, now and on later visits. Cookie
 * settings in the footer (`data-consent-reset`) withdraws: it forgets the yes,
 * deletes Google's `_ga*` cookies and reloads, so the notice asks again
 * (Roman's review of #240, GDPR Art. 7(3)). A click on an App Store button
 * (`data-store`, stores.ts) is the event `app_store_click` with its store and
 * channel, sent only when Google's tag is loaded, i.e. after the yes (#60).
 */
export const CONSENT_JS = `(function(){var k=${JSON.stringify(KEY)},id=${JSON.stringify(GA_ID)},r=document.documentElement;function load(){window.dataLayer=window.dataLayer||[];window.gtag=function(){window.dataLayer.push(arguments)};window.gtag("js",new Date());window.gtag("config",id);var s=document.createElement("script");s.async=true;s.src="https://www.googletagmanager.com/gtag/js?id="+id;document.head.appendChild(s)}document.addEventListener("click",function(e){var a=e.target.closest&&e.target.closest("[data-store]");if(a&&window.gtag)window.gtag("event","app_store_click",{store:a.getAttribute("data-store"),channel:a.getAttribute("data-channel")})});document.addEventListener("click",function(e){if(!e.target.closest||!e.target.closest("[data-consent-reset]"))return;try{localStorage.removeItem(k)}catch(x){}var h=location.hostname,d=["",h,"."+h,"."+h.split(".").slice(-2).join(".")];document.cookie.split(";").forEach(function(c){var n=c.split("=")[0].trim();if(n.indexOf("_ga")!==0)return;d.forEach(function(m){document.cookie=n+"=; Max-Age=0; path=/"+(m?"; domain="+m:"")})});location.reload()});var v=null;try{v=localStorage.getItem(k)}catch(e){}if(v==="yes"){load();return}var b=document.getElementById("consent");if(!b)return;b.hidden=false;if(b.hasAttribute("data-wall"))r.classList.add("walled");var y=b.querySelector("[data-consent]");if(!y)return;y.addEventListener("click",function(){try{localStorage.setItem(k,"yes")}catch(e){}b.hidden=true;r.classList.remove("walled");load()})})();`;

let scriptHash: Promise<string> | undefined;

/** `sha256-…` of CONSENT_JS, for the Content-Security-Policy; worked out once per Worker instance. */
export function consentHash(): Promise<string> {
  scriptHash ??= crypto.subtle.digest("SHA-256", new TextEncoder().encode(CONSENT_JS)).then((digest) => {
    let binary = "";
    for (const byte of new Uint8Array(digest)) binary += String.fromCharCode(byte);
    return `sha256-${btoa(binary)}`;
  });
  return scriptHash;
}

/**
 * The notice, hidden until the script shows it, then the script. `wall`
 * covers the page until OK (articles and lists); without it, a bar at the
 * bottom (the information pages, so Details can be read). Without JavaScript
 * it never shows and nothing loads. Cloudflare's cookieless beacon follows,
 * for every visitor.
 */
export const consent = (lang: SiteLang, wall: boolean): Html => html`<div class="consent" id="consent" role="dialog" aria-modal="${wall ? "true" : "false"}" aria-label="${t(lang, "consentTitle")}"${wall ? raw(" data-wall") : ""} hidden><div class="consent-card">
<p>${t(lang, "consentText")}</p>
<div class="consent-buttons"><button type="button" class="yes" data-consent="yes">${t(lang, "consentYes")}</button><a href="${infoPath(lang, "privacy")}">${t(lang, "consentDetails")}</a></div>
</div></div>
<script>${raw(CONSENT_JS)}</script>
${raw(BEACON)}`;
