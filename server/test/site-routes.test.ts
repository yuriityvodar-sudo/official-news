// The website's routes and headers (#88): status and cache headers per kind of
// page, nothing indexed, one request per page view, no host in any page, and
// nothing from the data or the address ever becoming markup.
import { env } from "cloudflare:workers";
import { beforeEach, describe, expect, it } from "vitest";
import { CACHE } from "../src/site/respond";
import { INFO_PAGES } from "../src/site/urls";
import { SITE_LANGS } from "../src/site/texts";
import { hideSeed } from "./helpers";
import { ORIGIN, insertArticle, insertTranslation, site, siteEnv, siteRowsRead as rowsRead, testId } from "./site-helpers";

const ID = testId(1);
const NOT_IN_UK = testId(2);

beforeEach(async () => {
  await hideSeed();
  await insertArticle({ id: ID });
  await insertTranslation(ID, "uk");
  await insertArticle({ id: NOT_IN_UK });
});

/** [path, status, cache kind, content-language] for every kind of response. */
const ROUTES: [string, number, keyof typeof CACHE, string | null][] = [
  ["/", 200, "fixed", "en"],
  ["/robots.txt", 200, "fixed", null],
  ["/en", 200, "list", "en"],
  ["/uk?before=5", 200, "list", "uk"],
  [`/en/de/${ID}`, 200, "article", "en"],
  [`/uk/de/${ID}-slug`, 200, "article", "uk"],
  [`/uk/de/${NOT_IN_UK}`, 404, "notInLanguage", "uk"],
  [`/en/de/${testId(99)}`, 404, "missing", "en"],
  ["/ru/about", 200, "fixed", "ru"],
  ["/es/privacy", 200, "fixed", "es"],
  ["/de/terms", 200, "fixed", "de"],
  ["/en/support", 200, "fixed", "en"],
  ["/nowhere", 404, "missing", "en"],
  ["/uk/nowhere", 404, "missing", "uk"],
  ["/en/de", 404, "missing", "en"],
  ["/.well-known/apple-app-site-association", 404, "missing", "en"],
  ["/sitemap.xml", 404, "missing", "en"],
  ["/favicon.ico", 404, "icon", null],
  ["/apple-touch-icon-precomposed.png", 404, "icon", null],
  ["/en/", 301, "redirect", null],
  ["/en?utm_source=x", 301, "redirect", null],
  ["/?fbclid=1", 301, "redirect", null],
];

describe("every route", () => {
  for (const [path, status, kind, lang] of ROUTES) {
    it(`${path}: ${status}, ${kind} cache, noindex, the CSP, no cookie`, async () => {
      for (const method of ["GET", "HEAD"]) {
        const { status: got, headers, body } = await site(path, { method });
        expect(got).toBe(status);
        expect(headers.get("cache-control")).toBe(CACHE[kind].browser);
        expect(headers.get("cloudflare-cdn-cache-control")).toBe(CACHE[kind].edge);
        expect(headers.get("x-robots-tag")).toBe("noindex");
        expect(headers.get("x-content-type-options")).toBe("nosniff");
        expect(headers.get("content-security-policy")).toMatch(/^default-src 'none'; style-src 'sha256-[A-Za-z0-9+/]+=*'; img-src data:;/);
        expect(headers.get("content-language")).toBe(lang);
        expect(headers.get("set-cookie")).toBeNull();
        expect(headers.get("vary")).toBeNull();
        if (method === "HEAD") expect(body).toBe("");
      }
    });
  }

  it("sends a query a list or the landing page does not use to the clean URL, with no D1 read", async () => {
    for (const [path, location] of [
      ["/en?x=1", "/en"],
      ["/en?before=12&utm=1", "/en?before=12"],
      ["/en?before=0", "/en"],
      ["/en?before=1&before=2", "/en"],
      ["/en?before=abc", "/en"],
      ["/uk/?before=7", "/uk?before=7"],
      ["/?lang=uk", "/"],
    ]) {
      let response: Awaited<ReturnType<typeof site>> | undefined;
      expect(await rowsRead(async () => (response = await site(path)))).toBe(0);
      expect(response!.status).toBe(301);
      expect(response!.headers.get("location")).toBe(ORIGIN + location);
    }
  });

  it("answers 405 to other methods, never stored", async () => {
    for (const method of ["POST", "PUT", "DELETE"]) {
      const { status, headers } = await site("/en", { method });
      expect(status).toBe(405);
      expect(headers.get("allow")).toBe("GET, HEAD");
      expect(headers.get("cache-control")).toBe("no-store");
    }
  });

  it("answers 500, never stored, when D1 fails: never a cached 404", async () => {
    const broken = { ...siteEnv(), DB: { prepare: () => { throw new Error("D1 is down"); } } as unknown as D1Database };
    for (const path of ["/en", `/uk/de/${ID}`]) {
      const { status, headers, body } = await site(path, {}, "site.test", broken);
      expect(status).toBe(500);
      expect(headers.get("cache-control")).toBe("no-store");
      expect(headers.get("cloudflare-cdn-cache-control")).toBe("no-store");
      expect(body).not.toContain("D1 is down");
    }
  });

  it("serves robots.txt that disallows everything", async () => {
    expect((await site("/robots.txt")).body).toBe("User-agent: *\nDisallow: /\n");
  });

  it("says noindex in every page's head too", async () => {
    for (const [path] of ROUTES.filter(([p, s]) => s !== 301 && !p.endsWith(".txt") && !p.endsWith(".ico") && !p.endsWith(".png"))) {
      expect((await site(path)).body, path).toContain('<meta name="robots" content="noindex">');
    }
  });
});

describe("one request per page view", () => {
  it("no page refers to anything it would have to load: no script, image, stylesheet, font or frame", async () => {
    await env.DB.prepare("UPDATE articles SET image_url = 'https://www.bundesregierung.de/picture.jpg' WHERE id = ?").bind(ID).run();
    const paths = ["/", "/en", "/uk", `/en/de/${ID}`, `/uk/de/${ID}`, ...SITE_LANGS.flatMap((l) => INFO_PAGES.map((p) => `/${l}/${p}`))];
    for (const path of paths) {
      const { body } = await site(path);
      expect(body, path).not.toMatch(/<script|<img|<iframe|<object|<embed|<video|<audio|<source|rel="stylesheet"|rel="preload"|rel="prefetch"|rel="preconnect"|rel="dns-prefetch"|@import|@font-face/i);
      // CSS url() only for data:, and every icon a data: URL (no /favicon.ico request).
      for (const m of body.matchAll(/url\(([^)]*)\)/g)) expect(m[1], path).toMatch(/^["']?data:/);
      expect(body).toMatch(/<link rel="icon" href="data:image\/svg\+xml,/);
      for (const m of body.matchAll(/<link rel="([^"]+)" [^>]*href="([^"]+)"/g)) {
        if (m[1] === "icon") expect(m[2]).toMatch(/^data:/);
        else expect(["canonical", "alternate"], `${path}: <link rel="${m[1]}">`).toContain(m[1]);
      }
      expect(body).not.toContain("picture.jpg");
    }
  });

  it("shows the Smart App Banner tag and no source picture", async () => {
    const { body } = await site(`/en/de/${ID}`);
    expect(body).toContain('<meta name="apple-itunes-app" content="app-id=6822820350">');
  });
});

describe("the request's host", () => {
  it("never appears in a page: every absolute URL is SITE_ORIGIN's (the cache key has no host)", async () => {
    for (const path of ["/", "/en", `/uk/de/${ID}`, "/es/about", "/en/", `/uk/de/${NOT_IN_UK}`]) {
      const { body, headers } = await site(path, {}, "evil.test");
      expect(body).not.toContain("evil.test");
      expect(headers.get("location") ?? "").not.toContain("evil.test");
    }
    expect((await site(`/uk/de/${ID}`, {}, "evil.test")).body).toContain(`<link rel="canonical" href="${ORIGIN}/uk/de/${ID}-`);
  });
});

describe("text from the data and the address", () => {
  const XSS = testId(3);
  beforeEach(async () => {
    await insertArticle({
      id: XSS,
      headline: `"><script>alert(1)</script>`,
      shortSummary: `<img src=x onerror=alert(1)>`,
      summary: `First <b>bold</b> & "quoted"\n\n<svg onload=alert(1)>`,
      originalUrl: "javascript:alert(1)",
      decisionType: `"><script>`,
      originalLanguage: `x" onmouseover="alert(1)`,
    });
    await env.DB.prepare(`UPDATE sources SET name = ? WHERE id = 'de-federal-government'`).bind(`O'Brien & "Co" <b>`).run();
  });

  it("is always escaped: no tag, no attribute, no javascript: link", async () => {
    for (const path of [`/en/de/${XSS}`, "/en"]) {
      const { status, body } = await site(path);
      expect(status).toBe(200);
      expect(body).not.toMatch(/<script|<img|<svg onload|<b>bold/i);
      // No tag carries an event handler: the escaped text may say "onerror=", a tag never does.
      // (Attribute values are blanked first: a meta description may quote the escaped text.)
      expect(body.replace(/"[^"]*"/g, '""')).not.toMatch(/<[^>]*\son\w+=/i);
      expect(body).not.toMatch(/href="javascript:/i);
      expect(body).toContain("&quot;&gt;&lt;script&gt;alert(1)&lt;/script&gt;");
      expect(body).toContain("O&#39;Brien &amp; &quot;Co&quot; &lt;b&gt;");
    }
    const { body } = await site(`/en/de/${XSS}`);
    // In <title> and in attributes (meta, Open Graph), quotes are escaped too.
    expect(body).toContain("<title>&quot;&gt;&lt;script&gt;alert(1)&lt;/script&gt; · Official News</title>");
    expect(body).toMatch(/<meta property="og:title" content="&quot;&gt;&lt;script&gt;/);
    // No official link for a URL that is not https, and an unknown type gets no label.
    expect(body).not.toContain('class="official"');
    expect(body).not.toContain('class="kind"');
    expect(body).not.toMatch(/<span lang="x/);
  });

  it("keeps an https link that tries to break out of its attribute inside it", async () => {
    await env.DB.prepare("UPDATE articles SET url = ? WHERE id = ?").bind(`https://x.gov/"onmouseover=alert(1)`, XSS).run();
    const { body } = await site(`/en/de/${XSS}`);
    expect(body).toContain('class="official" href="https://x.gov/%22onmouseover=alert(1)"');
  });

  it("never repeats the address in a page", async () => {
    for (const path of ["/en/<script>alert(1)</script>", "/en/de/%3Cscript%3E", `/en/de/${ID}x<b>`, "/%3Cscript%3E"]) {
      const { status, body } = await site(path);
      expect(status).toBe(404);
      // (The tab icon's data: URL holds %3C, and "description" holds "script".)
      expect(body).not.toMatch(/alert|<script|%3Cscript|<b>|x%3Cb/i);
    }
  });
});
