// Google Analytics on the website, only with the visitor's yes (Yurii, 28 Oct:
// one analytics place for the website and the app; the website is the web
// stream "Outer News website" of the app's Google Analytics property). Nothing
// from Google loads until the visitor taps Accept: a small inline script
// shows the banner, keeps the answer in the browser (localStorage, no cookie
// of ours) and only then adds Google's tag. Pages stay one cached HTML for
// everyone; the choice is made in each browser.
import { type Html, html, raw } from "./html";
import { type SiteLang, t } from "./texts";

/** The web stream's Measurement ID (not a secret; docs/setup.md). */
export const GA_ID = "G-D0H8XW2SWJ";

const KEY = "outer-news-analytics";

/** Shows the banner when nothing is chosen yet; loads Google's tag after a yes, now and on later visits. */
export const CONSENT_JS = `(function(){var k=${JSON.stringify(KEY)},id=${JSON.stringify(GA_ID)};function load(){window.dataLayer=window.dataLayer||[];window.gtag=function(){window.dataLayer.push(arguments)};window.gtag("js",new Date());window.gtag("config",id);var s=document.createElement("script");s.async=true;s.src="https://www.googletagmanager.com/gtag/js?id="+id;document.head.appendChild(s)}var v=null;try{v=localStorage.getItem(k)}catch(e){}if(v==="yes"){load();return}if(v==="no")return;var b=document.getElementById("consent");if(!b)return;b.hidden=false;b.addEventListener("click",function(e){var c=e.target.closest&&e.target.closest("[data-consent]");if(!c)return;var yes=c.getAttribute("data-consent")==="yes";try{localStorage.setItem(k,yes?"yes":"no")}catch(e){}b.hidden=true;if(yes)load()})})();`;

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

/** The banner, hidden until the script shows it, then the script. Without JavaScript it never shows and nothing loads. */
export const consent = (lang: SiteLang): Html => html`<div class="consent" id="consent" role="region" aria-label="${t(lang, "consentTitle")}" hidden><div class="wrap">
<p>${t(lang, "consentText")}</p>
<div class="consent-buttons"><button type="button" data-consent="no">${t(lang, "consentNo")}</button><button type="button" class="yes" data-consent="yes">${t(lang, "consentYes")}</button></div>
</div></div>
<script>${raw(CONSENT_JS)}</script>`;
