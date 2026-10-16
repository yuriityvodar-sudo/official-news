# Sources

The list of official sites the fetcher reads lives in [sources.csv](sources.csv): one row per source. Every source was checked by hand on 2026-10-14 (Poland, Czechia, Spain and Ukraine on 2026-10-16, #72): official (how is in `verified_by` and `evidence`), allowed by `robots.txt`, no bot check, items and dates in the page itself, and mostly official decisions (laws, bills, decrees, cabinet decisions, meeting agendas and outcomes).

## Changing the list

1. Edit `docs/sources.csv` in a pull request. `npm test` in `server/` checks every row.
2. After the merge, the deploy loads it into the live database by itself (`.github/workflows/deploy.yml`). On your laptop run `npm run sources:local`. Loading adds new rows and updates changed ones; it never touches `status` or check times, and removing a row does not delete the source (mark it `blocked` instead).

3. Removing a row stops the source: loading sets it to `blocked` (the row stays, because its articles point to it). Ids of the Kickoff seed sources cannot be reused.

Never add media, aggregators or trending lists, and never a site that needs a bot check, CAPTCHA or login to read. Sources are read over `https` only: plain `http` can be altered on the way, and we show the text as official.

**Official gazettes are allowed** (that is where decisions take effect), always with a title filter (`exclude`) for routine entries: exchange and interest rates, price indices, court edicts, company notices, tenders, routine appointments, technical standards. They never reach the AI, so they cost nothing.

## `config`

How the fetcher (item 6) reads a source, as JSON. Types: `server/src/fetcher/types.ts`.

**Any kind**
- `match` / `exclude`: keep or drop items whose `title` or `category` matches a regular expression; `(?i)` at the start ignores case.
- `itemPages`: `false` never opens item pages (robots.txt forbids it, or they are built by JavaScript); the list text is used. A source's `fullText` is still read when set (Argentina has both); robots.txt is checked for each of its URLs.
- `textSelector`: CSS selector of the main text on item pages (default `main`, then `article`, then `body`). Set it when the page holds more than the article (menus, share links, a site footer): only the text inside is kept, and reading the page costs far less CPU (#71, measured locally on a 122 KB Bundesregierung page: about 17 ms without, about 1 ms with). A selector list (`a, b`) works too, but keeps the handlers for the whole page, so it saves no CPU: prefer one selector. Picture captions (`figcaption`) are always left out.
- `fullText` (#71): where the whole text is when the item page does not hold it (built by JavaScript, or the text is on another official site). Read instead of the item page. A list of steps, or one step: `from` is a regular expression on the item link (first step) or on the previous step's result, whose groups fill `{1}`, `{2}`… in `url` (default `{0}`, the result as it is); `json` is the dotted path to the result in a JSON answer, or a list of paths whose results are joined in order (in the last step; before it the first found is used), where `*` goes through each entry of a list and after `*.` a `{path}` template is filled from each entry (the Commission's quotes: `docuLanguageResource.dolaQuoteResources.*.{author.authorName}: {extract}`); `link` follows the first element matching a CSS selector on a page (`selector@attr`, default `href`); `encoding` is the answer's character set when the server does not send one. The last step's answer is the text: its `json` value (HTML is turned into text), or the page's main text (`textSelector` applies). Every URL must be on the source's site or in `allowedHosts`, over https, and allowed by its robots.txt. At most 3 steps, each answer at most 200 KB, and one read counts as one page of the run's budget. An item whose link `from` does not match keeps its list text. Examples: the European Commission (one JSON step) and Argentina (JSON, then a link, then the page) in `sources.csv`.
- `encoding`: character set when the server does not send one, e.g. `iso-8859-1`.
- `newStageIsNewItem`: a new date on the same link is a new item (bill stages); the stored URL gets `#YYYY-MM-DD`.
- `crawlDelaySeconds`: wait between our requests to the site (from its robots.txt).
- `allowedHosts`: other hosts whose links count as the source's own (Brazil's open-data API links to `www.camara.leg.br`). Links to any other site are dropped.
- `conditionalGet`: send `If-Modified-Since` with the last check time; the site answers 304 when nothing changed, so a big list is not downloaded again (China's 266 KB archive).
- `textDays`: days to keep the extracted text (default 30).
- `note`: anything else people should know.

**Feeds (`kind: rss`)**: RSS 2.0, RSS 1.0 and Atom are read without settings. `title`: another element holds the title (e.g. `description`). `date.field`: another element holds the date (e.g. `valueDate`).

**Pages (`kind: page`)**: `item` selects one list entry; inside it `link` (default `a`, reads `href`), `title` (default: the link's text), `summary`, `image`, `category` are CSS selectors. `selector@attr` reads an attribute; `@attr` reads the item element itself. A list such as `.card-time, .card-date` takes the first element in the item that matches any part; every part is looked for inside the item only.

**APIs (`kind: api`)**: `items` is the dotted path to the list (empty for a top-level list); `itemRoot` a path inside each entry; `title`, `link`, `text` and `key` are paths or `{path}` templates. A string holding JSON is parsed when a path goes through it. `keep`: `{ "path": "regex" }`, entries that do not match are skipped. `key` is added to the stored URL so one link can hold several items.

**Teasers (#71)**: list text under 1,000 characters is a teaser. Its item page (or `fullText`) is read for the whole text, also when the list has a picture, and the item waits for the run's page budget rather than being saved with the teaser. The read text replaces the list text when it is longer and already holds it (its start or its end); otherwise the list text stays in front of it (Germany's lead, SAIJ's summary). A page is read only up to 20,000 characters of text, whatever its size, and a text that long counts as both pages of the run. A site that answers 429 or 503, or cannot be reached, is not asked again in that run; another 5xx or no answer in time is that page only, and the site's other pages are still read (after 3 such pages in a run the site counts as busy). Pages that failed do not use the run's page budget. Items whose text could not be read wait for a later check while they are under 24 hours old, then are saved with the teaser. Check a new source's stored text length after its first day: under 1,000 characters for most items means a teaser, so find where its whole text is (item page selector, `fullText`).

**Dates (`date`)**: without settings, ISO 8601, feed dates and day-first `dd/mm/yyyy` are understood. `selector` + `attr` (pages), `field` (feeds; APIs accept a list, first non-empty wins), `format` (`fr` for "14 octobre 2026"; `uk` for "16 жовтня 2026", "15 жовтня 17:34" or "12:31, 16 жовтня", where no year means the latest such date; or a pattern with `yyyy mm dd HH MM`), `utcOffset` for local times without a zone (e.g. `+03:00`), `dateOnly` to ignore a meaningless time, `fromLink` (a regular expression whose group is `yyyymmdd` in the item link).

## Open points

- **Saudi Arabia: not in the list yet.** The only reachable official source, the Umm al-Qura gazette (`https://www.uqn.gov.sa/rssFeed/21`), forbids automated monitoring without written consent. We ask them before adding it. Everything else official there did not answer from abroad.
- **India:** PIB cabinet decisions (`pib.gov.in`) is the better source but blocks our fetcher's user agent; we ask PIB to allow it. Until then: Parliament's bill list, which is quiet between sessions (the health check must not call it stale then).
- **Russia:** the Kremlin site answered only over plain http from Kenya; the list now uses `https` (our rule). If Cloudflare cannot reach it either, source health shows it broken and we look for another source.
- **Retest from Cloudflare** once the fetcher runs; these did not answer from a test machine in Kenya and would be better sources: Türkiye's Official Gazette (`resmigazete.gov.tr`), Australia's Federal Register of Legislation (`legislation.gov.au`), Argentina's Boletín Oficial (`boletinoficial.gob.ar`), Brazil's Planalto legislation (`planalto.gov.br`).
- **Spain: the Official State Gazette (BOE) comes with a robots.txt change.** Section I (`https://www.boe.es/rss/boe.php?s=1`: royal decrees, orders, laws, about 2 to 5 a day) reads with today's `rss` kind and an `exclude` for `Sumario`, `Corrección de errores` and `Sentencia`, and robots.txt allows the feed and the item pages (`/diario_boe/txt.php?id=…`, text in `#textoxslt`). But that robots.txt is 494 KB with 12,312 rules, and the fetcher reads and checks it in every run: measured 16 Oct in the Workers runtime on a laptop, parsing takes 2 to 4 ms and checking the 3 URLs of one run 14 ms warm and 88 ms cold, against 10 ms of CPU per run. Add it together with robots.txt handling that keeps the verdict between runs, or reads only the rules that can match. `boe.es` is not a `gob.es` domain, so its row needs `portal` or `wikidata`. Until then Spain has La Moncloa's weekly Council of Ministers summaries.
- **Ukraine: only the Cabinet's home page.** The Verkhovna Rada (`zakon.rada.gov.ua`, `rada.gov.ua`, `data.rada.gov.ua`, `itd.rada.gov.ua`) resolves in DNS but did not answer a test machine abroad (TCP timeouts on 15 and 16 Oct); `president.gov.ua` answers its robots.txt with an Akamai 403; the Cabinet's RSS (`/api/rss`), its acts list (`/npas/`) and `/timeline` (where `/news` redirects) are disallowed by robots.txt. The home page dates its cards without a year in Kyiv time; on a busy meeting day, more decisions than the home page shows (about 12 latest) between two checks would be missed.
- **Czechia:** the binding government resolutions (`odok.gov.cz`) are `Disallow: /`; e-Sbírka (`e-sbirka.gov.cz`) is a JavaScript app with a CAPTCHA key; the Chamber's Collection of Laws list (`https://www.psp.cz/sqw/sbirka.sqw`) is allowed but needs windows-1250 decoding and a parser for its flat list.
- **Poland:** `dziennikustaw.gov.pl`, `monitorpolski.gov.pl`, `isap.sejm.gov.pl` and `www.sejm.gov.pl` disallow every agent except Googlebot, so the Journal of Laws comes from the Sejm's ELI API. gov.pl lists 10 decisions a page and only the first page is read. A Council of Ministers regulation can show twice, on purpose: gov.pl lists it when the cabinet adopts it (with its text), the Journal of Laws a day or more later when it is published (title and keywords). It stays in the Journal of Laws because not every one reaches gov.pl's list: checked 16 Oct, of the 2 cabinet regulations published 30 Sep to 15 Oct, DU/2026/1327 (13 Oct, ARiMR) is on gov.pl and DU/2026/1309 (2 Oct, open pension funds) is not on its 3 latest pages (22 Sep to 13 Oct).
- **Licences for a commercial launch:** Mexico (DOF), Canada (Parliament), South Africa (GCIS) and Saudi Arabia allow non-commercial use only without permission. gov.pl text is CC BY-SA 4.0 (share-alike: check what it asks of our summaries), and gov.pl pictures, audio and video are CC BY-NC-ND 4.0 (non-commercial, no derivatives) unless a page says otherwise; the app shows gov.pl preview pictures today. Check before any paid feature.
- **Spain: La Moncloa's reuse terms ask for a set citation and a date** (`https://www.lamoncloa.gob.es/Paginas/es_AvisoLegal.aspx`, read 16 Oct): the source cited as "Origen de los datos: sitio web de lamoncloa.gob.es. Ministerio de la Presidencia." and the date of the last update of the information used. The article screen shows the source's name, "Official source", the publication date and the link to the page, but not that wording or a last-update date. To settle: a citation line for this source on the article screen (the source's own wording, with the publication date as the update date), or confirm with La Moncloa that the source line and link are enough.
- **Texts still short (#71):** South Africa's notices and Brazil's bills have their text only in a PDF (the Government Gazette notice; the bill's `urlInteiroTeor`), which the fetcher does not read yet: ZA is stored with the notice's fields only (the PDF's name and size, and the public-comment deadline when there is one), BR with the ementa, author and date. A PDF cannot be read within 10 ms of CPU; Workers AI `toMarkdown` could convert it in one request, once we know whether a PDF conversion costs neurons. Mexico's DOF stays title only: `dof.gob.mx`'s robots.txt forbids its note pages; the ministry's SIDOF data service has the text (`https://sidof.segob.gob.mx/dof/sidof/notas/nota/{codigo}`, field `Nota.cadenaContenido`, allowed by SIDOF's robots.txt) and would work as a `fullText` step, but whether to read it is Yurii's decision.
- **Not used on purpose:** `hcdn.gob.ar` (Argentina's Chamber of Deputies) lists AI agents by name as disallowed in `robots.txt`.

## Backups

If a source breaks, the research found these second choices (same country, also checked on 2026-10-14):

| Country | Backup | URL |
| --- | --- | --- |
| US | Federal Register, presidential documents | `https://www.federalregister.gov/api/v1/documents.rss?conditions%5Btype%5D%5B%5D=PRESDOCU&order=newest` |
| CA | Canada Gazette, Part II (regulations) | `https://gazette.gc.ca/rss/p2-eng.xml` |
| MX | DOF data service (SIDOF) | `https://sidof.segob.gob.mx/dof/sidof/notas/{DD-MM-YYYY}` |
| BR | Central Bank regulations | `https://www.bcb.gov.br/api/feed/app/normativos/normativos?ano={YYYY}` |
| AR | Senate votes | `https://www.senado.gob.ar/votaciones/actas` |
| GB | Parliament, government bills (API) | `https://bills-api.parliament.uk/api/v1/Bills?SortOrder=DateUpdatedDescending&BillType=1&Take=20` |
| DE | Federal Law Gazette, Part I | `https://www.recht.bund.de/rss/feeds/rss_bgbl-1.xml?nn=211452` |
| FR | Senate texts | `https://www.senat.fr/rss/textes.rss` |
| IT | Official Gazette, general series | `https://www.gazzettaufficiale.it/rss/SG` |
| EU | Official Journal acts of Council and Parliament (SPARQL) | `https://publications.europa.eu/webapi/rdf/sparql` |
| RU | Government documents | `http://government.ru/docs/rss/` |
| TR | Parliament committee news | `https://www.tbmm.gov.tr/meclis-haber/komisyon` |
| ZA | Cabinet statements | `https://www.gov.za/news/cabinet-statements` |
| AU | Treasury consultations (proposals; item pages are JavaScript-only, so list titles only) | `https://treasury.gov.au/consultation` |
| CN | Ministry of Commerce policies | `https://www.mofcom.gov.cn/zwgk/zcfb/index.html` (data call in the research notes) |
| IN | Directorate General of Foreign Trade notifications | `https://www.dgft.gov.in/CP/?opt=notification` |
| JP | e-Gov new laws (API) | `https://laws.e-gov.go.jp/api/2/laws?promulgation_date_from={date}&limit=100` |
| KR | Cabinet meeting laws | `https://www.moleg.go.kr/board.es?mid=a10105040000&bid=0093` |
| ID | State Secretariat legal database (POST API) | `https://jdih.setneg.go.id/api/hukumproduk/produkhukum` |
| SA | Umm al-Qura, Council of Ministers news | `https://www.uqn.gov.sa/news/council-of-ministers` (same consent needed) |
| PL | Sejm, legislative processes passed (API; checked 16 Oct: dates move in batches on old processes, and `term10` changes after the 2027 election) | `https://api.sejm.gov.pl/sejm/term10/processes/passed?limit=20&sort_by=-lastModified` |
| CZ | Chamber of Deputies, Collection of Laws list (checked 16 Oct; needs windows-1250 and a parser first) | `https://www.psp.cz/sqw/sbirka.sqw` |
| ES | La Moncloa, Council of Ministers references, the full record (checked 16 Oct) | `https://www.lamoncloa.gob.es/Paginas/rss.aspx?tipo=16` |
