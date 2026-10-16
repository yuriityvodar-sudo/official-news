import { describe, expect, it } from "vitest";

import { parseApi } from "../src/fetcher/api";
import { parseDate } from "../src/fetcher/dates";
import { parseFeed } from "../src/fetcher/feed";
import { extractContent, findLink, parsePage } from "../src/fetcher/page";
import { isAllowed, parseRobots, robotsFromResponse } from "../src/fetcher/robots";
import { decodeBody, decodeEntities, fillTemplate, getPath, getStrings, htmlToText } from "../src/fetcher/text";

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

  it("reads English month names, also after other words (ilo.org)", () => {
    const dateOnly = { publishedAt: "2026-09-07T12:00:00Z", dateOnly: true };
    expect(parseDate("Record of decisions | 7 September 2026", { format: "en" }, NOW)).toEqual(dateOnly);
    expect(parseDate("07 Sep. 2026", { format: "en" }, NOW)).toEqual(dateOnly);
    expect(parseDate("Record of decisions | 7 Septembre 2026", { format: "en" }, NOW)).toBeNull();
    expect(parseDate("Record of decisions", { format: "en" }, NOW)).toBeNull();
  });

  it("reads Ukrainian dates, with the time before or after and the year left out (kmu.gov.ua)", () => {
    const now = new Date("2026-10-16T10:00:00Z");
    const kyiv = { format: "uk", utcOffset: "+03:00" };
    expect(parseDate("15 жовтня  17:34", kyiv, now)).toEqual({ publishedAt: "2026-10-15T14:34:00Z", dateOnly: false });
    expect(parseDate("12:31, 16 жовтня", kyiv, now)?.publishedAt).toBe("2026-10-16T09:31:00Z");
    expect(parseDate("14:20, 02 жовтня 2026", kyiv, now)?.publishedAt).toBe("2026-10-02T11:20:00Z");
    expect(parseDate("16 Жовтня 2025", kyiv, now)).toEqual({ publishedAt: "2025-10-16T12:00:00Z", dateOnly: true });
    // No year: the latest such date, so 31 December read on 1 January is last year's.
    expect(parseDate("31 грудня 23:50", kyiv, new Date("2027-01-01T08:00:00Z"))?.publishedAt).toBe("2026-12-31T20:50:00Z");
    expect(parseDate("1 січня 09:00", kyiv, new Date("2027-01-01T08:00:00Z"))?.publishedAt).toBe("2027-01-01T06:00:00Z");
    expect(parseDate("16 жовтеня", kyiv, now)).toBeNull();
    expect(parseDate("Засідання Уряду", kyiv, now)).toBeNull();
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

  it("decodes ISO-8859-1 byte for byte, also 0x80 to 0x9F", () => {
    const bytes = Uint8Array.from({ length: 256 }, (_, i) => i);
    expect(decodeBody(bytes.buffer, "ISO-8859-1")).toBe(String.fromCharCode(...bytes));
    expect(decodeBody(Uint8Array.from([0x52, 0x65, 0x73, 0x6f, 0x6c, 0x75, 0x63, 0x69, 0xf3, 0x6e]).buffer, "latin1")).toBe("Resolución");
  });

  it("collapses Windows and old Mac line ends like any other", () => {
    expect(htmlToText("Ementa\r\n\r\n\t Institui mecanismos\r\rpara a saúde ")).toBe("Ementa\nInstitui mecanismos\npara a saúde");
  });

  it("follows JSON stored as a string and fills templates", () => {
    const item = { abs: '{"document":{"content":{"title":"Decreto 1177"}}}', n: 5 };
    expect(getPath(item, "abs.document.content.title")).toBe("Decreto 1177");
    expect(fillTemplate("PL {n}: {abs.document.content.title}", item)).toBe("PL 5: Decreto 1177");
    expect(fillTemplate("missing.path", item)).toBe("");
  });

  it("collects strings through lists (*), with a template per entry", () => {
    // Trimmed from the Commission's Press Corner API answer for IP/26/2175.
    const answer = {
      docuLanguageResource: {
        htmlContent: "<p>Today, the Commission launched RAISE.</p>",
        dolaQuoteResources: [
          { author: { authorName: "Ekaterina Zaharieva, Commissioner for Startups, Research and Innovation" }, extract: "Our ambition for AI in science can only become reality together." },
          { author: {}, extract: "" },
        ],
      },
    };
    expect(getStrings(answer, "docuLanguageResource.htmlContent")).toEqual(["<p>Today, the Commission launched RAISE.</p>"]);
    expect(getStrings(answer, "docuLanguageResource.dolaQuoteResources.*.extract")).toEqual(["Our ambition for AI in science can only become reality together."]);
    expect(getStrings(answer, "docuLanguageResource.dolaQuoteResources.*.{author.authorName}: {extract}")).toEqual([
      "Ekaterina Zaharieva, Commissioner for Startups, Research and Innovation: Our ambition for AI in science can only become reality together.",
    ]);
    expect(getStrings(answer, "docuLanguageResource.missing.*.extract")).toEqual([]);
    expect(getStrings({ a: '{"b":"from a JSON string"}' }, "a.b")).toEqual(["from a JSON string"]);
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

  it("reads the ILO's decisions list: the date after its label, as a date without time", async () => {
    // A row of https://www.ilo.org/governing-body/all-gb-documents?field_document_type_target_id=5966 (16 Oct), trimmed.
    // `datetime` is a Unix timestamp, which parseDate does not read, so the text is read with format "en".
    const html = `<div class="views-row"><div class="ilo--card"><a class="ilo--card--link" href="/resource/record-decisions/gb/gb357bis/x" title="Decision concerning X">
      <span class="ilo--card--link--text">Decision concerning X</span></a><div class="ilo--card--wrap"><div class="ilo--card--content">
      <p class="ilo--card--eyebrow">GB.357bis/PFA/1/Decision</p><p class="ilo--card--title">Decision concerning X</p>
      <p class="ilo--card--intro">Adopted at the 357th bis (Special) session</p>
      <time class="ilo--card--date" datetime="1788782400">Record of decisions | 7 September 2026</time></div></div></div></div>`;
    const [item] = await parsePage(html, "https://www.ilo.org/governing-body/all-gb-documents?field_document_type_target_id=5966", {
      item: "div.views-row",
      link: "a.ilo--card--link",
      title: ".ilo--card--title",
      summary: ".ilo--card--intro",
      date: { selector: "time.ilo--card--date", format: "en" },
    }, NOW);
    expect(item).toMatchObject({
      url: "https://www.ilo.org/resource/record-decisions/gb/gb357bis/x",
      title: "Decision concerning X",
      text: "Adopted at the 357th bis (Special) session",
      publishedAt: "2026-09-07T12:00:00Z",
      dateOnly: true,
      imageUrl: null,
    });
  });

  it("keeps every part of a selector list inside the item", async () => {
    // Two kinds of card on one page (kmu.gov.ua): the date is .card-time in one and .card-date in the other.
    const html = `<div class="card"><a href="/news/a">Уряд затвердив Порядок</a><span class="card-time">15 жовтня  17:34</span></div>
      <div class="card"><div class="card-date">12:31, 16 жовтня</div><a href="/news/b">Схвалено Стратегію</a></div>
      <div class="card"><a href="/news/c">Уряд ухвалив рішення</a></div>
      <div class="card-date">10:00, 16 жовтня</div>
      <div class="card"><a href="/events/d, e">Подія</a></div>`;
    const items = await parsePage(html, "https://www.kmu.gov.ua/", {
      item: "div.card",
      link: 'a[href*="/news/"], a[href*=", e"]',
      date: { selector: ".card-time, .card-date", format: "uk", utcOffset: "+03:00" },
    }, new Date("2026-10-16T10:00:00Z"));
    expect(items.map((i) => [i.url, i.publishedAt])).toEqual([
      ["https://www.kmu.gov.ua/news/a", "2026-10-15T14:34:00Z"],
      ["https://www.kmu.gov.ua/news/b", "2026-10-16T09:31:00Z"],
      // The date after this card is outside every card, so it stays undated.
      ["https://www.kmu.gov.ua/news/c", null],
      // A comma inside quotes is not a list separator.
      ["https://www.kmu.gov.ua/events/d,%20e", null],
    ]);
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

  it("drops a picture that is the site's root, and takes twitter:image instead", async () => {
    // vlada.gov.cz pages without a photo: og:image is the home page, an HTML page.
    const noPhoto = `<head><meta property="og:image" content="https://vlada.gov.cz" /></head><main><p>Vláda schválila nový statut.</p></main>`;
    expect((await extractContent(noPhoto, "https://vlada.gov.cz/cz/x/")).imageUrl).toBeNull();
    const second = `<head><meta property="og:image" content="/"><meta name="twitter:image" content="/media/foto.jpg"></head><main>x</main>`;
    expect((await extractContent(second, "https://vlada.gov.cz/cz/x/")).imageUrl).toBe("https://vlada.gov.cz/media/foto.jpg");
    const feed = `<rss><channel><item><title>A</title><link>https://vlada.gov.cz/a</link><enclosure url="https://vlada.gov.cz/" type="image/jpeg"/></item></channel></rss>`;
    expect(parseFeed(feed, "https://vlada.gov.cz/rss.xml", {}, NOW)[0].imageUrl).toBeNull();
  });

  it("uses the source's text selector", async () => {
    const html = `<body><div class="top">首页 | 简 | 繁</div><div id="UCAP-CONTENT"><p>国务院关于发展新质生产力的意见</p></div></body>`;
    expect((await extractContent(html, "https://www.gov.cn/x", "#UCAP-CONTENT")).text).toBe("国务院关于发展新质生产力的意见");
  });

  it("with a text selector, still skips scripts and menus inside it and breaks between its blocks; a selector list works too", async () => {
    const html = `<body><div><p>Outside</p></div><div id="c"><nav>Menu</nav><script>track()</script><h2>Title</h2><div>First</div><p>Second<br>Third</p></div>
      <aside id="d"><p>Sidebar</p></aside></body>`;
    expect((await extractContent(html, "https://x.gov/", "#c")).text).toBe("Title\nFirst\nSecond\nThird");
    expect((await extractContent(html, "https://x.gov/", "#c, #d")).text).toBe("Title\nFirst\nSecond\nThird");
  });

  // #71: trimmed from the real item pages of each source the selector was set for.
  it("takes the Bundesregierung article body without the share links (textSelector)", async () => {
    const html = `<html><head><meta property="og:image" content="/resource/image/2427030/og.jpg"></head><body>
      <nav>Startseite Aktuelles</nav>
      <main id="main"><div class="bpa-container"><header class="bpa-article-header"><h2><span class="bpa-topline-title">Im Bundestag beschlossen</span>
        <span class="bpa-teaser-title-text-inner">Mehr Resilienz für Smart-Geräte</span></h2>
        <div class="bpa-short-text"><p>Mit der Cyberresilienz-Verordnung werden erstmalig Mindeststandards festgelegt.</p></div></header>
        <div class="bpa-share rs_skip"><ul class="bpa-share-list"><li><a href="mailto:?">E-Mail<br>per E-Mail teilen, Mehr Resilienz für Smart-Geräte</a></li>
        <li><a href="https://www.facebook.com/sharer">Facebook<br>per Facebook teilen, Mehr Resilienz für Smart-Geräte</a></li></ul></div></div>
      <div class="bpa-container" id="rs_reading_area_content"><div class="bpa-module-full bpa-article bpa-padded"><div class="bpa-richtext">
        <figure class="bpa-figure"><img src="/resource/image/2427030/w.webp" alt="Waschmaschine"><figcaption>Foto: picture alliance / Westend61</figcaption></figure>
        <div class="bpa-richtext"><p><span>Der sogenannte </span><span lang="en-GB">Cyber Resilience Act</span><span> (CRA) legt erstmalig ein Mindestmaß an Cybersicherheit für alle vernetzten Produkte fest.</span></p>
        <h3>Wann tritt der CRA in Kraft?</h3><p>Die Umsetzung erfolgt in verschiedenen Etappen, bis Ende 2027.</p></div></div></div></div></main>
      <footer>Impressum</footer></body></html>`;
    const base = "https://www.bundesregierung.de/breg-de/aktuelles/cyberresilienz-2426502";
    expect((await extractContent(html, base)).text).toContain("per Facebook teilen");
    const content = await extractContent(html, base, "div.bpa-article .bpa-richtext");
    // The picture's caption and credit are not the article's text.
    expect(content.text).toBe(
      "Der sogenannte Cyber Resilience Act (CRA) legt erstmalig ein Mindestmaß an Cybersicherheit für alle vernetzten Produkte fest.\nWann tritt der CRA in Kraft?\nDie Umsetzung erfolgt in verschiedenen Etappen, bis Ende 2027.",
    );
    expect(content.imageUrl).toBe("https://www.bundesregierung.de/resource/image/2427030/og.jpg");
  });

  it("keeps a gov.za notice's fields, with the public-comment deadline, and leaves the menus out", async () => {
    // Trimmed from /documents/notices/standards-act-standards-matters-comments-invited-09-oct-2026 (16 Oct).
    const html = `<html><body><a href="#main-content">Skip to main content</a><form><label>Search gov.za</label><button>Search</button></form>
      <aside><div class="field--name-body"><p>The Government Gazette is published on the Government Printing Works' website</p></div></aside>
      <main role="main"><h1 class="page-title"><span>Standards Act: Standards Matters: Comments invited</span></h1>
      <article data-history-node-id="846491" class="node"><div class="node-content"><div class="field field--name-field-gcisdoc-files"><div class="field__label">Files</div>
      <table><thead><tr>
        <th>Attachment</th>
        <th>Size</th>
      </tr></thead><tbody><tr>
        <td><a href="/sites/default/files/gcis_document/202610/55525gen4190.pdf" type="application/pdf">55525gen4190.pdf</a></td>
        <td>389.25 KB</td>
      </tr></tbody></table></div>
      <div class="field field--name-field-comment-by"><div class="field__label">Comment by</div><div class="field__item"><time datetime="2026-12-08T12:00:00Z">Tuesday, December 8, 2026 - 12:00</time></div></div>
      <div class="grid"><h3>Share this page</h3><a class="social-link facebook"><div class="inline">Facebook</div></a></div>
      </div></article></main></body></html>`;
    const base = "https://www.gov.za/documents/notices/standards-act-standards-matters-comments-invited-09-oct-2026";
    expect((await extractContent(html, base)).text).toContain("Skip to main content");
    expect(await extractContent(html, base, "article.node .field")).toEqual({
      text: "Files\nAttachment\nSize\n55525gen4190.pdf\n389.25 KB\nComment by\nTuesday, December 8, 2026 - 12:00",
      imageUrl: null,
    });
  });

  it("keeps the Grand National Assembly's news text without the site footer", async () => {
    // Trimmed from /Haber/Detay?Id=377f1763-9427-47f8-b58e-01a13a00ae7c (16 Oct).
    const html = `<html><body><div class="page-content"><div id="content-title-type"><a href="/meclis-haber/meclis-baskani">MECLİS HABERLERİ</a></div>
      <div id="detay-content"><div class="blog-content"><div id="haber-detay-baslik"><div id="haber-detay-saat-dakika"> 2026-10-14 - 13:41</div>
      <div class="mobile-social-media"><a class="a-whatsapp" href="whatsapp://send"><img src="/images/yeni_tasarim/whatsapp.png"></a></div>
      &#x130;Y&#x130; PART&#x130; TBMM GRUP TOPLANTISI</div>
      <div id="haber-detay-ozet">İYİ Parti Genel Başkanı Müsavat Dervişoğlu, fon soruşturmalarına ilişkin açıklama yaptı.</div>
      <div id="haber-detay-aciklama"><p>Dervişoğlu, partisinin TBMM Grup Toplantısı'nda konuştu.</p></div></div></div></div>
      <div class="footer-area"><a href="/cerez-politikasi">Çerez Politikası</a><h4>BİZE ULAŞIN</h4><p>Atatürk Bulvarı TBMM 06543</p><p>0 (312) 420 50 00</p></div></body></html>`;
    const base = "https://www.tbmm.gov.tr/Haber/Detay?Id=377f1763-9427-47f8-b58e-01a13a00ae7c";
    expect((await extractContent(html, base)).text).toContain("BİZE ULAŞIN");
    expect((await extractContent(html, base, "#detay-content")).text).toBe(
      "2026-10-14 - 13:41\nİYİ PARTİ TBMM GRUP TOPLANTISI\nİYİ Parti Genel Başkanı Müsavat Dervişoğlu, fon soruşturmalarına ilişkin açıklama yaptı.\nDervişoğlu, partisinin TBMM Grup Toplantısı'nda konuştu.",
    );
  });

  it("stops reading a page once its text is long enough, whatever the page's size", async () => {
    // An Argentine norm is mostly <br> and text: 198 KB took about 25 ms locally to read whole (#71 review).
    const line = "ARTÍCULO 1°.- Apruébase el Plan Nacional de Abordaje Integral de Salud Vascular 2026-2030.<br>";
    const html = `<html><head><meta property="og:image" content="/og.jpg"></head><body><p>${line.repeat(3000)}</p><p>LAST LINE</p></body></html>`;
    const whole = await extractContent(html, "https://servicios.infoleg.gob.ar/x");
    expect(whole.text).toContain("LAST LINE");
    const cut = await extractContent(html, "https://servicios.infoleg.gob.ar/x", undefined, 20_000);
    expect(cut.text.length).toBeGreaterThanOrEqual(20_000);
    expect(cut.text.length).toBeLessThan(30_000);
    expect(cut.text).not.toContain("LAST LINE");
    expect(whole.text.startsWith(cut.text)).toBe(true);
    expect(cut.imageUrl).toBe("https://servicios.infoleg.gob.ar/og.jpg");
    // A short page is read whole.
    expect((await extractContent(`<body><main>${"<p>Short decree text.</p>".repeat(20)}</main></body>`, "https://x.gov/", undefined, 20_000)).text).toHaveLength(
      20 * "Short decree text.".length + 19,
    );
  });

  it("with a cap, still prefers main over body while main is being read", async () => {
    const html = `<body><div>${"Menu entry that is not a nav element. ".repeat(10)}</div><main><p>${"Decision of the cabinet. ".repeat(100)}</p></main><div>${"Footer text. ".repeat(500)}</div></body>`;
    const content = await extractContent(html, "https://x.gov/", undefined, 1000);
    expect(content.text.startsWith("Decision of the cabinet.")).toBe(true);
    expect(content.text).not.toContain("Menu entry");
  });

  it("reads a Chamber of Deputies bill record without menus, also with CRLF line ends", async () => {
    const html = [
      `<html><body><div id="portal-breadcrumbs">Página Inicial / Atividade Legislativa / PL 5576/2026</div>`,
      `<div id="content"><span id="barraFuncoesTopo">Versões\r\npara impressão</span>`,
      `<div id="identificacaoProposicao"><p id="colunaPrimeiroAutor"><strong>Autor</strong><br />\r\n\t\t\tJosé Medeiros - PL/MT\r\n</p>`,
      `<p><strong>Apresentação</strong><br />15/10/2026</p>`,
      `<p><strong>Ementa</strong><br /> <span class="textoJustificado">Institui mecanismos para o aproveitamento da capacidade assistencial ociosa dos prestadores privados de serviços de saúde.\r\n\r\n</span></p></div>`,
      `<div id="informacoesDeTramitacao">Regime de Tramitação\r\n.\r\n</div></div></body></html>`,
    ].join("\r\n");
    const content = await extractContent(html, "https://www.camara.leg.br/propostas-legislativas/2647775", "#identificacaoProposicao");
    expect(content.text).toBe(
      "Autor\nJosé Medeiros - PL/MT\nApresentação\n15/10/2026\nEmenta\nInstitui mecanismos para o aproveitamento da capacidade assistencial ociosa dos prestadores privados de serviços de saúde.",
    );
    expect((await extractContent(html, "https://www.camara.leg.br/x")).text).not.toContain("\r");
  });
});

describe("findLink", () => {
  it("finds the InfoLEG link to a norm's full text, as an absolute URL", async () => {
    const html = `<div id="Textos_Completos"><p><strong>Resolución&nbsp;1445/2026 MINISTERIO DE SALUD</strong></p>
      <p><strong> Resumen:</strong><br/>APRUEBASE EL PLAN NACIONAL DE ABORDAJE INTEGRAL DE SALUD VASCULAR 2026-2030.</p>
      <p><a href='anexos/430000-434999/431253/norma.htm'><b>Texto completo de la norma</b></a></p>
      <p><a href="/infolegInternet/verVinculos.do?modo=1&amp;id=431253">Esta norma modifica o complementa a 3 norma(s).</a></p></div>`;
    const base = "https://servicios.infoleg.gob.ar/infolegInternet/verNorma.do?id=431253";
    expect(await findLink(html, base, "a[href$='norma.htm']")).toBe("https://servicios.infoleg.gob.ar/infolegInternet/anexos/430000-434999/431253/norma.htm");
    expect(await findLink(html, base, "a[href*='verVinculos']@href")).toBe("https://servicios.infoleg.gob.ar/infolegInternet/verVinculos.do?modo=1&id=431253");
    expect(await findLink(html, base, "a.missing")).toBeNull();
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
