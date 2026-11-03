// The App Store buttons and their redirect (#60, the website's funnel): a
// channel per page kind and language, Apple's campaign tokens, never cached,
// kept from crawlers, and a click counted in Google Analytics after the yes.
import { describe, expect, it } from "vitest";
import { CONSENT_JS } from "../src/site/consent";
import { getApp } from "../src/site/layout";
import { APP_STORE_ID, APP_STORE_LIVE, appStoreUrl, storeChannel } from "../src/site/stores";
import { site } from "./site-helpers";

describe("/go/appstore/<channel>", () => {
  it("sends the visitor to the App Store with the channel as Apple's campaign, never cached, not indexed", async () => {
    const { status, headers, body } = await site("/go/appstore/web-article-uk");
    expect(status).toBe(302);
    expect(headers.get("location")).toBe(appStoreUrl("web-article-uk"));
    expect(headers.get("location")).toMatch(new RegExp(`^https://apps\\.apple\\.com/app/id${APP_STORE_ID}\\?(pt=\\d+&)?ct=web-article-uk&mt=8$`));
    expect(headers.get("cache-control")).toBe("no-store");
    expect(headers.get("x-robots-tag")).toBe("noindex");
    expect(body).toBe("");
  });

  it("takes only Apple's channel characters; anything else, or none, is the channel `web`", async () => {
    for (const path of ["/go/appstore/Web_Article", "/go/appstore/" + "a".repeat(41), "/go/appstore", "/go/appstore/"]) {
      expect((await site(path)).headers.get("location"), path).toContain("ct=web&mt=8");
    }
  });

  it("is kept from crawlers by robots.txt", async () => {
    expect((await site("/robots.txt")).body).toMatch(/^Disallow: \/go\/$/m);
  });
});

describe("the App Store button", () => {
  it("names its page kind and language as the channel", () => {
    expect(storeChannel("article", "uk")).toBe("web-article-uk");
    expect(storeChannel("list", "en")).toBe("web-list-en");
    expect(storeChannel("notInLanguage", "es")).toBe("web-notinlanguage-es");
  });

  it("says Coming soon and is no link until the app is in the store", async () => {
    expect(APP_STORE_LIVE).toBe(false);
    const { body } = await site("/en");
    expect(body).toContain('<span class="store" aria-disabled="true"><span class="name">App Store</span><span>Coming soon</span></span>');
    expect(body).not.toContain("/go/appstore");
  });

  it("once live, links to the redirect with its channel, nofollow, marked for the click event", () => {
    const button = getApp("uk", "article", true).toString();
    expect(button).toContain('<a class="store" href="/go/appstore/web-article-uk" rel="nofollow" data-store="appstore" data-channel="web-article-uk"><span class="name">App Store</span><span>Завантажити</span></a>');
    // Google Play stays a placeholder: no Android app yet.
    expect(button).toContain('<span class="name">Google Play</span>');
  });

  it("counts a click in Google Analytics only once Google's tag is loaded (after the yes)", () => {
    expect(CONSENT_JS).toContain('closest("[data-store]");if(a&&window.gtag)window.gtag("event","app_store_click"');
  });
});
