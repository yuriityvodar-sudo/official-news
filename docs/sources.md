# Sources

The list of official sites the fetcher reads lives in [sources.csv](sources.csv): one row per source. Every source was checked by hand on 2026-10-14: official (how is in `verified_by` and `evidence`), allowed by `robots.txt`, no bot check, items and dates in the page itself, and mostly official decisions (laws, bills, decrees, cabinet decisions, meeting agendas and outcomes).

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
- `itemPages`: `false` never opens item pages (robots.txt forbids it, or they are built by JavaScript); the list text is used.
- `textSelector`: CSS selector of the main text on item pages (default `main`, then `article`, then `body`). Set it when the page holds more than the article (menus, share links): only the text inside is kept, and reading the page costs far less CPU (#71: a 130 KB page, 4.8 ms locally without, 1.1 to 1.5 ms with). One selector, not a list.
- `fullText` (#71): where the whole text is when the item page does not hold it (built by JavaScript, or the text is on another official site). Read instead of the item page. A list of steps, or one step: `from` is a regular expression on the item link (first step) or on the previous step's result, whose groups fill `{1}`, `{2}`… in `url` (default `{0}`, the result as it is); `json` is the dotted path to the result in a JSON answer; `link` follows the first element matching a CSS selector on a page (`selector@attr`, default `href`); `encoding` is the answer's character set when the server does not send one. The last step's answer is the text: its `json` value (HTML is turned into text), or the page's main text (`textSelector` applies). Every URL must be on the source's site or in `allowedHosts`, over https, and allowed by its robots.txt. At most 3 steps, each answer at most 200 KB, and one read counts as one page of the run's budget. An item whose link `from` does not match keeps its list text. Examples: the European Commission (one JSON step) and Argentina (JSON, then a link, then the page) in `sources.csv`.
- `encoding`: character set when the server does not send one, e.g. `iso-8859-1`.
- `newStageIsNewItem`: a new date on the same link is a new item (bill stages); the stored URL gets `#YYYY-MM-DD`.
- `crawlDelaySeconds`: wait between our requests to the site (from its robots.txt).
- `allowedHosts`: other hosts whose links count as the source's own (Brazil's open-data API links to `www.camara.leg.br`). Links to any other site are dropped.
- `conditionalGet`: send `If-Modified-Since` with the last check time; the site answers 304 when nothing changed, so a big list is not downloaded again (China's 266 KB archive).
- `textDays`: days to keep the extracted text (default 30).
- `note`: anything else people should know.

**Feeds (`kind: rss`)**: RSS 2.0, RSS 1.0 and Atom are read without settings. `title`: another element holds the title (e.g. `description`). `date.field`: another element holds the date (e.g. `valueDate`).

**Pages (`kind: page`)**: `item` selects one list entry; inside it `link` (default `a`, reads `href`), `title` (default: the link's text), `summary`, `image`, `category` are CSS selectors. `selector@attr` reads an attribute; `@attr` reads the item element itself.

**APIs (`kind: api`)**: `items` is the dotted path to the list (empty for a top-level list); `itemRoot` a path inside each entry; `title`, `link`, `text` and `key` are paths or `{path}` templates. A string holding JSON is parsed when a path goes through it. `keep`: `{ "path": "regex" }`, entries that do not match are skipped. `key` is added to the stored URL so one link can hold several items.

**Teasers (#71)**: list text under 1,000 characters is a teaser. Its item page (or `fullText`) is read for the whole text, also when the list has a picture, and the item waits for the run's page budget rather than being saved with the teaser. The page's text replaces the list text only when it is longer. A site that answers 429 or 5xx, or does not answer, is not asked again in that run; its items wait for a later check while they are under 24 hours old, then are saved with the teaser. Check a new source's stored text length after its first day: under 1,000 characters for most items means a teaser, so find where its whole text is (item page selector, `fullText`).

**Dates (`date`)**: without settings, ISO 8601, feed dates and day-first `dd/mm/yyyy` are understood. `selector` + `attr` (pages), `field` (feeds; APIs accept a list, first non-empty wins), `format` (`fr` for "14 octobre 2026", or a pattern with `yyyy mm dd HH MM`), `utcOffset` for local times without a zone (e.g. `+03:00`), `dateOnly` to ignore a meaningless time, `fromLink` (a regular expression whose group is `yyyymmdd` in the item link).

## Open points

- **Saudi Arabia: not in the list yet.** The only reachable official source, the Umm al-Qura gazette (`https://www.uqn.gov.sa/rssFeed/21`), forbids automated monitoring without written consent. We ask them before adding it. Everything else official there did not answer from abroad.
- **India:** PIB cabinet decisions (`pib.gov.in`) is the better source but blocks our fetcher's user agent; we ask PIB to allow it. Until then: Parliament's bill list, which is quiet between sessions (the health check must not call it stale then).
- **Russia:** the Kremlin site answered only over plain http from Kenya; the list now uses `https` (our rule). If Cloudflare cannot reach it either, source health shows it broken and we look for another source.
- **Retest from Cloudflare** once the fetcher runs; these did not answer from a test machine in Kenya and would be better sources: Türkiye's Official Gazette (`resmigazete.gov.tr`), Australia's Federal Register of Legislation (`legislation.gov.au`), Argentina's Boletín Oficial (`boletinoficial.gob.ar`), Brazil's Planalto legislation (`planalto.gov.br`).
- **Licences for a commercial launch:** Mexico (DOF), Canada (Parliament), South Africa (GCIS) and Saudi Arabia allow non-commercial use only without permission. Check before any paid feature.
- **Texts still short (#71):** South Africa's notices and Brazil's bills have their text only in a PDF (the Government Gazette notice; the bill's `urlInteiroTeor`), which the fetcher does not read yet: ZA is stored with the title only, BR with the ementa, author and date. A PDF cannot be read within 10 ms of CPU; Workers AI `toMarkdown` could convert it in one request, once we know whether a PDF conversion costs neurons. Mexico's DOF stays title only: `dof.gob.mx`'s robots.txt forbids its note pages; the ministry's SIDOF data service has the text (`https://sidof.segob.gob.mx/dof/sidof/notas/nota/{codigo}`, field `Nota.cadenaContenido`, allowed by SIDOF's robots.txt) and would work as a `fullText` step, but whether to read it is Yurii's decision.
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
