// The website's way into the App Store, as a funnel we can count (#60, Yurii,
// 3 Nov: how many visitors click through, reach the App Store and download).
// Every App Store button links to our own `/go/appstore/<channel>`, which sends
// the visitor on to the App Store with Apple's campaign tokens: `pt` (our
// provider in App Store Connect) and `ct` (the channel). App Store Connect ›
// App Analytics › Campaigns then shows, per channel, the product page views and
// first-time downloads that came from it. That is the only proof iOS gives:
// Apple never tells an app where its install came from (AlphaMingo's lesson,
// 1 Nov: without `pt` Apple credited nothing for 90 days). Google Analytics
// counts the click too, for visitors who accepted cookies (consent.ts).
import type { SiteLang } from "./texts";

/** The App Store app (docs/setup.md); Safari shows its Smart App Banner. */
export const APP_STORE_ID = "6822820350";

/**
 * Whether the app is in the App Store: until then the buttons say "Coming
 * soon" and are not links (Yurii, 28 Oct). Switched on at the release.
 */
export const APP_STORE_LIVE = false;

/**
 * Our provider token in App Store Connect (App Analytics › Campaigns › a
 * generated link's `pt=`): not a secret, it is in every public campaign link.
 * Empty until it is read from App Store Connect; without it Apple attributes
 * nothing, so the release waits for it (docs/decisions/2026-11-03-app-store-funnel.md).
 */
export const APP_STORE_PROVIDER = "";

/** A channel as Apple takes it in `ct`: lower-case letters, digits and hyphens, at most 40 characters. */
const CHANNEL = /^[a-z0-9-]{1,40}$/;

/** The channel of a button: `web-<page kind>-<language>` (`web-article-uk`), so Apple's report splits by page and language. */
export const storeChannel = (kind: string, lang: SiteLang): string => {
  const channel = `web-${kind.toLowerCase().replace(/[^a-z0-9]+/g, "-")}-${lang}`.slice(0, 40);
  return CHANNEL.test(channel) ? channel : "web";
};

/** Our redirect for a channel: the link every App Store button has. */
export const storeLink = (channel: string) => `/go/appstore/${channel}`;

/** Where `/go/appstore/<channel>` sends the visitor: the App Store page with the campaign tokens; an unusable channel becomes `web`. */
export function appStoreUrl(channel: string): string {
  const ct = CHANNEL.test(channel) ? channel : "web";
  const pt = APP_STORE_PROVIDER ? `pt=${APP_STORE_PROVIDER}&` : "";
  return `https://apps.apple.com/app/id${APP_STORE_ID}?${pt}ct=${ct}&mt=8`;
}
