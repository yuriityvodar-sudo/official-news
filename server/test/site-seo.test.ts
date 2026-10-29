// The way in: / opens the visitor's language, and the front page's title.
import { describe, expect, it } from "vitest";
import { ORIGIN, site } from "./site-helpers";

describe("/ opens the visitor's language (no page to choose one)", () => {
  const go = async (acceptLanguage: string | null) => {
    const headers: Record<string, string> = {};
    if (acceptLanguage !== null) headers["accept-language"] = acceptLanguage;
    const { status, headers: h } = await site("/", { headers });
    return { status, location: h.get("location"), cache: h.get("cache-control") };
  };

  it("takes the browser's first language the site has, and is never cached", async () => {
    expect(await go("uk-UA,uk;q=0.9,en;q=0.8")).toEqual({ status: 302, location: `${ORIGIN}/uk`, cache: "private, no-store" });
    expect((await go("ru-RU,ru;q=0.9")).location).toBe(`${ORIGIN}/ru`);
    expect((await go("es-MX,es;q=0.9")).location).toBe(`${ORIGIN}/es`);
    expect((await go("fr-FR,fr;q=0.9,en;q=0.5")).location).toBe(`${ORIGIN}/en`);
    expect((await go("en;q=0.4,uk;q=0.9")).location).toBe(`${ORIGIN}/uk`);
  });

  it("leaves German out while the server does not translate into it, and falls back to English", async () => {
    expect((await go("de-DE,de;q=0.9")).location).toBe(`${ORIGIN}/en`);
    expect((await go(null)).location).toBe(`${ORIGIN}/en`);
    expect((await go("*")).location).toBe(`${ORIGIN}/en`);
  });
});

describe("the front page's title", () => {
  it("leads with the name", async () => {
    expect((await site("/uk")).body).toContain("<title>Outer News · ");
    expect((await site("/en")).body).toContain("<title>Outer News · Official decisions</title>");
  });
});
