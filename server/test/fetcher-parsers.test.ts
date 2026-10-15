import { describe, expect, it } from "vitest";

import { parseApi } from "../src/fetcher/api";
import { parseDate } from "../src/fetcher/dates";
import { parseFeed } from "../src/fetcher/feed";
import { extractContent, parsePage } from "../src/fetcher/page";
import { isAllowed, parseRobots, robotsFromResponse } from "../src/fetcher/robots";
import { decodeEntities, fillTemplate, getPath, htmlToText } from "../src/fetcher/text";

const NOW = new Date("2026-10-14T15:00:00Z");

describe("robots.txt", () => {
  const robots = parseRobots(`
User-agent: GPTBot
Disallow: /

User-agent: *
Disallow: /search
Disallow: /*/print$
Allow: /search/help
Disallow: /private/
`);

  it("uses the * group when no group names us", () => {
    expect(isAllowed(robots, "/news/1")).toBe(true);
    expect(isAllowed(robots, "/search?q=x")).toBe(false);
  });

  it("lets the longest rule win, and Allow on a tie", () => {
    expect(isAllowed(robots, "/search/help")).toBe(true);
    expect(isAllowed(parseRobots("User-agent: *\nDisallow: /a\nAllow: /a"), "/a")).toBe(true);
  });

  it("understands * and $", () => {
    expect(isAllowed(robots, "/page/print")).toBe(false);
    expect(isAllowed(robots, "/page/print/more")).toBe(true);
  });

  it("prefers a group that names our fetcher", () => {
    const ours = parseRobots("User-agent: *\nDisallow: /\n\nUser-agent: OfficialNewsBot\nAllow: /");
    expect(isAllowed(ours, "/anything")).toBe(true);
  });

  it("reads 4xx as no rules and 5xx as stay away", () => {
    expect(isAllowed(robotsFromResponse(404, ""), "/x")).toBe(true);
    expect(isAllowed(robotsFromResponse(503, ""), "/x")).toBe(false);
  });

  it("finds no rules in an HTML page served as robots.txt", () => {
    expect(isAllowed(robotsFromResponse(200, "<html><body>Access limited</body></html>"), "/feed/")).toBe(true);
  });
});

describe("parseDate", () => {
  it("reads ISO times with a zone", () => {
    expect(parseDate("2026-10-12T18:11:00+03:00", {}, NOW)).toEqual({ publishedAt: "2026-10-12T15:11:00Z", dateOnly: false });
  });

  it("applies the source's offset to local times", () => {
    expect(parseDate("2026-10-14 - 15:13", { utcOffset: "+03:00" }, NOW)?.publishedAt).toBe("2026-10-14T12:13:00Z");
    expect(parseDate("2026-10-14T10:46", { utcOffset: "-03:00" }, NOW)?.publishedAt).toBe("2026-10-14T13:46:00Z");
  });

  it("stores a date without time at midday, but never after now", () => {
    expect(parseDate("2026-10-13", {}, NOW)).toEqual({ publishedAt: "2026-10-13T12:00:00Z", dateOnly: true });
    expect(parseDate("2026-10-14", {}, new Date("2026-10-14T09:30:00Z"))?.publishedAt).toBe("2026-10-14T09:30:00Z");
  });

  it("reads feed dates, with or without the space after the comma", () => {
    expect(parseDate("Wed, 14 Oct 2026 10:00:00 +0000", {}, NOW)?.publishedAt).toBe("2026-10-14T10:00:00Z");
    expect(parseDate("Wed,14 Oct 2026 10:00:00 GMT", {}, NOW)?.publishedAt).toBe("2026-10-14T10:00:00Z");
  });

  it("reads day-first slashes, French month names and numeric patterns", () => {
    expect(parseDate("13/08/2026", {}, NOW)?.publishedAt).toBe("2026-08-13T12:00:00Z");
    expect(parseDate("14 octobre 2026", { format: "fr" }, NOW)?.publishedAt).toBe("2026-10-14T12:00:00Z");
    expect(parseDate("2026. 10. 14. ~ 2026. 11. 24.", { format: "yyyy. mm. dd." }, NOW)?.publishedAt).toBe("2026-10-14T12:00:00Z");
  });

  it("drops a meaningless midnight when asked", () => {
    expect(parseDate("2026-08-10 00:00:00.0", { dateOnly: true }, NOW)).toEqual({ publishedAt: "2026-08-10T12:00:00Z", dateOnly: true });
  });

  it("returns null for text that is not a date", () => {
    expect(parseDate("Open", {}, NOW)).toBeNull();
    expect(parseDate("", {}, NOW)).toBeNull();
  });
});

describe("text helpers", () => {
  it("decodes named and numeric entities", () => {
    expect(decodeEntities("&eacute;t&#233; &amp; &#x41;&nbsp;&unknown;")).toBe("été & A &unknown;");
  });

  it("strips HTML that a feed escaped", () => {
    expect(htmlToText("&lt;p&gt;Tomorrow I will join&lt;/p&gt;&lt;p&gt;counterparts&lt;/p&gt;")).toBe("Tomorrow I will join\ncounterparts");
  });

  it("follows JSON stored as a string and fills templates", () => {
    const item = { abs: '{"document":{"content":{"title":"Decreto 1177"}}}', n: 5 };
    expect(getPath(item, "abs.document.content.title")).toBe("Decreto 1177");
    expect(fillTemplate("PL {n}: {abs.document.content.title}", item)).toBe("PL 5: Decreto 1177");
    expect(fillTemplate("missing.path", item)).toBe("");
  });
});

describe("parseFeed", () => {
  it("reads RSS items with CDATA, escaped HTML and an image", () => {
    const xml = `<?xml version="1.0"?><rss><channel><title>x</title>
      <item><title><![CDATA[Decree on visas]]></title><link>http://kremlin.ru/acts/news/80977</link>
        <pubDate>Mon, 12 Oct 2026 15:06:00 +0300</pubDate><category>Decrees</category>
        <description>&lt;p&gt;The President signed a decree.&lt;/p&gt;</description>
        <enclosure url="https://example.gov/a.jpg" type="image/jpeg"/></item>
      <item><title>No link</title></item>
    </channel></rss>`;
    expect(parseFeed(xml, "http://kremlin.ru/acts/news/feed", {}, NOW)).toEqual([
      {
        url: "http://kremlin.ru/acts/news/80977",
        title: "Decree on visas",
        publishedAt: "2026-10-12T12:06:00Z",
        dateOnly: false,
        text: "The President signed a decree.",
        imageUrl: "https://example.gov/a.jpg",
        category: "Decrees",
      },
    ]);
  });

  it("reads Atom entries", () => {
    const xml = `<feed xmlns="http://www.w3.org/2005/Atom"><entry><title>Steel strategy</title>
      <link rel="alternate" type="text/html" href="https://www.gov.uk/government/publications/steel-strategy"/>
      <updated>2026-10-14T10:58:32+01:00</updated><summary>Strategy document.</summary></entry></feed>`;
    const [item] = parseFeed(xml, "https://www.gov.uk/search.atom", {}, NOW);
    expect(item).toMatchObject({ url: "https://www.gov.uk/government/publications/steel-strategy", publishedAt: "2026-10-14T09:58:32Z", text: "Strategy document." });
  });

  it("takes the title and date from other fields when the config says so", () => {
    const xml = `<rss><channel><item><title>PRESIDENCIA</title><description><![CDATA[Decreto por el que se expropia&#8230;]]></description>
      <link>https://dof.gob.mx/nota_detalle.php?codigo=5801157</link><valueDate>14/10/2026</valueDate></item></channel></rss>`;
    const [item] = parseFeed(xml, "https://dof.gob.mx/sumario.xml", { title: "description", date: { field: "valueDate", format: "dd/mm/yyyy" } }, NOW);
    expect(item).toMatchObject({ title: "Decreto por el que se expropia…", publishedAt: "2026-10-14T12:00:00Z", dateOnly: true });
  });
});

describe("parsePage", () => {
  it("reads list items with selectors, attributes and filters", async () => {
    const html = `<ul>
      <li class="newsBlock-item"><a class="newsBlock-link" href="/emmanuel-macron/2026/10/14/cr?x=1&amp;y=2"><span class="newsBlock-cat">Conseil des ministres</span><span>Compte rendu du Conseil</span></a>
        <span class="newsBlock-date">14 octobre 2026</span><script>var noise = 1</script></li>
      <li class="newsBlock-item"><a class="newsBlock-link" href="/other"><span class="newsBlock-cat">Discours</span><span>Speech</span></a>
        <span class="newsBlock-date">13 octobre 2026</span></li>
    </ul>`;
    const items = await parsePage(html, "https://www.elysee.fr/toutes-les-actualites", {
      item: "li.newsBlock-item",
      link: "a.newsBlock-link",
      title: "a.newsBlock-link span:not([class])",
      category: ".newsBlock-cat",
      date: { selector: ".newsBlock-date", format: "fr" },
    }, NOW);
    expect(items).toHaveLength(2);
    expect(items[0]).toMatchObject({
      url: "https://www.elysee.fr/emmanuel-macron/2026/10/14/cr?x=1&y=2",
      title: "Compte rendu du Conseil",
      category: "Conseil des ministres",
      publishedAt: "2026-10-14T12:00:00Z",
    });
  });

  it("reads attributes of the item element itself and dates from the link", async () => {
    const html = `<div class="list"><a href="/Haber/Detay?Id=1"><div class="arb">TBMM GENEL KURULU</div><div class="ard">Kanun teklifi kabul edildi.</div><div class="arh" data-resim-yolu="/img/1.jpg"></div></a></div>`;
    const [item] = await parsePage(html, "https://www.tbmm.gov.tr/meclis-haber/yasama", { item: "div.list > a", link: "@href", title: "div.arb", summary: "div.ard", image: "div.arh@data-resim-yolu" }, NOW);
    expect(item).toMatchObject({ url: "https://www.tbmm.gov.tr/Haber/Detay?Id=1", title: "TBMM GENEL KURULU", text: "Kanun teklifi kabul edildi.", imageUrl: "https://www.tbmm.gov.tr/img/1.jpg" });

    const [meeting] = await parsePage(`<ul><li class="m"><a href="/jp/kakugi/2026/kakugi-2026101301.html">定例閣議案件</a></li></ul>`, "https://www.kantei.go.jp/jp/kakugi/index.html", { item: "li.m", date: { fromLink: "kakugi-(\\d{8})" } }, NOW);
    expect(meeting).toMatchObject({ title: "定例閣議案件", publishedAt: "2026-10-13T12:00:00Z" });
  });
});

describe("extractContent", () => {
  it("takes the main text and the preview image, without menus or scripts", async () => {
    const paragraph = "The cabinet approved the draft budget for 2027 at its weekly meeting. ".repeat(4);
    const html = `<html><head><meta property="og:image" content="/img/budget.jpg"></head><body>
      <nav>Menu Home Search</nav><svg class="icon"/><br>
      <main><h1>Budget</h1><p>${paragraph}</p><script>track()</script><p>Second &amp; last.</p></main>
      <footer>Contact</footer></body></html>`;
    const content = await extractContent(html, "https://www.bundesregierung.de/x");
    expect(content.imageUrl).toBe("https://www.bundesregierung.de/img/budget.jpg");
    expect(content.text).toBe(`Budget\n${paragraph.trim()}\nSecond & last.`);
  });

  it("uses the source's text selector", async () => {
    const html = `<body><div class="top">首页 | 简 | 繁</div><div id="UCAP-CONTENT"><p>国务院关于发展新质生产力的意见</p></div></body>`;
    expect((await extractContent(html, "https://www.gov.cn/x", "#UCAP-CONTENT")).text).toBe("国务院关于发展新质生产力的意见");
  });
});

describe("parseApi", () => {
  it("maps fields with templates", () => {
    const json = { dados: [{ id: 2647588, siglaTipo: "PL", numero: 5558, ano: 2026, ementa: "Dispõe sobre avisos.", dataApresentacao: "2026-10-14T10:46" }] };
    const [item] = parseApi(json, "https://dadosabertos.camara.leg.br/api/v2/proposicoes", {
      items: "dados",
      title: "{siglaTipo} {numero}/{ano}: {ementa}",
      text: "{ementa}",
      link: "https://www.camara.leg.br/propostas-legislativas/{id}",
      date: { field: "dataApresentacao", utcOffset: "-03:00" },
    }, NOW);
    expect(item).toMatchObject({ url: "https://www.camara.leg.br/propostas-legislativas/2647588", title: "PL 5558/2026: Dispõe sobre avisos.", publishedAt: "2026-10-14T13:46:00Z" });
  });

  it("follows JSON strings, keeps matching items, and adds a key to the URL", () => {
    const doc = (type: string, title: string) => ({ documentAbstract: JSON.stringify({ document: { metadata: { "document-content-type": type, uuid: "u1", "friendly-url": { description: "slug" } }, content: { titulo_1: title, fecha_bo: "2026-10-14" } } }) });
    const items = parseApi({ r: { list: [doc("novedad", "Crédito BID"), doc("legislacion", "DECRETO 1177")] } }, "https://www.saij.gob.ar/busqueda", {
      items: "r.list",
      itemRoot: "documentAbstract.document",
      keep: { "metadata.document-content-type": "^novedad$" },
      title: "content.titulo_1",
      link: "https://www.saij.gob.ar/{metadata.friendly-url.description}/{metadata.uuid}",
      key: "{content.fecha_bo}",
      date: { field: "content.fecha_bo" },
    }, NOW);
    expect(items).toHaveLength(1);
    expect(items[0]).toMatchObject({ url: "https://www.saij.gob.ar/slug/u1#2026-10-14", title: "Crédito BID" });
  });

  it("takes the first date field that has a value", () => {
    const [item] = parseApi({ records: [{ billName: "THE BILL", billAssentedDate: null, billPassedInRSDate: "2026-08-11 00:00:00.0", file: "https://sansad.in/a b.pdf" }] }, "https://sansad.in/api", {
      items: "records",
      title: "{billName}",
      link: "file",
      date: { field: ["billAssentedDate", "billPassedInRSDate"], dateOnly: true },
    }, NOW);
    expect(item).toMatchObject({ url: "https://sansad.in/a%20b.pdf", publishedAt: "2026-08-11T12:00:00Z" });
  });
});
