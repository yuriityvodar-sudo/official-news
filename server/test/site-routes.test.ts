// The website's routes and headers (#88): status and cache headers per kind of
// page, nothing indexed, one request per page view, no host in any page, and
// nothing from the address ever becoming markup.
import { describe, expect, it } from "vitest";
import { ROBOTS_TXT } from "../src/site/handler";
import { CACHE } from "../src/site/respond";
import { site } from "./site-helpers";

/** [path, status, cache kind, content-language] for every kind of response. */
const ROUTES: [string, number, keyof typeof CACHE, string | null][] = [
  ["/robots.txt", 200, "fixed", null],
  ["/nowhere", 404, "missing", "en"],
  ["/uk/nowhere", 404, "missing", "uk"],
  ["/.well-known/apple-app-site-association", 404, "missing", "en"],
  ["/favicon.ico", 404, "icon", null],
  ["/apple-touch-icon.png", 200, "icon", null],
  ["/apple-touch-icon-precomposed.png", 200, "icon", null],
  ["/icon-512.png", 200, "icon", null],
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
        expect(headers.get("content-security-policy")).toMatch(/^default-src 'none'; style-src 'sha256-[A-Za-z0-9+/]+=*'; img-src 'self' data:; /);
        expect(headers.get("content-language")).toBe(lang);
        expect(headers.get("set-cookie")).toBeNull();
        expect(headers.get("vary")).toBeNull();
        if (method === "HEAD") expect(body).toBe("");
      }
    });
  }

  it("answers 405 to other methods, never stored", async () => {
    for (const method of ["POST", "PUT", "DELETE"]) {
      const { status, headers } = await site("/en", { method });
      expect(status).toBe(405);
      expect(headers.get("allow")).toBe("GET, HEAD");
      expect(headers.get("cache-control")).toBe("no-store");
    }
  });

  it("serves robots.txt that keeps crawlers from every page", async () => {
    expect(ROBOTS_TXT).toBe("User-agent: *\nDisallow: /\n");
    expect((await site("/robots.txt")).body).toBe(ROBOTS_TXT);
  });

  const PAGES = ROUTES.filter(([p, s]) => (s < 300 || s >= 400) && !p.endsWith(".txt") && !p.endsWith(".ico") && !p.endsWith(".png"));

  it("says in every page's head exactly what its X-Robots-Tag says (one value, never two that disagree)", async () => {
    for (const [path] of PAGES) {
      const { headers, body } = await site(path);
      const meta = /<meta name="robots" content="([^"]+)">/.exec(body)?.[1];
      expect(meta, path).toBe(headers.get("x-robots-tag"));
    }
  });
});

describe("one request per page view", () => {
  it("no page refers to anything it would have to load: no script, image, stylesheet, font or frame", async () => {
    for (const path of ["/nowhere", "/uk/nowhere"]) {
      const { body } = await site(path);
      expect(body, path).not.toMatch(/<script|<iframe|<object|<embed|<video|<audio|<source|rel="stylesheet"|rel="preload"|rel="prefetch"|rel="preconnect"|rel="dns-prefetch"|@import|@font-face/i);
      // CSS url() only for data:, and the tab icon a data: URL (no /favicon.ico request).
      for (const m of body.matchAll(/url\(([^)]*)\)/g)) expect(m[1], path).toMatch(/^["']?data:/);
      expect(body).toMatch(/<link rel="icon" href="data:image\/png;base64,/);
      for (const m of body.matchAll(/<link rel="([^"]+)" [^>]*href="([^"]+)"/g)) {
        if (m[1] === "icon") expect(m[2]).toMatch(/^data:/);
        else if (m[1] === "apple-touch-icon") expect(m[2]).toBe("/apple-touch-icon.png");
        else expect(["canonical", "alternate"], `${path}: <link rel="${m[1]}">`).toContain(m[1]);
      }
    }
  });

  it("shows the Smart App Banner tag", async () => {
    const { body } = await site("/en/nowhere");
    expect(body).toContain('<meta name="apple-itunes-app" content="app-id=6822820350">');
  });
});

describe("the request's host", () => {
  it("never appears in a page (the cache key has no host)", async () => {
    for (const path of ["/", "/en", "/en/nowhere"]) {
      const { body, headers } = await site(path, {}, "evil.test");
      expect(body).not.toContain("evil.test");
      expect(headers.get("location") ?? "").not.toContain("evil.test");
    }
  });
});

describe("text from the address", () => {
  it("never repeats the address in a page", async () => {
    for (const path of ["/en/<script>alert(1)</script>", "/en/de/%3Cscript%3E", "/en/de/x<b>", "/%3Cscript%3E"]) {
      const { status, body } = await site(path);
      expect(status).toBe(404);
      // (The tab icon's data: URL holds %3C, and "description" holds "script".)
      expect(body).not.toMatch(/alert|<script|%3Cscript|<b>|x%3Cb/i);
    }
  });
});
