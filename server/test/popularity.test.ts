// Popularity per country (#230 step 4): Wikipedia's views per language and
// GDELT's media per country, from a fake web, into article_views and article_media.
import { env } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import { gdeltUrl, mediaFrom } from "../src/popularity/gdelt";
import { popularityStep } from "../src/popularity";
import { mediaScore, viewsScore } from "../src/popularity/score";
import { languageLinks, viewsFrom } from "../src/popularity/views";

/** The start of Christine Lagarde's English page as Wikipedia serves it (30 Oct 2026), cut to what the check reads. */
const PAGE = `<!DOCTYPE html><html><head><script>RLCONF={"wgPageName":"Christine_Lagarde","wgTitle":"Christine Lagarde"};</script></head><body>
<li class="interlanguage-link interwiki-cs mw-list-item"><a href="https://cs.wikipedia.org/wiki/Christine_Lagardeov%C3%A1" title="Christine Lagardeová – Czech" lang="cs" hreflang="cs" data-title="Christine Lagardeová" data-language-autonym="Čeština" data-language-local-name="Czech" class="interlanguage-link-target"><span>Čeština</span></a></li>
<li class="interlanguage-link interwiki-uk mw-list-item"><a href="https://uk.wikipedia.org/wiki/%D0%9A%D1%80%D1%96%D1%81%D1%82%D1%96%D0%BD_%D0%9B%D0%B0%D0%B3%D0%B0%D1%80%D0%B4" title="Крістін Лагард – Ukrainian" lang="uk" hreflang="uk" class="interlanguage-link-target"><span>Українська</span></a></li>
<li class="interlanguage-link interwiki-qu mw-list-item"><a href="https://qu.wikipedia.org/wiki/Christine_Lagarde" lang="qu" class="interlanguage-link-target"><span>Runa Simi</span></a></li>
</body></html>`;

/** Lagarde's Czech page from 20 to 30 Oct 2026, as the pageviews API answered: she resigned on the 29th. */
const CZECH_VIEWS = [5, 7, 8, 7, 7, 5, 5, 5, 7, 545].map((views, i) => ({ timestamp: `202610${20 + i}00`, views }));

const gdeltArticle = (country: string, n: number) => ({
  url: `https://news.example/${country.replace(" ", "-")}/${n}`,
  title: `Lagarde resigns ${n}`,
  domain: `${country.split(" ")[0].toLowerCase()}.example`,
  sourcecountry: country,
});

describe("the score", () => {
  it("counts a jump in a language's views, not big numbers alone: Lagarde on cs.wikipedia is 1", () => {
    expect(viewsScore(545, 6)).toBe(1);
    expect(viewsScore(1200, 20)).toBe(1.5);
    expect(viewsScore(150, 40)).toBe(0.5);
    // Few views, however sudden; many, but as usual.
    expect(viewsScore(90, 1)).toBe(0);
    expect(viewsScore(5000, 2000)).toBe(0);
  });

  it("counts the country's own outlets: 3 articles are half a point, 10 a point", () => {
    expect([mediaScore(2), mediaScore(3), mediaScore(9), mediaScore(10)]).toEqual([0, 0.5, 0.5, 1]);
  });
});

describe("Wikipedia", () => {
  it("reads an article's titles in the other languages from its page's language links", () => {
    const { title, links } = languageLinks(PAGE);
    expect(title).toBe("Christine Lagarde");
    expect(Object.fromEntries(links)).toEqual({ cs: "Christine Lagardeová", uk: "Крістін Лагард", qu: "Christine Lagarde" });
    expect(languageLinks("<html>cut before the links").links.size).toBe(0);
  });

  it("takes the most views a day since the item against the median of the 7 days before it", () => {
    expect(viewsFrom({ items: CZECH_VIEWS }, "20261029")).toEqual({ views: 545, usual: 7 });
    // A day the API leaves out had no views: here 5 of the 7 days before.
    expect(viewsFrom({ items: CZECH_VIEWS.slice(7) }, "20261029")).toEqual({ views: 545, usual: 0 });
    // No day since the item has ended yet.
    expect(viewsFrom({ items: CZECH_VIEWS }, "20261031")).toBeNull();
    expect(viewsFrom({ detail: "Not found." }, "20261029")).toBeNull();
  });
});

describe("GDELT", () => {
  it("searches the first two keywords GDELT takes, a name in quotes", () => {
    const query = (keywords: string[]) => {
      const url = gdeltUrl(keywords);
      return url ? new URL(url).searchParams.get("query") : null;
    };
    expect(query(["Lagarde", "ECB", "resignation"])).toBe("Lagarde ECB");
    expect(query(["Christine Lagarde", "EU", "resigns"])).toBe('"Christine Lagarde" resigns');
    expect(query(["EU", "UN"])).toBeNull();
  });

  it("counts the articles by their outlet's country, keeping 3 links each and the countries For you serves", () => {
    const media = mediaFrom({
      articles: [
        ...[1, 2, 3, 4].map((n) => gdeltArticle("Czech Republic", n)),
        gdeltArticle("Ukraine", 1),
        gdeltArticle("Atlantis", 1),
        { ...gdeltArticle("Ukraine", 2), url: "javascript:alert(1)" },
      ],
    });
    expect(media?.get("CZ")).toEqual({ count: 4, links: [1, 2, 3].map((n) => ({ title: `Lagarde resigns ${n}`, outlet: "czech.example", url: `https://news.example/Czech-Republic/${n}` })) });
    expect(media?.get("UA")?.count).toBe(1);
    expect([...(media?.keys() ?? [])]).toEqual(["CZ", "UA"]);
    // No articles at all is an answer (30 Oct: every one GDELT gave); an error page is none.
    expect(mediaFrom({})?.size).toBe(0);
    expect(mediaFrom("Please limit requests to one every 5 seconds")).toBeNull();
  });
});

describe("popularityStep", () => {
  const NOW = new Date("2026-10-30T17:21:00Z");
  /** A run of the summarizer at this minute of the hour. */
  const at = (minute: number) => Date.parse(`2026-10-30T17:${String(minute).padStart(2, "0")}:00Z`);

  async function released(id: string, wikipedia: string[], keywords: string[], published = "2026-10-29T12:00:00Z") {
    await env.DB.prepare(
      `INSERT INTO articles (id, source_id, url, original_title, published_at, fetched_at, headline, is_news, importance, feed_seq, wikipedia, keywords)
       VALUES (?1, 'de-federal-government', 'https://example.gov/' || ?1, 'Lagarde', ?2, ?2, 'Lagarde resigns', 1, 4,
               (SELECT COALESCE(MAX(feed_seq), 0) + 1 FROM articles WHERE feed_seq IS NOT NULL), ?3, ?4)`,
    )
      .bind(id, published, JSON.stringify(wikipedia), JSON.stringify(keywords))
      .run();
  }

  /** The web the check sees; `gdelt` answers GDELT. Records every address asked. */
  function web(gdelt: () => Response) {
    const asked: string[] = [];
    const get = async (url: string) => {
      asked.push(url);
      if (url.startsWith("https://en.wikipedia.org/wiki/Christine_Lagarde")) return new Response(PAGE);
      if (url.includes("/per-article/cs.wikipedia/")) return Response.json({ items: CZECH_VIEWS });
      if (url.includes("/per-article/en.wikipedia/")) return Response.json({ items: CZECH_VIEWS.map((d) => ({ ...d, views: d.views * 20 })) });
      if (url.includes("/per-article/uk.wikipedia/")) return Response.json({ items: CZECH_VIEWS.map((d) => ({ ...d, views: 3 })) });
      if (url.startsWith("https://api.gdeltproject.org/")) return gdelt();
      return new Response("not found", { status: 404 });
    };
    return { get, asked };
  }

  const rows = async (table: "article_views" | "article_media") =>
    (await env.DB.prepare(`SELECT * FROM ${table} WHERE article_id = 'lagarde' ORDER BY 2`).all<Record<string, unknown>>()).results;

  it("stores each language's views and each country's media for one item, then leaves it for 12 hours", async () => {
    await released("lagarde", ["Christine Lagarde"], ["Lagarde", "ECB"]);
    const { get, asked } = web(() =>
      Response.json({ articles: [...[1, 2, 3].map((n) => gdeltArticle("Czech Republic", n)), ...[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11].map((n) => gdeltArticle("United States", n))] }),
    );
    await popularityStep(env, at(21), NOW, get);

    expect((await rows("article_views")).map((r) => [r.lang, r.title, r.views, r.usual, r.score])).toEqual([
      ["cs", "Christine Lagardeová", 545, 7, 1],
      ["en", "Christine Lagarde", 10900, 140, 1.5],
      ["uk", "Крістін Лагард", 3, 3, 0],
    ]);
    const media = await rows("article_media");
    expect(media.map((r) => [r.country, r.count, r.score])).toEqual([
      ["CZ", 3, 0.5],
      ["US", 11, 1],
    ]);
    expect(JSON.parse(String(media[0].links))).toHaveLength(3);
    // Only the languages For you serves are asked (not qu), the days from a week before the item to yesterday.
    expect(asked.filter((u) => u.includes("/per-article/")).map((u) => u.split("/")[8])).toEqual(["cs.wikipedia", "uk.wikipedia", "en.wikipedia"]);
    expect(asked.find((u) => u.includes("/cs.wikipedia/"))).toMatch(/\/daily\/20261022\/20261029$/);
    expect(await env.DB.prepare("SELECT popularity_at FROM articles WHERE id = 'lagarde'").first("popularity_at")).toBe("2026-10-30T17:21:00Z");

    // Checked: not again within 12 hours; and only in the runs at minutes 1, 5, 9…
    asked.length = 0;
    await popularityStep(env, at(25), new Date(NOW.getTime() + 4 * 60_000), get);
    await popularityStep(env, at(23), new Date(NOW.getTime() + 13 * 3_600_000), get);
    expect(asked).toEqual([]);
    await popularityStep(env, at(29), new Date(NOW.getTime() + 13 * 3_600_000), get);
    expect(asked.length).toBeGreaterThan(0);
  });

  it("keeps the views when GDELT refuses, and the media it had; an item without Wikipedia articles is checked for its media", async () => {
    await released("lagarde", ["Christine Lagarde"], ["Lagarde", "ECB"]);
    await env.DB.prepare(
      "INSERT INTO article_media (article_id, country, count, links, score, checked_at) VALUES ('lagarde', 'CZ', 4, '[]', 0.5, '2026-10-30T05:00:00Z')",
    ).run();
    const refusing = web(() => new Response("Please limit requests to one every 5 seconds", { status: 429 }));
    await popularityStep(env, at(21), NOW, refusing.get);
    expect((await rows("article_views")).map((r) => r.lang)).toEqual(["cs", "en", "uk"]);
    expect((await rows("article_media")).map((r) => [r.country, r.count])).toEqual([["CZ", 4]]);

    await released("decree", [], ["Metrogas", "tariff"], "2026-10-30T09:00:00Z");
    const quiet = web(() => Response.json({}));
    await popularityStep(env, at(25), NOW, quiet.get);
    expect(quiet.asked).toEqual([expect.stringMatching(/^https:\/\/api\.gdeltproject\.org\/.*query=Metrogas\+tariff/)]);
    expect(await env.DB.prepare("SELECT popularity_at FROM articles WHERE id = 'decree'").first("popularity_at")).toBe("2026-10-30T17:21:00Z");
  });

  it("checks only released news of the last 72 hours with something to look for, never checked first", async () => {
    await released("old", ["Christine Lagarde"], ["Lagarde"], "2026-10-27T11:00:00Z");
    await released("bare", [], []);
    await released("checked", ["Christine Lagarde"], ["Lagarde"], "2026-10-30T10:00:00Z");
    await env.DB.prepare("UPDATE articles SET popularity_at = '2026-10-30T09:00:00Z' WHERE id = 'checked'").run();
    await released("new", ["Christine Lagarde"], ["Lagarde"], "2026-10-29T08:00:00Z");
    const { get } = web(() => Response.json({}));
    await popularityStep(env, at(21), NOW, get);
    const checkedNow = await env.DB.prepare("SELECT id FROM articles WHERE popularity_at = '2026-10-30T17:21:00Z'").all<{ id: string }>();
    expect(checkedNow.results.map((r) => r.id)).toEqual(["new"]);
  });
});
