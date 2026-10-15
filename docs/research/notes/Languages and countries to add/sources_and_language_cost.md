# Candidate countries and the cost of adding a language (status 2026-10-15)

How to read the evidence in these notes:

- **"Probe"** means a live HTTP request I made on 2026-10-15 with `curl` from a test machine. Cloudflare's trace showed it on a **Kenyan IP** (`loc=KE`, served by colo `MRS`), using the user agent `Mozilla/5.0 (compatible; research-check)`. A probe shows what that request got back. It does **not** show what a Cloudflare Worker gets back: Workers leave from Cloudflare IPs, send their own user agent, and may be treated differently.
- **"Second vantage"** means the WebFetch tool's own servers (location not confirmed, probably the US).
- **"Repo"** means files in this repository (`docs/sources.csv`, `docs/decisions.md`, `server/src/summarizer/*`).
- **Estimates are labelled as estimates.** All arithmetic is shown.

---

## Part 1, Q1: Can new official acts be found automatically (RSS/Atom, API, machine-readable lists)? What do robots.txt and bot checks say, and is there official English?

### Takeaway
Most candidates have at least one clean, machine-readable route:

- **Poland:** Sejm ELI API.
- **Spain:** BOE JSON API and RSS.
- **Austria:** RIS OGD API.
- **EU:** EUR-Lex RSS, the European Parliament Open Data API and the Council RSS.
- **Czech Republic:** government RSS.
- **Kazakhstan:** Akorda RSS.
- **Nigeria:** State House RSS.
- **South Africa:** gov.za feeds.
- **Kenya:** the Kenya Law gazette list.
- **Brazil:** the Senate API, on top of the Chamber API already in use.

The hard cases are:

- **Ukraine:** the Rada sites did not answer from outside Ukraine. The Cabinet's acts list and RSS are both blocked by its robots.txt. The President's site returned "Access Denied".
- **France:** Légifrance sits behind a Cloudflare challenge, though the DILA bulk dumps are open.
- **Germany:** the Bundestag DIP API needs a key, and recht.bund.de asks for a 30-second crawl delay.
- **UAE:** the legislation site is behind a Cloudflare block.
- **Morocco:** the government site is behind a Cloudflare challenge.
- **Egypt, Indonesia's peraturan.go.id and Argentina's Boletín Oficial:** did not answer at all.

### Cited Findings

**Ukraine**
- `zakon.rada.gov.ua`, `data.rada.gov.ua` and `www.rada.gov.ua` all **timed out** (20 s, no TCP answer) in two separate probes from a Kenyan IP — [probe: data.rada.gov.ua](https://data.rada.gov.ua/), [probe: zakon.rada.gov.ua/laws/main/r](https://zakon.rada.gov.ua/laws/main/r).
- From the second vantage, `data.rada.gov.ua` refused the connection (`ECONNREFUSED 193.19.153.66:443`) — [second vantage: data.rada.gov.ua/open/main/api](https://data.rada.gov.ua/open/main/api).
- The Rada does run an open-data portal in Ukrainian and English. OpenSanctions says commercial use of its MP data needs a data licence — [OpenSanctions: ua_rada](https://www.opensanctions.org/datasets/ua_rada/).
- I found **no public documentation** saying the Rada blocks foreign IPs. A search turned up only the precedent of the State Tax Service, which unblocks foreign users on request by static IP — [7eminar: unblocking DPS services from abroad](https://7eminar.ua/news/4261-yak-rozblokuvati-dostup-do-servisiv-dps-z-za-mez-ukrayini).
- `kmu.gov.ua` robots.txt for all user agents disallows `/api/`, `/timeline`, `/npas/`, `/npasearch*`, `/backend/` and `/storage/` — [probe: kmu.gov.ua/robots.txt](https://www.kmu.gov.ua/robots.txt).
  - The Cabinet's RSS lives at `/api/rss` and works (200, RSS 2.0, Ukrainian news), but it sits under the disallowed `/api/` — [probe: kmu.gov.ua/api/rss](https://www.kmu.gov.ua/api/rss).
  - `/npas` (normative acts) declares `/timeline?type=acts` as its canonical URL, which is also disallowed — [probe: kmu.gov.ua/npas](https://www.kmu.gov.ua/npas).
  - An English site exists: `kmu.gov.ua/en` returned 200 — [probe](https://www.kmu.gov.ua/en).
- `president.gov.ua` returned **403 "Access Denied"** in an Akamai-style reference format, both for robots.txt and for `/documents` — [probe: president.gov.ua/documents](https://www.president.gov.ua/documents).

**Czech Republic**
- The government (vlada.gov.cz) advertises RSS feeds at `/cs/urad/RSS/rss.xml` and `/en/rss.xml` on its RSS page — [probe: vlada.gov.cz RSS page](https://vlada.gov.cz/cz/urad-vlady/rss/rss-21080/).
  - Its robots.txt disallows `/pages/`, `/images/`, `/classes/`, `/css/`, `/data/`, `/errmsg/` and `/files/` (first lines read). I did not see the feed paths in the part I read — [probe: vlada.gov.cz/robots.txt](https://vlada.gov.cz/robots.txt).
  - An English site exists: `vlada.gov.cz/en/` returned 200 — [probe](https://vlada.gov.cz/en/).
- e-Sbírka (the official Collection of Laws) now redirects to `e-sbirka.gov.cz`. It is a JavaScript single-page app, and its `/robots.txt` returns the app's HTML rather than a robots file — [probe: e-sbirka.gov.cz/robots.txt](https://e-sbirka.gov.cz/robots.txt).
- The Ministry of the Interior says e-Sbírka offers a REST API and open data. It recommended connecting production services only **after 15 January 2026**, because fragment identifiers and the data structure could change until then — [MV: limits of e-Sbírka during the e-Legislativa rollout](https://mv.gov.cz/npo/clanek/omezeni-e-sbirky-spojene-s-postupnym-spoustenim-e-legislativy-do-ostreho-provozu.aspx).
- Critics say e-Sbírka's open data lacks documentation and fails several open-data criteria — [Lupa.cz: "e-Sbírka ukazuje, jak neotevírat data"](https://www.lupa.cz/clanky/e-sbirka-ukazuje-jak-neotevirat-data/).
- The open-data host `opendata.eselpoint.cz` failed with a TLS certificate error — [probe](https://opendata.eselpoint.cz/).
- The e-Sbírka system was due to move to the state cloud, with logins unavailable for a time (notice from March 2026) — [MV: planned outage of eSeL](https://mv.gov.cz/bsmv/clanek/planovana-odstavka-systemu-esel-e-sbirka-a-e-legislativa.aspx).
- Chamber of Deputies (psp.cz): robots.txt disallows only asset paths and `/ib` and `/cgi-bin/ascii/ib` in the part I read — [probe: psp.cz/robots.txt](https://www.psp.cz/robots.txt).

**Poland**
- The Sejm ELI API `api.sejm.gov.pl/eli/acts/DU/2026` returned JSON with `"count":1335` items for Dziennik Ustaw 2026 — [probe](https://api.sejm.gov.pl/eli/acts/DU/2026).
  - Each item has `title`, `promulgation`, `changeDate` (the latest was 2026-10-15T09:41:54), `textPDF` and `textHTML`.
  - `api.sejm.gov.pl` has no robots.txt (404), so nothing is disallowed — [probe](https://api.sejm.gov.pl/robots.txt).
- The Sejm prints endpoint `api.sejm.gov.pl/sejm/term10/prints` works but is heavy: 1.86 MB in 13.5 s — [probe](https://api.sejm.gov.pl/sejm/term10/prints).
- ISAP (`isap.sejm.gov.pl`) robots.txt allows only Googlebot and Nekstbot and disallows `/` for everyone else — [probe](https://isap.sejm.gov.pl/robots.txt).
- `gov.pl` robots.txt: `Allow: /` — [probe](https://www.gov.pl/robots.txt).

**Kazakhstan**
- Akorda (the President) has an RSS feed at `akorda.kz/ru/rss`: RSS 2.0, though served as `text/html` — [probe](https://www.akorda.kz/ru/rss).
  - Its robots.txt says `Allow: /` — [probe](https://www.akorda.kz/robots.txt).
  - An English site exists: `akorda.kz/en` returned 200 — [probe](https://www.akorda.kz/en).
- `primeminister.kz/ru/rss` returns only the text `<!-- RSS -->`, so that feed is empty — [probe](https://primeminister.kz/ru/rss). An English site exists: `primeminister.kz/en` returned 200 — [probe](https://primeminister.kz/en).
- Adilet (the national legal information system) robots.txt:
  - For all agents it allows act pages and disallows `/api/`, `/search` and `/advanced-search`.
  - It explicitly disallows AI **training** crawlers (GPTBot, ClaudeBot, CCBot and others).
  - Its comments say search/citation agents and agents fetching a page on a person's request are welcome, because findability of acts is a statutory duty — [probe: adilet.zan.kz/robots.txt](https://adilet.zan.kz/robots.txt).
- `gov.kz` robots.txt disallows `/legalacts/` — [probe](https://www.gov.kz/robots.txt).

**Spain**
- The BOE open-data API `boe.es/datosabiertos/api/boe/sumario/YYYYMMDD` returned JSON for 2026-10-15 (248 KB) when sent `Accept: application/json` — [probe](https://www.boe.es/datosabiertos/api/boe/sumario/20261015). Without an Accept header it returns 400: "No soportado ningún mime type de la cabecera Accept".
- The BOE RSS `boe.es/rss/boe.php?s=1` (section I, general provisions) works. It is encoded ISO-8859-1 — [probe](https://www.boe.es/rss/boe.php?s=1).
- BOE robots.txt disallows only the translated text views (`lang=ca, va, gl, eu, en, fr`) — [probe](https://www.boe.es/robots.txt).
- La Moncloa (the government) robots.txt is effectively empty (`#`). Its RSS feeds `/Paginas/rss.aspx?tipo=1` and `tipo=15` return `application/rss+xml` — [probe](https://www.lamoncloa.gob.es/Paginas/rss.aspx?tipo=1).
  - The Council of Ministers "referencias" page is reachable — [probe](https://www.lamoncloa.gob.es/consejodeministros/referencias/Paginas/index.aspx).
  - An English site exists — [probe](https://www.lamoncloa.gob.es/lang/en/Paginas/index.aspx).

**Spanish-speaking Latin America**
- **Mexico** is already in the repo: DOF `dof.gob.mx/sumario.xml`, RSS. Per the repo, robots.txt disallows `/nota_detalle.php`, and commercial reuse needs SEGOB consent — [Repo: docs/sources.csv; DOF aviso legal](https://dof.gob.mx/aviso_legal.html).
- **Argentina:** the Boletín Oficial (`boletinoficial.gob.ar`) **timed out** in three probes from Kenya and failed from the second vantage — [probe](https://www.boletinoficial.gob.ar/seccion/primera). The repo already uses SAIJ instead.
- **Colombia:**
  - Función Pública robots.txt: `Disallow:` (empty), so everything is allowed — [probe](https://www.funcionpublica.gov.co/robots.txt).
  - `presidencia.gov.co/normativa/decretos-2026` returned 200 with a **0-byte** body to curl, so it likely needs JavaScript — [probe](https://www.presidencia.gov.co/normativa/decretos-2026).
  - SUIN-Juriscol serves an app page (HTML) instead of robots.txt — [probe](https://www.suin-juriscol.gov.co/robots.txt).

**Brazil and Portugal**
- **Brazil:**
  - The Chamber of Deputies API is already in the repo — [Repo: docs/sources.csv](https://dadosabertos.camara.leg.br/howtouse/sobre-dados-abertos.html).
  - The Senate open-data API works, but `/dadosabertos/materia/tramitando` is 10.7 MB of XML and took 15 s — [probe](https://legis.senado.leg.br/dadosabertos/materia/tramitando).
  - `planalto.gov.br` redirects to `gov.br/planalto`. `www4.planalto.gov.br/legislacao/` reset the connection — [probe](https://www4.planalto.gov.br/legislacao/).
  - `in.gov.br` (the Diário Oficial da União) failed with an HTTP/2 PROTOCOL_ERROR to curl — [probe](https://www.in.gov.br/leiturajornal).
  - LexML robots.txt **disallows `/busca/`**, the path of its search/SRU interface — [probe](https://www.lexml.gov.br/robots.txt).
  - The Imprensa Nacional publishes the DOU in XML as open data under its Open Data Plan (Portaria nº 293/2018) — [IRIB: ITI and Imprensa Nacional modernisation](https://irib.org.br/noticias/detalhes/iti-certificacao-digital-icp-brasil-e-aliada-na-modernizacao-da-imprensa-nacional). I did not confirm the INLABS download or sign-up steps.
  - An English Planalto site exists — [probe](https://www.gov.br/planalto/en).
- **Portugal:**
  - `diariodarepublica.pt` is an OutSystems app that returns HTML for `/robots.txt` — [probe](https://diariodarepublica.pt/robots.txt).
  - `portugal.gov.pt` robots.txt says `Allow: /`, and an English site (`/en/gc25`) exists — [probe](https://www.portugal.gov.pt/robots.txt).
  - `parlamento.pt` has no robots.txt (404) — [probe](https://www.parlamento.pt/robots.txt).

**Germany and Austria**
- **Germany:**
  - recht.bund.de (the new federal law gazette) robots.txt sets **`Crawl-delay: 30`** and disallows `/SiteGlobals/` (except modules and styles) and `/de|en/serviceseiten/` — [probe](https://www.recht.bund.de/robots.txt).
  - The Bundestag DIP API answers 401: "An API key is required to access this service. Please refer to https://dip.bundestag.de/über-dip/hilfe/api how to apply for a key" — [probe](https://search.dip.bundestag.de/api/v1/vorgang?format=json).
  - The Bundesregierung RSS is already in the repo. An English site (`/breg-en`) exists — [probe](https://www.bundesregierung.de/breg-en).
- **Austria:**
  - The RIS OGD API v2.6 `data.bka.gv.at/ris/api/v2.6/Bundesrecht?Applikation=BgblAuth` returned JSON: 18,971 hits, with `BGBLA_2026_II_303` first — [probe](https://data.bka.gv.at/ris/api/v2.6/Bundesrecht?Applikation=BgblAuth).
  - The RIS **website** (`ris.bka.gv.at`) answered 503 with a "Security Check" page — [probe](https://www.ris.bka.gv.at/robots.txt).
  - Parliament robots.txt (12.5 KB) mostly lists single disallowed items, and the `*` group does not block the site — [probe](https://www.parlament.gv.at/robots.txt).

**France**
- Légifrance robots.txt returned **403 with a Cloudflare "Just a moment..." challenge** page — [probe](https://www.legifrance.gouv.fr/robots.txt).
- The DILA bulk open data (`echanges.dila.gouv.fr/OPENDATA/JORF/`) is a plain directory listing and was reachable — [probe](https://echanges.dila.gouv.fr/OPENDATA/JORF/).
- info.gouv.fr robots.txt disallows `/api/`, `/*recherche?` and `/*_Incapsula*`. The Incapsula reference suggests Imperva bot protection — [probe](https://www.info.gouv.fr/robots.txt).
- The Élysée list page is already in the repo.

**Turkey**
- The Resmî Gazete robots.txt names only Googlebot, Bingbot, Slurp and Yandex, with `Noindex:` lines for old PDFs. It has **no `User-agent: *` rules**, so nothing is disallowed for other agents — [probe](https://www.resmigazete.gov.tr/robots.txt). The home page returned 200 — [probe](https://www.resmigazete.gov.tr/).
- mevzuat.gov.tr robots.txt has the same pattern (Googlebot only) — [probe](https://www.mevzuat.gov.tr/robots.txt).
- `tccb.gov.tr/en/` (the Presidency, English) ended on a 302 that curl did not resolve — [probe](https://www.tccb.gov.tr/en/).

**Indonesia**
- `peraturan.go.id` **timed out** in three probes — [probe](https://peraturan.go.id/).
- JDIH Setneg robots.txt: `Disallow:` (empty), so everything is allowed. The home page is a 2.5 MB Next.js app — [probe](https://jdih.setneg.go.id/robots.txt).
- `dpr.go.id` (parliament) returned **403 Access Denied** — [probe](https://www.dpr.go.id/robots.txt).
- The Setkab RSS is already in the repo. An English site (`setkab.go.id/en/`) returned 200 — [probe](https://setkab.go.id/en/).

**Nigeria, Kenya, South Africa** (all publish officially in English)
- **Nigeria:** the State House WordPress RSS `statehouse.gov.ng/feed/` returned 200 `application/rss+xml`. Its robots.txt is the WordPress default (only `/wp-admin/` disallowed) — [probe](https://statehouse.gov.ng/feed/).
- **Kenya:**
  - Kenya Law robots.txt: `Allow: /`, `Disallow: /search/`, `Disallow: /api/`, **`Crawl-delay: 5`** — [probe](https://new.kenyalaw.org/robots.txt).
  - The Kenya Gazette list page returned 200 — [probe](https://new.kenyalaw.org/gazettes/).
  - Its advertised feed `/feeds/all.xml` returned **403** to our user agent — [probe](https://new.kenyalaw.org/feeds/all.xml).
- **South Africa:**
  - `gov.za` timed out in the first probe and answered 200 in 11.6 s in the second, so it is slow or intermittent — [probe](https://www.gov.za/documents/latest).
  - It advertises feeds including `/documents-feed`, `/news-feed` and `/speeches-feed` — [probe: gov.za/rss-feeds](https://www.gov.za/rss-feeds).

**Egypt, UAE, Morocco**
- **Egypt:** `cabinet.gov.eg` timed out from Kenya and refused the connection from the second vantage (`ECONNREFUSED 163.121.35.34:443`) — [probe](https://www.cabinet.gov.eg/).
- **UAE:** `uaelegislation.gov.ae` robots.txt says `Disallow:` (empty, everything allowed), but `/en` and `/en/legislations` returned **403 "Sorry, you have been blocked"** from Cloudflare — [probe](https://uaelegislation.gov.ae/en/legislations).
- **Morocco:**
  - The SGG Bulletin Officiel page (French) returned 200, and the SGG home page redirects to the Arabic site — [probe](https://www.sgg.gov.ma/BulletinOfficiel.aspx).
  - The government site `cg.gov.ma` returned **403 with a Cloudflare challenge** — [probe](https://www.cg.gov.ma/robots.txt).

**EU institutions**
- The EUR-Lex RSS `display-feed.rss?rssId=222` ("5 - Acts of the Official Journal L") returned 200 XML, dated Thu, 15 Oct 2026 — [probe](https://eur-lex.europa.eu/EN/display-feed.rss?rssId=222).
- EUR-Lex **HTML** pages (the OJ daily view) and its robots.txt returned **202 with an empty body**. That looks like a bot challenge, but this is an inference — [probe](https://eur-lex.europa.eu/oj/daily-view/L-series/default.html).
- The EUR-Lex web service is SOAP, free after registration, and has a daily query limit. Documents are downloaded through the Cellar REST API — [EUR-Lex: web service help](https://eur-lex.europa.eu/content/help/data-reuse/webservice.html?locale=es).
- The Cellar SPARQL endpoint answered 200 — [probe](https://publications.europa.eu/webapi/rdf/sparql).
- The European Parliament Open Data API v2 `adopted-texts?year=2026` returned JSON-LD with ELI ids (for example `eli/dl/doc/TA-10-2026-0006`) — [probe](https://data.europarl.europa.eu/api/v2/adopted-texts?year=2026&format=application%2Fld%2Bjson&limit=5). Its robots.txt sets `Crawl-delay: 2` — [probe](https://data.europarl.europa.eu/robots.txt).
- The Council press-release RSS returned 200 XML — [probe](https://www.consilium.europa.eu/en/rss/pressreleases.ashx). The Council's robots.txt, however, returned **403 "Browser check"** — [probe](https://www.consilium.europa.eu/robots.txt).

### Inferences
- **Easiest candidates (feed or API, no obstacles seen):**
  - Poland: the Sejm ELI API (adds the official Polish gazette, a clean JSON list).
  - Spain: BOE API/RSS and La Moncloa RSS.
  - Austria: RIS OGD API.
  - EU: EUR-Lex OJ L RSS and the EP adopted-texts API.
  - Czech Republic: vlada.gov.cz RSS.
  - Kazakhstan: Akorda RSS.
  - Nigeria: State House RSS.
  - South Africa: gov.za documents feed.
  - Turkey: Resmî Gazete daily page (robots does not restrict).
- **Workable with care:**
  - Germany: recht.bund.de at 30 s crawl delay, which is fine at one request per run. The DIP API needs a free key; a key is a secret, so it goes to Worker secrets.
  - Kenya: Kenya Law list pages with crawl delay 5. The feed blocks our user agent, so test with the Worker's own.
  - Brazil: the Senate API, but it needs filtered queries because the full list is 10 MB.
  - Portugal: portugal.gov.pt.
  - Colombia: Función Pública.
- **Hard or blocked from outside the country, or by bot protection:**
  - Ukraine: Rada, the Cabinet's acts list and RSS (robots.txt), the President's site.
  - France: Légifrance (Cloudflare challenge). Use the DILA dumps instead; they are daily tar.gz files, which are heavy for a Worker.
  - UAE (Cloudflare block) and Morocco's government site (challenge).
  - Egypt Cabinet, Argentina Boletín Oficial, Indonesia peraturan.go.id: no answer.
  - The project's rule "never bypass bot checks" excludes the challenge-protected HTML routes.
- **Ukraine specifically** may need a different official route, for example the Official Gazette of Ukraine or Uriadovyi Kurier (not checked here). Or a test from the real Worker: Cloudflare has Ukrainian data centres, but a Worker cannot choose where its fetch leaves from. Whether the Rada lets Cloudflare's IPs through can only be settled by a probe from the deployed Worker.
- **Several "allowed" robots files sit next to an explicitly disallowed `/api/`** (kmu.gov.ua, adilet.zan.kz, Kenya Law, info.gouv.fr). The fetcher has to check each feed path against robots.txt and not assume an RSS link is allowed.

### Gaps
- No probe ran from Cloudflare's network. Every reachability result could differ for a Worker; the one action that settles it is a one-off fetch from the deployed Worker that logs each status.
- No official statement found on whether the Rada (zakon/data.rada.gov.ua) geo-blocks foreign IPs. The Rada API terms (token or user-agent rules) could not be read because the site was unreachable.
- Not verified:
  - e-Sbírka REST API access terms (key or registration).
  - INLABS (DOU XML) sign-up.
  - Légifrance PISTE API terms.
  - Colombian Diario Oficial access.
  - Kazakhstan's adilet English coverage.
  - Egypt's Official Gazette online availability.
  - Nigeria's Federal Gazette online availability.
  - Indonesia's peraturan.go.id from another vantage.
- Official English per source was checked only by "an /en page returns 200". That does not mean the acts themselves are translated: most gazettes (BOE, Dz.U., Resmî Gazete, DOU, JORF) publish only in the national language.

---

## Part 1, Q2: Blocking and legal risks; geo-blocking from foreign IPs

### Takeaway
- **Geo-blocking is real and inconsistent.** After the 2022 invasion, a quarter of reachable Russian government domains blocked all non-Russian vantage points. On 2026-10-15, kremlin.ru, the Rada sites, Egypt's Cabinet and Argentina's Boletín Oficial all failed from Kenya, and most failed from a second vantage too.
- **Legal status of official texts** is left to each country (Berne Art. 2(4)). Reuse terms differ per site, so each source needs its licence recorded. The repo already does this.

### Cited Findings
- A USENIX Security 2023 study ("Network Responses to Russia's Invasion of Ukraine in 2022") found that **136 Russian government domains (25.09% of 542 accessible) blocked access from all tested countries outside Russia**, and 112 (20.66%) were reachable only from Russian and Kazakh vantage points — [Lantern corpus summary of Ramesh et al., USENIX Security 2023](https://corpus.lantern.io/findings/2023-ramesh-network__russia-gov-geoblocking-ad-hoc-mechanisms/).
  - The mechanisms were mixed (DNS timeouts, TCP timeouts, HTTP 403, block pages), which the authors read as an ad hoc response with no central policy (same source).
- In 2022 (early in the invasion) the President's, government's and State Duma's sites were reported intermittently unavailable even inside Russia and Kazakhstan — [TBS News / Reuters](https://www.tbsnews.net/world/some-russian-govt-websites-intermittently-unavailable-375658).
- On 2026-10-15:
  - `kremlin.ru` and its acts feed timed out from Kenya — [probe](https://kremlin.ru/acts/news/feed). The fetch also failed from the second vantage.
  - `government.ru` answered 200 from Kenya — [probe](http://government.ru/).
- Berne Convention Art. 2(4): "It shall be a matter for legislation in the countries of the Union to determine the protection to be granted to official texts of a legislative, administrative and legal nature" — [Berne Convention (Cornell LII)](https://law.cornell.edu/treaties/berne/berne.htm).
- Licence and reuse examples in the repo:
  - Mexico DOF: non-profit reproduction with citation; commercial use needs SEGOB consent — [DOF aviso legal](https://dof.gob.mx/aviso_legal.html).
  - Brazil Chamber: open data "free of licences" — [Câmara dados abertos](https://dadosabertos.camara.leg.br/howtouse/sobre-dados-abertos.html).
- Kazakhstan's Adilet states its policy in robots.txt: it closes the site to AI **training** crawlers, but keeps it open to search/citation agents and to agents fetching a page on a person's request. It also says the same names are enforced server-side in nginx — [probe: adilet.zan.kz/robots.txt](https://adilet.zan.kz/robots.txt).
- Bot-protection products seen in probes:
  - Cloudflare challenge or block: Légifrance, uaelegislation.gov.ae, cg.gov.ma.
  - "Browser check": Consilium.
  - Akamai-style "Access Denied": president.gov.ua, dpr.go.id.
  - "Security Check": ris.bka.gv.at.
  - Incapsula referenced: info.gouv.fr.
  - Sources: the probe links in Q1.

### Inferences
- A source that answers only from inside its own country cannot be fetched reliably from a Worker. The project should treat "times out from abroad" like the existing Russia note: skip it, or find a mirror that is itself official (for example the EU's own records of member-state acts, or an official API host that differs from the website).
- Each Cloudflare or Akamai challenge counts as a bot check under the project's rules, so those HTML routes are out. Several of these sites offer an official API on another host: RIS OGD at data.bka.gv.at, DILA dumps for Légifrance, EUR-Lex RSS. Those are the compliant routes.
- Legal risk for reading and summarising official acts with a link back is low where official texts are excluded from copyright. But reuse terms (like the DOF's commercial-use clause or the Rada's data licence) matter if the app is ever monetised. This is not legal advice: confirm per country.

### Gaps
- Not verified for the candidates: which countries exclude official texts from copyright, with article numbers. A WIPO Lex lookup per country is needed.
- No current (2026) independent measurement of Russian government geo-blocking. The USENIX data is from 2022.
- Saudi Arabia's no-monitoring clause (known from context) was not re-checked. No similar clause was looked for on the candidates' terms pages.

---

## Part 2, Q3: UI localization in Flutter, store-listing localization, and evidence of download uplift

### Takeaway
- **UI localization in Flutter is mechanical:** one ARB file per language, generated by `gen-l10n`. The listings are also cheap:
  - **Apple:** 50 listing languages, including uk, ru, cs, pl, ar, tr, id, es-MX and pt-BR, but **not Kazakh**.
  - **Google Play:** about 86 listing languages, free machine translation for 10 of them, and automatic translations shown to users when none is provided.
- **Uplift evidence is thin and old.** The widely repeated figures (Distimo +128% downloads per country; a 767% single-developer anecdote) trace back to secondary sources. The one controlled test found +33% in China and 0% in the Netherlands.

### Cited Findings
- Flutter localization:
  - Add `flutter_localizations` and `intl`, set `generate: true`, add `l10n.yaml` and one ARB file per language. Code is generated by `flutter gen-l10n`.
  - ICU plurals and selects are supported; `few` and `many` categories are available, and only `other` is required.
  - Dates and numbers are formatted per locale (example: `yMd` gives "7/9/1959" in en-US and "9.07.1959" in Russian).
  - Source: [Flutter docs: Internationalizing Flutter apps](https://docs.flutter.dev/ui/accessibility-and-internationalization/internationalization).
- A language that Flutter's built-in Material localizations do not cover needs "about 70 translations" plus date patterns and symbols — [Flutter docs](https://docs.flutter.dev/ui/accessibility-and-internationalization/internationalization).
- On iOS, the supported languages must also be added under Xcode's Localizations section, which updates `project.pbxproj` — [Flutter docs](https://docs.flutter.dev/ui/accessibility-and-internationalization/internationalization).
- **App Store**: 50 listing languages/locales, including Arabic, Czech, Indonesian, Polish, Portuguese (Brazil and Portugal), Russian, Spanish (Mexico and Spain), Turkish and Ukrainian. **Kazakh is not one of them.** No date on the page — [Apple: App Store localizations](https://developer.apple.com/help/app-store-connect/reference/app-information/app-store-localizations).
- **Google Play** (all from the same help page):
  - You can add your own translations in about 86 languages and variants.
  - Free machine translation covers 10 languages: Arabic, French, German, Indonesian, Italian, Japanese, Portuguese (BR), Spanish (LatAm and ES) and Thai. They are "not reviewed or approved by humans".
  - If you add no translation, "automated translations of your app's store listing will be available to Google Play users".
  - Paid human translation "costs as little as USD 0.07 per word" and finishes within 7 days.
  - Play Console banners call some translations "likely to increase installs", without a number.
  - Source: [Google Play Console Help: translate and localize your app](https://support.google.com/googleplay/android-developer/answer/9844778).
- **Distimo study:** localizing iPhone apps gave **128% more downloads per country** and **26% more revenue per country added**, within a week. Only secondary sources were found; the original report was not located, and the date is likely about 2012 — [Game Developer: 35 tips, part 3](https://www.gamedeveloper.com/business/35-tips-to-increase-mobile-game-downloads-part-3-of-3); [FoxData: impact of localization](https://foxdata.com/en/marketing-academy/an-in-depth-analysis-of-app-localization-/).
- **"767%"** comes from one developer's experiment (David Janner): app name and keywords localized. It is not an industry average — [FoxData](https://foxdata.com/en/marketing-academy/an-in-depth-analysis-of-app-localization-/); [AppDrift](https://appdrift.co/blog/app-localization-the-hidden-growth-hack-behind-30-higher-install-rates).
- **Controlled A/B test (Paper by FiftyThree, 2016):** Chinese screenshot captions converted **33% better** in China, while Dutch versus English showed **no difference** in the Netherlands. About 2,600 users were tested over 30 days — [Smashing Magazine](https://www.smashingmagazine.com/2016/03/design-app-pages-for-better-conversion-case-study-of-paper-by-fiftythree/).

### Inferences
- **UI effort (estimate):** the app's UI strings are few (feed, article, sources, settings), so a new language costs mostly the translation of an ARB file plus review by a native speaker. Roughly half a day to a day per language once the ARB setup exists; the one-off setup is about one or two days. These are estimates, not measured.
- **Store listing:** translating the listing (title, subtitle, keywords, description, screenshot captions) is the cheapest localization step and the one the evidence supports. The effect is market-dependent: large in markets with low English proficiency, about zero where English is widely read.
- **Kazakhstan:** an App Store listing must be Russian (available) or English. There is no Kazakh listing on Apple.

### Gaps
- No recent (2023–2026) controlled study from AppTweak, Sensor Tower, Phiture or SplitMetrics that quantifies uplift from localization was found. The Distimo original was not located.
- No source on how many Flutter `GlobalMaterialLocalizations` locales exist (the Flutter page does not state it), or on whether `kk` is among them.

---

## Part 2, Q4: Translating the content. Options (a), (b) and (c), model quality, and free-tier arithmetic

### Takeaway
- **On Workers AI, a dedicated translation model is not cheaper.** m2m100-1.2b costs 31,050 Neurons per M tokens both in and out, against glm-4.7-flash at 5,500 in and 36,400 out. Both bill mainly per output token, so the cost of a language is roughly "the output tokens of one more summary".
- **Cost estimate:** with the repo's ~65 Neurons per English article, each extra language adds very roughly 30 Neurons per article. The free 10,000 Neurons a day then fit about 150 articles in English only, about 100 with one extra language, and about 40 with six.
- **Quality evidence for GLM-4.7-Flash in Ukrainian, Czech, Polish or Arabic is missing.** The model card lists only English and Chinese. Qwen3 (119 languages, all target languages listed) and Gemma 3/4 (140+ languages, published multilingual scores) have better-documented coverage.

### Cited Findings

**Workers AI pricing and free tier**
- Free: **10,000 Neurons per day**, resetting at 00:00 UTC. Above that: **$0.011 per 1,000 Neurons**, on Workers Paid only. The page was "Last updated Oct 9, 2026" — [Cloudflare: Workers AI pricing](https://developers.cloudflare.com/workers-ai/platform/pricing/).
- Neurons per million tokens, input / output (same source):

  | Model | Input | Output |
  | --- | --- | --- |
  | @cf/zai-org/glm-4.7-flash | 5,500 | 36,400 |
  | @cf/qwen/qwen3-30b-a3b-fp8 | 4,625 | 30,475 |
  | @cf/google/gemma-4-26b-a4b-it | 9,091 | 27,273 |
  | @cf/google/gemma-3-12b-it | 31,371 | 50,560 |
  | @cf/mistralai/mistral-small-3.1-24b-instruct | 31,876 | 50,488 |
  | @cf/meta/llama-3.2-3b-instruct | 4,625 | 30,475 |
  | @cf/meta/llama-3.1-8b-instruct-fp8-fast | 4,119 | 34,868 |
  | @cf/openai/gpt-oss-20b | 18,182 | 27,273 |
  | @cf/ibm-granite/granite-4.0-h-micro | 1,542 | 10,158 |
  | @cf/zai-org/glm-5.3-flash (paid only) | 13,636 | 45,455 |
  | **@cf/meta/m2m100-1.2b** (translation) | **31,050** | **31,050** ($0.342 per M each way) |

- The page says glm-5.x, kimi-k2.6/2.7 and deepseek-v4 need a paid billing method (same source).
- Workers AI lists only **two** models under Translation: `m2m100-1.2b` (Meta, many-to-many) and `indictrans2-en-indic-1B` (22 Indic languages) — [Cloudflare: models, Translation](https://developers.cloudflare.com/workers-ai/models/?tasks=Translation).
- The glm-4.7-flash page on Workers AI describes a "fast and efficient multilingual text generation model" supporting "more than 100 languages", with a 131,072-token context and a price of $0.0605 / $0.40 per M tokens in / out — [Cloudflare: glm-4.7-flash](https://developers.cloudflare.com/workers-ai/models/glm-4.7-flash/).
- The gemma-4-26b-a4b-it page on Workers AI gives a 256K context and $0.10 / $0.30 per M tokens; it does not list languages — [Cloudflare: gemma-4-26b-a4b-it](https://developers.cloudflare.com/workers-ai/models/gemma-4-26b-a4b-it/).
- The repo's own estimate is "about 60 to 70 Neurons per article", so the free tier covers "roughly 150 articles". The summarizer caps output at `max_completion_tokens: 1500` and input text at 20,000 characters — Repo: `docs/decisions.md` (2026-10-14 entry), `server/src/summarizer/index.ts` (`MAX_COMPLETION_TOKENS = 1500`), `server/src/summarizer/prompt.ts` (`MAX_TEXT = 20_000`).

**Multilingual quality evidence**
- **GLM-4.7-Flash:** the Hugging Face card tags only English and Chinese. It reports **no multilingual benchmarks** (only AIME, GPQA, LCB, HLE, SWE-bench, τ²-Bench and BrowseComp). It is a 30B-A3B mixture-of-experts model under the MIT licence — [Hugging Face: zai-org/GLM-4.7-Flash](https://huggingface.co/zai-org/GLM-4.7-Flash).
- **Qwen3** "supports 119 languages and dialects". Its table lists Ukrainian, Russian, Czech, Polish, Arabic (several dialects), Kazakh, Turkish and Indonesian. Released 2025-04-29 — [Qwen blog: Qwen3](https://qwenlm.github.io/blog/qwen3/).
- **Gemma 3** (pre-trained) multilingual scores for the 1B / 4B / 12B / 27B sizes; the card claims "over 140 languages" — [Hugging Face: google/gemma-3-12b-it](https://huggingface.co/google/gemma-3-12b-it):

  | Benchmark | 1B | 4B | 12B | 27B |
  | --- | --- | --- | --- | --- |
  | WMT24++ (ChrF) | 36.7 | 48.4 | 53.9 | 55.7 |
  | FloRes | 29.5 | 39.2 | 46.0 | 48.8 |
  | Global-MMLU-Lite | 24.9 | 57.0 | 69.4 | 75.7 |

- **Mistral Small 3.1** officially supports, among others, Polish, Russian, Ukrainian, Turkish, Indonesian and Arabic. **Czech is not listed.** In its multilingual evals it averages 71.18%, against 70.19% for Gemma 3 27B and 70.36% for GPT-4o mini — [Hugging Face: Mistral-Small-3.1-24B-Instruct-2503](https://huggingface.co/mistralai/Mistral-Small-3.1-24B-Instruct-2503).
- **Llama 3.1** officially supports 8 languages (English, German, French, Italian, Portuguese, Hindi, Spanish, Thai). **None of Ukrainian, Russian, Czech, Polish or Arabic is among them** — [Llama 3.1 8B Instruct model card (HF mirror)](https://huggingface.co/crusoeai/Llama-3.1-8B-Instruct).
- **Ukrainian LLM leaderboard** (aggregator, imports dated 2026-05-06):
  - MamayLM-Gemma-3-12B-IT ranks 2nd, gemma-3-12b-pt 5th, Qwen3-8B-Base 6th. No Llama in the visible top 8.
  - Tasks include FLORES, ZNO exams and translated MMLU.
  - Source: [benchmarklist.com: Ukrainian LLM Leaderboard](https://benchmarklist.com/benchmarks/ukrainian_llm_leaderboard/).
- **UNLP 2026 grammar and orthography benchmark:** smaller models reached at most 42.1% accuracy, and the largest LLMs up to 59.6%. The authors conclude standard Ukrainian "remains challenging" — [ACL Anthology author listing (UNLP 2026)](https://aclanthology.org/people/yuliia-maksymiuk/) (from a search summary; the paper itself was not opened).
- **WMT25 general MT findings:** 30 language pairs (including en→uk, en→cs, en→ar_EG, en→ru and cs→uk), ranked by human evaluation with ESA/MQM. The preliminary ranking includes Gemma-3-27B. One participant chose Gemma-3-12B and landed mid-tier — [WMT25 findings](https://preview.aclanthology.org/setup/2025.wmt-1.22); [Preliminary ranking, arXiv 2508.14909](https://arxiv.org/pdf/2508.14909); [WMT25 participant paper](https://aclanthology.org/2025.wmt-1.51.pdf).
- **TranslateGemma** (Gemma-3-based translation models, January 2026): its smaller models often match larger baselines on WMT25 pairs — [arXiv 2601.09012](https://arxiv.org/abs/2601.09012v2). It is **not** in Workers AI's Translation list (above).
- **Tokenization cost by language:** the same text can tokenize to lengths "up to 15 times" different across languages. Gaps persist even in multilingual tokenizers — [Petrov et al., "Language Model Tokenizers Introduce Unfairness Between Languages", arXiv 2305.15425](https://arxiv.org/abs/2305.15425).
- **On-device (option c), Google ML Kit:**
  - 59 languages, including uk, ru, cs, pl, es, ar, tr, id and pt, but **not Kazakh** — [ML Kit language support](https://developers.google.com/ml-kit/language/translation/translation-language-support).
  - It is "intended for casual and simple translations".
  - Models translate to and from English; other pairs pivot through English.
  - Language packs download on demand, and attribution in the app is required — [ML Kit translation overview](https://developers.google.com/ml-kit/language/translation).

**Free-tier arithmetic (all ESTIMATES)**

The rates are from the Cloudflare pricing page above. The token counts are my assumptions.

glm-4.7-flash costs 0.0055 Neurons per input token and 0.0364 per output token.

1. **English only (today).**
   - Assume about 7,700 input tokens: a 1,000-token prompt plus about 20,000 characters of article.
   - Assume about 400 output tokens: headline, short summary and summary.
   - Cost: 7,700 × 0.0055 = 42.4, plus 400 × 0.0364 = 14.6, gives **≈ 57 Neurons**. That matches the repo's 60–70.
   - A short article of 3,000 input tokens gives 16.5 + 14.6 = **≈ 31 Neurons**.
   - With the repo's 65: 10,000 / 65 = **≈ 153 articles a day**.
2. **Option (a): one call, extra languages written in the same answer.**
   - Assume a non-English summary takes about 2× the English tokens: 400 × 2 = 800 tokens, for Cyrillic and Arabic. This is an estimate; see Petrov et al.
   - Each extra language adds 800 × 0.0364 = **≈ 29 Neurons**.

     | Languages | Neurons per article | Articles a day on the free tier |
     | --- | --- | --- |
     | English + 1 | 65 + 29 = 94 | 10,000 / 94 ≈ **106** |
     | English + 3 | 65 + 87 = 152 | 10,000 / 152 ≈ **66** |
     | English + 6 (uk, ru, cs, pl, es, ar) | 65 + 174 = 239 | 10,000 / 239 ≈ **42** |

   - The current `max_completion_tokens: 1500` would cut off English + 2 or more: 400 + 2 × 800 = 2,000 > 1,500.
3. **Option (b): a second call per language translating the English summary.**
   - Input about 700 tokens (prompt plus English text): 700 × 0.0055 = 3.9.
   - Output about 800 tokens: 800 × 0.0364 = 29.1.
   - Total **≈ 33 Neurons per language per article**, about the same as (a) but with N extra requests.
   - **With m2m100 instead:** (500 in + 800 out) × 0.03105 = **≈ 40 Neurons**, which is *more* than GLM.
   - **With qwen3-30b-a3b instead:** 700 × 0.004625 + 800 × 0.030475 = 3.2 + 24.4 = **≈ 28 Neurons**.
   - **With gemma-4-26b-a4b instead:** 700 × 0.009091 + 800 × 0.027273 = 6.4 + 21.8 = **≈ 28 Neurons**.
4. **Paid overflow example:** 300 articles a day × English + 6 languages ≈ 300 × 239 = 71,700 Neurons a day.
   - Minus the free 10,000 leaves 61,700, and 61.7 × $0.011 = **$0.68 a day, about $20 a month**, plus the $5 Workers Paid base. This is an estimate.
5. **Option (c): on-device or on demand** costs no Neurons. ML Kit covers the target languages except Kazakh, at "casual" quality. Translating on demand on the server spends Neurons only for articles someone opens, so the cost scales with readers rather than articles.

### Inferences
- **(a) is cheapest in requests and keeps "one AI call per article"**, a fixed project principle. It does mean longer answers (the token limit must rise) and one failure loses all languages.
- **(b) costs about the same in Neurons** but breaks the one-call principle unless that rule is amended.
- **(c) needs no server spend** but its quality is "casual", and it pivots through English.
- **m2m100 has no cost advantage on Workers AI** and is an older (2020-era) model. With the evidence above, an instruction model (Qwen3-30B-A3B or Gemma 4 26B A4B) is the better translation option on Workers AI. This is an inference: no head-to-head result for these exact models was found.
- **Before adding a language with glm-4.7-flash, run a small native-speaker spot-check**, for example 20 articles per language. There is no published multilingual evaluation for GLM-4.7-Flash, while Qwen3 and Gemma document coverage of all six target languages.

### Gaps
- No measured token counts per article in this project (the repo's 60–70 Neurons is an estimate). The per-language token multiplier (×2) is an assumption.
- No published FLORES or WMT scores found for GLM-4.7-Flash, Qwen3-30B-A3B or Gemma 4 26B A4B on Ukrainian, Czech, Polish or Arabic specifically. No FLORES numbers for m2m100-1.2b were retrieved.
- Not checked: Apple's on-device Translation framework language list, Granite 4.0's supported languages, or whether the 10,000-Neuron free allocation applies to every model (the pricing page lists paid-only exceptions, and gemma-4's page says nothing either way).

---

## Part 2, Q5: Right-to-left (Arabic) and Cyrillic in Flutter

### Takeaway
Flutter's localization delegates set text direction per locale, so Arabic flips the layout once the delegates are in place. The work is in the details: direction-aware paddings and alignments, mirrored arrow icons, and fonts. The app's `Georgia` serif with a generic `serif` fallback will show Arabic in whatever system fallback font each platform picks.

### Cited Findings
- `GlobalWidgetsLocalizations.delegate` "defines the default text direction, either left-to-right or right-to-left". Widgets "should be adapted to ... use the appropriate left-to-right or right-to-left layout" — [Flutter docs: Internationalizing Flutter apps](https://docs.flutter.dev/ui/accessibility-and-internationalization/internationalization).
- Russian date formatting example from the same page: "9.07.1959" — [Flutter docs](https://docs.flutter.dev/ui/accessibility-and-internationalization/internationalization).
- The app sets `fontFamily: 'Georgia'` with `fontFamilyFallback: ['serif']` in `app/lib/core/theme.dart` (repo, read 2026-10-15).

### Inferences
- **Layout:** for RTL, use `EdgeInsetsDirectional` and `AlignmentDirectional` (start/end) instead of left/right, and mirror directional icons such as back arrows and chevrons. This is based on Flutter API knowledge; I did not re-check it against the docs in this session.
- **Fonts:** Georgia is an Apple and Microsoft system font. Android has none, so Android already falls back to its system serif. Arabic and Cyrillic glyphs come from each platform's fallback, so the look will differ between iOS and Android. To fix that, bundle a serif with Cyrillic and Arabic coverage (for example Noto Serif and Noto Naskh Arabic). Each added font file adds app size. This is an inference; glyph coverage of Georgia was not checked here.
- **Text length:** Cyrillic and German text runs longer than English, and Arabic needs more line height. Headline truncation rules and the fixed card heights in the design should be tested with real translated strings.

### Gaps
- No primary source fetched on Georgia's glyph coverage, or on Flutter's handling of mixed RTL/LTR text (for example Latin act numbers inside Arabic summaries).
- No measurement of app-size cost for bundling Arabic and Cyrillic fonts.
