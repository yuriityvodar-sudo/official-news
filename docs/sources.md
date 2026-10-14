# Sources

The list of official sites the fetcher reads lives in [sources.csv](sources.csv): one row per source. Every source was checked by hand on 2026-10-14: official (how is in `verified_by` and `evidence`), allowed by `robots.txt`, no bot check, items and dates in the page itself, and mostly official decisions (laws, bills, decrees, cabinet decisions, meeting agendas and outcomes).

## Changing the list

1. Edit `docs/sources.csv` in a pull request. `npm test` in `server/` checks every row.
2. After the merge, the deploy loads it into the live database by itself (`.github/workflows/deploy.yml`). On your laptop run `npm run sources:local`. Loading adds new rows and updates changed ones; it never touches `status` or check times, and removing a row does not delete the source (mark it `blocked` instead).

Never add media, aggregators or trending lists, and never a site that needs a bot check, CAPTCHA or login to read.

## `config`

Hints for the fetcher (item 6), as JSON. A draft from the research; item 6 settles the final keys.

- `match` / `exclude`: keep or drop items by `title` or `category` (regular expressions).
- Pages (`kind: page`): CSS selectors for `item`, `link`, `title`, `date`, `category`, `summary`, `image`; `@attr` reads an attribute.
- APIs (`kind: api`): where the list is (`items`) and which fields hold `title`, `date` and `link`.
- `date`: a field, selector or format when the date is not a standard feed date.
- `itemPages: false`: do not open item pages (robots.txt forbids it); summarize from the list text.
- `note`: anything else the fetcher needs to know.

## Open points

- **Saudi Arabia: not in the list yet.** The only reachable official source, the Umm al-Qura gazette (`https://www.uqn.gov.sa/rssFeed/21`), forbids automated monitoring without written consent. We ask them before adding it. Everything else official there did not answer from abroad.
- **India:** PIB cabinet decisions (`pib.gov.in`) is the better source but blocks our fetcher's user agent; we ask PIB to allow it. Until then: Parliament's bill list, which is quiet between sessions (the health check must not call it stale then).
- **Retest from Cloudflare** once the fetcher runs; these did not answer from a test machine in Kenya and would be better sources: Türkiye's Official Gazette (`resmigazete.gov.tr`), Australia's Federal Register of Legislation (`legislation.gov.au`), Argentina's Boletín Oficial (`boletinoficial.gob.ar`), Brazil's Planalto legislation (`planalto.gov.br`).
- **Licences for a commercial launch:** Mexico (DOF), Canada (Parliament), South Africa (GCIS) and Saudi Arabia allow non-commercial use only without permission. Check before any paid feature.
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
