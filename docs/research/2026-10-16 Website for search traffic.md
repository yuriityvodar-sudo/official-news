# Website for search traffic

## The question

Should we publish our summaries and translations as a website, so Google brings readers from many countries who then install the app? And how many people look for such an app in the stores?

## Recommendation

- **Build it, starting with a page per article.** The app's share now sends only the ministry link (`shareArticle()`). Our own page on the app's domain opens the app when installed and shows a Smart App Banner when not, so it pays off from the first share. It also gives the App Store its required Privacy and Support URLs.
- **Plain HTML, rendered on request by a Worker reading D1, and cached.** Each page shows an AI label, the official link, a credit line and an "independent, not a government body" note. No source photos by default.
- **Index a small reviewed set; the rest is `noindex`.** Google lists AI and auto-translated feed pages "without adding value" as scaled content abuse. Index pages a person has fact-checked (translations native-reviewed) and country or topic pages that add what the original lacks: what changed, who is affected, dates.
- **Lead with Ukrainian and Russian.** Google machine-translates results into Spanish, German and about 20 other languages, not these two; English pages compete with the originals, which rank first. The niche is an estimate.
- **Measure for 4–8 weeks:** Search Console clicks, "Web referrer" installs, crawler requests and Apple Ads keyword popularity.
- **Scale one language or page type at a time** once indexed pages earn clicks and review keeps up. At about 6,500 page views a day (10% of free requests), plan the next step inside our one account (for example pages stored in R2 and served without a Worker request). One project stays in one Cloudflare account (Yurii, 16 Oct).
- **Search is one channel of several.** Localized App Store pages, a featuring nomination and Telegram for UA/RU are nearly free and better evidenced.

## Google's rules that matter

- **AI content is allowed; value is the test:** "Appropriate use of AI or automation is not against our guidelines" ([Feb 2023](https://developers.google.com/search/blog/2023/02/google-search-and-ai-content)).
- **Scaled content abuse** ([spam policies](https://developers.google.com/search/docs/essentials/spam-policies), Aug 2026): AI used to "generate many pages without adding value for users", "automated transformations like synonymizing, translating", and "Stitching or combining content from different web pages without adding value". Remedy: "If you're hosting such content on your site, exclude it from Search."
- **Translation:** in June 2025 Google dropped its advice to block auto-translated pages, "a docs-only change, no change in behavior" ([changelog](https://developers.google.com/search/updates)). Google calling AI translation not "strictly" spam appears only in press reports.
- **Rater guidelines** ([Sep 2025](https://static.googleusercontent.com/media/guidelines.raterhub.com/en//searchqualityevaluatorguidelines.pdf)): paraphrase helps "when an expert paraphrases the contents of a government policy in easy-to-understand language"; low-value AI pages rate Lowest "even if the page assigns credit for the content to another source".
- **Gen-AI guide** ([Oct 2026](https://developers.google.com/search/docs/fundamentals/using-gen-ai-content)): "critical to manually factcheck and review all AI-generated content ... before publishing", titles and meta descriptions included. Disclosure is only suggested; the EU AI Act makes a label mandatory for unreviewed text. The [AI optimization guide](https://developers.google.com/search/docs/fundamentals/ai-optimization-guide) adds: "a summary of existing content simply restates information already available elsewhere".
- **Originals first** ([ranking systems](https://developers.google.com/search/docs/appearance/ranking-systems-guide)): original reporting goes "ahead of those who merely cite it", and "Site-wide signals" are used. That weak pages could pull down the domain is our inference.
- **News and Discover:** eligibility is automatic. News expects "Clear dates and bylines" and contact details ([policies](https://support.google.com/news/publisher-center/answer/6204050)). Discover's February 2026 update favours "websites based in their country", US English first ([post](https://developers.google.com/search/blog/2026/02/discover-core-update)); wider rollout is unverified.
- **App prompts:** "Instead of full page interstitials, use banners", app-install prompts included ([interstitials](https://developers.google.com/search/docs/appearance/avoid-intrusive-interstitials)).

## What similar sites and apps show

- **Civic sites that rank are trackers.** GovTrack and Ballotpedia keep one evergreen page per bill or candidate, updated over years; Google brings about 37–50% of visits (Semrush estimates). The EU publishes 2,500+ official summaries of its own laws.
- **AI news apps grew through creators and press.** Ground News gets about 10–14% of traffic from Google (Semrush estimate) and was YouTube's top brand sponsor in H1 2025. Artifact closed after a year (market too small).
- **Mass translation is volatile.** Reddit's AI-translated pages fell in May–June 2026 and recovered in September (third-party trackers). Le Monde in English, AI-drafted and journalist-edited, broke even (secondary source).
- **Failures were wrong short facts:** CNET corrected 41 of 77 AI stories; Apple paused news notification summaries. NewsGuard's 3,749 AI content farms share no real human oversight and no clear disclosure.
- **News search traffic is shrinking.** Chartbeat: Google Search referrals −40.2% (Jul 2025–Jul 2026); small sites −60% (Dec 2024–Dec 2025). Pew: a result was clicked on 8% of visits with an AI summary, 15% without. Our baseline: LyFi, about 110 readers a day.

## App Store demand and the web-to-app path

**Demand.** Apple says "Almost 65% of downloads happen directly after a search" (2022 data). Searches for "official news" or similar are unknown: Apple Ads shows only a relative popularity score, reported by vendors as unreliable since October 2025. Google Play has 21,388 News & Magazines apps (AppBrain).

**Measuring:**
- Before launch: a free Apple Ads account shows keyword popularity per storefront without a campaign; Google Trends covers the web.
- After launch: App Store Connect splits installs into App Store search, Web referrer and App referrer, with campaign links; Play Console shows search terms.
- Web-to-app conversion has no independent benchmark, so we measure our own.

**The path:** a universal link opens the app, or our page. The Smart App Banner is one meta tag (iOS Safari only, hidden once dismissed). Firebase Dynamic Links closed in 2025; App Clips are not needed. Shared links are growing: "dark social" rose from 7.1% to 11.3% of page views (Chartbeat). Apple News takes AU, CA, UK and US publishers only. Telegram suits UA: 52% of Ukrainians read Telegram channels constantly or often (Rating Group, 2025).

## Reuse rights and photos

Not legal advice: notes from primary sources read 16 Oct 2026, for the legal review the plan already includes. We translate our own English summary, not the official text, and never show full official text.

| Sources | Our summary + link | Verbatim text | Source photos |
|---|---|---|---|
| US, UK, EU, IT, ES, JP, AU, UA, AR | Yes, with credit line | Yes under licence (EU, JP: mark changes) | US federal staff, governo.it, Pool Moncloa: yes; others if not third-party |
| DE, FR, PL, BR, KR, TR, ID, CZ | Yes, low risk | Limited by licence | No |
| CA, MX, ZA, CN | Own words arguably fine | Commercial use needs permission | No |
| IN | Yes | Full translations not covered | Third-party excluded |

- The UA row rests on Law 2811-IX art. 8 and kmu.gov.ua's CC BY 4.0; the statute text was unreachable, so it is unverified.
- Some sources require exact credit wording (OGL, Moncloa, BOE, Kantei, DOF): keep a template per source beside `licence`. OGL v3 grants no right to "suggest any official status"; the independence note covers it.
- **Photos are the main new risk:** a site adds public copies and a permanent archive. Use our own country visuals.
- **EU AI Act Art. 50(4), since 2 Aug 2026:** AI text on public-interest matters needs a visible label unless a person substantively reviews it under named editorial responsibility. Our publisher is in Slovakia.

## Fit with our system and the free plan

- **Retention:** records are never deleted, only full text after 30 days, and the API serves any article by id (repo read). The archive starts 7 Oct 2026. Change: record "article pages are permanent", return 410 for hidden ones, decide whether new languages backfill beyond 7 days.
- **Cost per page view** (D1 rows measured 16 Oct): 1 Worker request with plain HTML, about 9 D1 rows per uncached article, 0 AI calls. A list page reads about 630 rows; a country/week page 297, growing until a country/time index is added.
- **Ceiling:** 100,000 Worker requests a day per account, shared by the app's API, crons and the site. Cache hits and crons are billed as requests; assume they count until measured. Going over also stops the app's API, hence the 6,500 line.
- **Storage** (estimate): 140–290 MB a year against 500 MB per D1 database, so 2–3.5 years.
- **CPU:** 10 ms per request, 1 cron trigger left: render on request, cache, split sitemaps by month.
- **`/health`** scans the whole articles table; polled every minute, it would pass D1's 5M daily reads within about a year (estimate). Make it cheap first.
- Reusing stored summaries keeps one AI call per article.

## Steps as small pull requests

1. **Decision (docs):** shape, URLs `/{lang}/{country}/{id}-{slug}`, permanent pages, index, photo and label policy, in `docs/decisions.md`, `plan.md` and `contract.md`.
2. **Server prep:** country/time index; cheap `/health`.
3. **Site Worker** on the app's domain: D1 binding, robots.txt, Workers Cache, Search Console; in `docs/setup.md`.
4. **English article page:** canonical, NewsArticle JSON-LD, AI label, credit line, Smart App Banner, `noindex` by default.
5. **Language versions:** hreflang, 410 for hidden articles.
6. **Store pages:** About and methodology with named editors, Privacy, Terms, Support (from the #64 drafts).
7. **Universal links and share:** apple-app-site-association, app route, `shareArticle()` sending our page.
8. **Sitemaps and measurement:** sitemaps, analytics with EU consent, crawler breakdown, campaign links.
9. **Indexed pilot:** switch the first reviewed set to `index`.

About 6–8 working days in total (estimate).

## Open questions

- Who reviews which pages, and how many a day? This sets the indexed set.
- Which page type leads the UA/RU pilot: daily top decisions or weekly country digests?
- Is a free site promoting the app "commercial" under CA, MX, ZA and CN terms, and which entity publishes it? For the legal review.
- Do cache hits and crons count toward the 100k cap? A dashboard check settles it.
- How often do summaries get dates or amounts wrong, on a sample?

## Sources

- Google: [AI content](https://developers.google.com/search/blog/2023/02/google-search-and-ai-content) · [spam policies](https://developers.google.com/search/docs/essentials/spam-policies) · [changelog](https://developers.google.com/search/updates) · [rater guidelines](https://static.googleusercontent.com/media/guidelines.raterhub.com/en//searchqualityevaluatorguidelines.pdf) · [gen-AI guide](https://developers.google.com/search/docs/fundamentals/using-gen-ai-content) · [AI optimization](https://developers.google.com/search/docs/fundamentals/ai-optimization-guide) · [ranking](https://developers.google.com/search/docs/appearance/ranking-systems-guide) · [News](https://support.google.com/news/publisher-center/answer/6204050) · [Discover](https://developers.google.com/search/blog/2026/02/discover-core-update) · [hreflang](https://developers.google.com/search/docs/specialty/international/localized-versions) · [translated results](https://developers.google.com/search/docs/appearance/translated-results) · [interstitials](https://developers.google.com/search/docs/appearance/avoid-intrusive-interstitials)
- Precedents: [GovTrack](https://cw.semrush.com/website/govtrack.us/overview) · [Ballotpedia](https://zh.semrush.com/website/ballotpedia.org/overview) · [EU summaries](https://op.europa.eu/documents/2050822/2140005/Summaries+of+EU+Legislation+-+A+Compass+to+EU+Law.pdf) · [Ground News](https://cw.semrush.com/website/ground.news/overview) · [Axios](https://www.axios.com/2025/10/22/youtube-sponsorship-creator-videos) · [Artifact](https://the-decoder.com/ai-curated-news-app-artifact-shuts-down-after-one-year/) · [Reddit drop](https://www.gsqi.com/marketing-blog/reddit-ai-translations-drop/) · [rebound](https://seroundtable.com/google-september-2026-spam-update-two-42209.html) · [Le Monde](https://www.connexionfrance.com/magazine/how-le-monde-in-english-finally-broke-even-with-ai-and-subscriptions/803938) · [CNET](https://gizmodo.com/cnet-ai-chatgpt-news-robot-1849996151) · [Apple summaries](https://www.siliconrepublic.com/business/apple-halt-ai-notification-summaries-backlash-features) · [NewsGuard](https://www.newsguardtech.com/special-reports/ai-tracking-center/) · [Chartbeat](https://www.searchenginejournal.com/google-search-decline-publishers-chartbeat/590681/) · [by size](https://chartbeat.com/resources/articles/pageviews-down-ai-impact/) · [Pew](https://www.pewresearch.org/short-reads/2025/07/22/google-users-are-less-likely-to-click-on-links-when-an-ai-summary-appears-in-the-results/)
- Stores: [Apple Ads](https://ads.apple.com/app-store) · [popularity](https://aso.dev/blog/apple-ads-popularity-massive-drop/) · [AppBrain](https://www.appbrain.com/stats/android-market-app-categories) · [sources](https://developer.apple.com/help/app-store-connect/view-app-analytics/view-acquisition-sources) · [Play terms](https://support.google.com/googleplay/android-developer/answer/9859173) · [Smart App Banners](https://developer.apple.com/documentation/webkit/promoting-apps-with-smart-app-banners) · [universal links](https://developer.apple.com/documentation/xcode/supporting-universal-links-in-your-app) · [Dynamic Links](https://firebase.google.com/support/dynamic-links-faq/) · [App Clips](https://docs.flutter.dev/platform-integration/ios/ios-app-clip) · [App Store URLs](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information) · [Apple News](https://support.apple.com/guide/news-publisher/publishing-on-apple-news-apde42330c66/1.0/icloud/1.0) · [Rating Group](https://www.ratinggroup.ua/en/news/media-aug2025)
- Legal: [17 U.S.C. §105](https://www.law.cornell.edu/uscode/text/17/105) · [OGL v3](https://www.nationalarchives.gov.uk/doc/open-government-licence/version/3/) · [EU](https://commission.europa.eu/legal-notice_en) · [Bundesregierung](https://www.bundesregierung.de/breg-de/mediathek/pressefotos/nutzungsbedingungen-bilder) · [gov.pl](https://www.gov.pl/web/gov/warunki-korzystania) · [Canada.ca](https://www.canada.ca/en/transparency/terms.html) · [DOF](https://dof.gob.mx/aviso_legal.html) · [gov.za](https://www.gov.za/terms-and-conditions-use-0) · [Ukraine](https://www.wipo.int/wipolex/en/legislation/details/23798) · [AI Act Art. 50](https://artificialintelligenceact.eu/article/50/) · [Commission FAQ](https://digital-strategy.ec.europa.eu/en/faqs/transparency-obligations-under-article-50-ai-act)
- Cloudflare: [Workers limits](https://developers.cloudflare.com/workers/platform/limits/) · [pricing](https://developers.cloudflare.com/workers/platform/pricing/) · [Workers Cache](https://developers.cloudflare.com/workers/cache/) · [D1 limits](https://developers.cloudflare.com/d1/platform/limits/) · [D1 pricing](https://developers.cloudflare.com/d1/platform/pricing/)
- Repo: `app/lib/features/detail/detail_screen.dart`, `server/src/health/cleanup.ts`, `server/src/api/index.ts`, `docs/decisions.md`; D1 figures from read-only `wrangler d1` queries, 16 Oct 2026.
