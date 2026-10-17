# AI sources for an AI tab

Research for Yurii's idea of 17 Oct 2026: a separate "AI" tab in the app, fed only by what AI companies and AI regulators publish on their own official websites, plus a weekly roundup written by the app from those items. Research only; nothing is decided. Adding company newsrooms changes the fixed principle "official government and international-body websites", so it needs a decision issue and Roman's agreement first.

## How it was checked

On 17 Oct 2026, from Yurii's Mac, with the fetcher's rules: user agent `OfficialNewsBot/0.1 (+https://github.com/yuriityvodar-sudo/official-news)`, robots.txt first and obeyed, at most 3 requests per site (list page, one feed guess, one item page), 5 seconds apart (10 where robots.txt asks), stop at the first 403, 429, 503 or bot check, no retries, no other user agent, no browser. Terms pages were read separately, only for sites that did not block. Posts per week are estimates from the dates visible in the list or feed over 17 Sep to 17 Oct 2026. "Clean" means: allowed by robots.txt, a feed or an HTML list with dates, and terms that do not forbid automated reading or redistribution.

## Companies

| Site | List | Feed | robots | List | Terms | Posts/week | Verdict |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Anthropic | anthropic.com/news | none (`/rss.xml` 404) | allows all | HTML, `<time>` and category per item; 433 KB page | no website terms; only the Claude service terms; "© Anthropic PBC" | ~4 | **clean** (list HTML, item page for text) |
| Mistral | mistral.ai/news/ | **mistral.ai/news/rss** (90 items, dates, one-line description) | allows all | HTML too, but 1.2 MB; use the feed; the item page's JSON-LD date is wrong, trust the feed | generic product terms, extraction "as permitted through the Products"; the feed is such a channel | ~1 | **clean** (feed) |
| Google, The Keyword AI | blog.google/innovation-and-ai/technology/ai/ | **…/technology/ai/rss/** (20 items, dates, tags) | allows (only /search blocked) | partly JS; use the feed | Google ToS: content "as allowed by these terms", obey robots.txt; no ban on summaries or commercial use | ~2 | **clean** (feed) |
| Google DeepMind | deepmind.google/blog/ | **deepmind.google/blog/rss.xml** (100 items) | allows all (robots.txt is gzip-encoded) | HTML, month+year only; use the feed | Google ToS, as above | ~2.6 | **clean** (feed) |
| Hugging Face | huggingface.co/blog | **huggingface.co/blog/feed.xml** (full archive) | allows all | HTML, `<time datetime>` | no reproduction of "proprietary materials"; no robots clause | ~4.4, of which ~2.3 HF's own | **clean**, keep only slugs without `/` (the rest are partner organisations' posts) |
| ElevenLabs | elevenlabs.io/blog | **elevenlabs.io/blog/rss.xml** (50 items) | allows; `Content-Signal: ai-input=yes` | list HTML is stale (newest 30 Sep); use the feed | content owned, "use other than as authorized" prohibited; no robots clause | ~11, half SEO how-tos | clean via feed, **noisy**: needs a title filter or parking |
| Microsoft (Source, AI topic) | news.microsoft.com/source/topics/ai/ | **…/topics/ai/feed/** | allows; `Crawl-delay: 10` | titles without dates; item pages are block pages (2 paragraphs) | "personal and non-commercial use"; permissions page allows linking "for informational purposes" | ~0.5 tagged, ~1 to 2 real | needs page reading; low volume; **terms caution** |
| OpenAI | openai.com/news/ | not reached | allows `/news/` | not reached | not read | | **blocked**: HTTP 403, Cloudflare challenge (`cf-mitigated: challenge`) |
| xAI | x.ai/news | not reached | allows `/news`; `Content-Signal: ai-input=yes` | not reached | not read | | **blocked**: HTTP 403, Cloudflare |
| NVIDIA newsroom | nvidianews.nvidia.com/news | **nvidianews.nvidia.com/rss.xml** (20 items, images) | allows (only /file blocked) | HTML with dates | nvidia.com ToS §3.1 "personal, non-commercial internal use only", §3.2(f) no "robot, spider, scraper, crawler"; newsroom not mentioned, yet a public feed is offered | 8 to 15 in a launch week | technically clean, **terms problem** |
| Meta newsroom | about.fb.com/news/ | **about.fb.com/feed/** (10 items, full text, categories) | allows | clean WordPress HTML | Meta ToS 3.2.3: no automated collection "without our prior permission"; 3.4 all rights reserved | ~8, ~3 AI | technically clean, **terms problem** |
| Meta AI blog | ai.meta.com/blog/ | none | allows; robots.txt header says automated collection needs permission | HTML, curated, newest 27 Jul | Meta ToS | ~0 | dormant; covered by the newsroom |
| Apple newsroom | apple.com/newsroom/ | **apple.com/newsroom/rss-feed.rss** (Atom, 20 items, type) | allows | JS list; item pages fine | site terms: no copying "for any commercial enterprise", no "robot, spider or other automatic device" | ~3.3, ~0.5 AI | **terms problem** (strictest of the set) |
| Amazon, About Amazon (AWS) | aboutamazon.com/news/aws | site-wide feed only (10 items, categories) | allows; `Crawl-delay: 10` | items in an embedded JSON blob; item pages 2 MB | Conditions of Use not readable (HTTP 503 twice); AWS site terms (below) likely | ~1 | needs page reading; **terms unread** |
| AWS Machine Learning blog | aws.amazon.com/blogs/machine-learning/ | **…/machine-learning/feed/** (20 items, full text) | allows | HTML with `<time>`; 1.4 MB pages | AWS Site Terms: no "commercial use", no "data mining, robots" | 15 to 17, nearly all tutorials | **terms problem**, and not news |
| Cohere | cohere.com/blog | none | allows | HTML with dates; 1 MB page | ToS 9.3, 14.10, 14.17, 14.19: no robots, no copying or distributing Content | ~3, mostly marketing | **terms problem** |
| Perplexity | perplexity.ai/hub/blog | none found | allows `/hub/blog` | HTML with `<time>` | ToS 5.1, 5.2: personal non-commercial only, no copy or distribute, no robots | ~3 to 4, mixed with guides | **terms problem** |
| Waymo | waymo.com/blog/ | none (`feed.xml` 404) | allows all | HTML with dates, ~9 items shown | terms §3: no commercial use, no copying, no "data mining, robots", obey robots.txt | ~1.6 | **terms problem** |
| Boston Dynamics | bostondynamics.com/news | `/feed/` exists but empty; sitemaps have `lastmod` | allows (only /docs/ blocked) | titles without dates | no copying "for any commercial enterprise", no "robot, spider" | ~1.6 | **terms problem**, needs page reading |
| Stability AI | stability.ai/news-updates | `?format=rss` (20 items) | allows | HTML, `M/D/YY` dates | §3(b): no crawling or scraping of Services including websites | ~0.1 (none in 30 days) | **terms problem**, too quiet |
| Runway | runway.com/news | none | allows all | JS (data only in the React payload) | §1.3: no scraping, no copying | ~2.8 | **terms problem**, needs page reading |
| Scale AI | scale.com/blog | none | allows; any `?query` and /research blocked | partly JS (dates only in the payload) | "internal purposes" only, no derivative works | ~1.4 | needs page reading; terms restrictive |
| Alibaba Cloud press room | alibabacloud.com/en/press-room | none | allows; `?page=` blocked | JS (`window.pressPageData` JSON) | §3.2: no copying or redistribution, no systematic retrieval or crawling | ~0.9 | **terms problem**, needs page reading |

Baidu has no English newsroom (investor relations only), so Alibaba Cloud was checked instead.

## Regulators and bodies

| Site | List | Feed | robots | List | Terms | Posts/week | Verdict |
| --- | --- | --- | --- | --- | --- | --- | --- |
| NIST AI | nist.gov/news-events/news-updates/topic/2753736 | no AI feed (general feed `news-events/news/rss.xml` exists) | allows | HTML with `<time datetime>` | public domain, credit requested (nist.gov/oism/copyrights) | ~0.7 | **clean** |
| White House, presidential actions | whitehouse.gov/presidential-actions/ (already a source: `us-presidential-actions`) | **…/presidential-actions/feed/** (30 items, no categories) | allows | HTML with `<time>` | US government works are not copyrighted | ~7, ~0.5 AI | **clean**; an AI keyword filter on an existing source |
| White House OSTP | whitehouse.gov/ostp/news/ | not tried | allows | HTML with `<time>` | as above | ~1, little AI | clean, low AI density |
| EU, digital-strategy (AI Office) | digital-strategy.ec.europa.eu/en/news (site-wide; the AI-filtered list uses `?`, which robots.txt forbids) | none | allows; no `?` URLs, no PDFs | HTML, `ecl-content-block` items with dates | CC BY 4.0, credit and indicate changes (legal-notice page) | ~15, ~5 to 7 AI | **clean**, needs a keyword filter |
| UK AI Security Institute | aisi.gov.uk/blog; formal items on gov.uk/government/organisations/ai-security-institute (OGL v3, Atom feeds, not fetched) | none on aisi.gov.uk | no rules | HTML (Webflow) with dates | aisi.gov.uk states no licence (Crown copyright by default); GOV.UK is OGL v3 | ~1 | **clean via GOV.UK**; the blog's licence is unstated |
| OECD.AI, "AI Wonk" | oecd.ai/en/wonk | **wp.oecd.ai/feed/** (10 items, full content) | allows (English) | HTML too; use the feed | CC BY 4.0 for content since July 2024 per search excerpts; the terms page answered 403 to our reader: confirm in a browser | ~1 | clean once the terms are confirmed; analysis, not announcements |
| ITU AI for Good | aiforgood.itu.int/newsroom/ | **aiforgood.itu.int/feed/** (200+ items, categories) | allows; `Crawl-delay: 10` | HTML with dates | ITU: non-commercial only, no derivatives; "Newsroom material" (press releases) reusable with credit | ~4, press releases far fewer | **terms problem** except the "Press Release" category |
| Council of Europe AI | not reached | | robots.txt itself returned 403 | | | | **blocked** (Cloudflare) |
| Japan AI Safety Institute | aisi.go.jp (Japanese only) | none | not fetched | | | ~2 to 3 | not suitable: no English list |
| Singapore IMDA | imda.gov.sg/resources/press-releases-factsheets-and-speeches (all topics) | none | allows | Next.js payload, needs JSON parsing | sister sites: personal non-commercial, written permission for reproduction; main terms page is JS-only | ~2 to 3, ~1 AI | **terms problem**, needs page reading |

## What this says

**Clean first list (10 sources, about 3 items a day):** Anthropic, Mistral, Google The Keyword AI, Google DeepMind, Hugging Face (own posts only), NIST, White House presidential actions (AI keyword filter on the existing source), EU digital-strategy (AI keyword filter), UK AI Security Institute via GOV.UK, OECD.AI (after confirming the terms). ElevenLabs can join with a title filter that drops the how-to articles. Estimate: about 20 items a week, so the AI cost is about 50 Neurons a day on the free 10,000 (estimate from 16 Neurons per article), and translations about 60 a week.

**Feed offered, terms say no (ask for permission):** NVIDIA, Meta newsroom, Apple, Microsoft, Amazon, Waymo, Boston Dynamics, Runway, Scale, Stability, Alibaba Cloud, Cohere, Perplexity, ITU. These are the companies the TikTok roundup is about, so the list is thin without them. Their terms forbid automated reading and redistribution as written, yet most of them publish a public feed, which exists to be read by machines. The honest route is one email per company asking to allow `OfficialNewsBot` for their newsroom, with the same text as planned for India's PIB; companies that want coverage usually say yes. Until an answer, they stay out, listed on the "Our sources" page as "asked".

**Blocked by a Cloudflare challenge:** OpenAI, xAI, Council of Europe. Two ways in, both honest: test again from the Worker (the check ran from a Mac, and Cloudflare's firewall may treat traffic from inside Cloudflare differently), and apply to Cloudflare's Verified Bots programme with Web Bot Auth (our Worker signs each request with a key whose public half is published at `https://<our domain>/.well-known/http-message-signatures-directory`; needs the domain from #65; category "Feed fetching"). Verified bots pass the challenge by default; a site can still block them on purpose.

**Decision types the tab would need:** Release (model, product), Research, Policy (regulation, guidance, consultation), Safety disclosure, Partnership, Funding. Events, hiring and how-to articles are not news and are hidden by the AI, as statements are today.

**The weekly roundup:** one AI call a week over the week's AI items (about 20, under 10,000 tokens of input), producing a numbered list, one line per item with the official link, in every language through the translator, pinned at the top of the AI tab. It is the same format as the social-media roundups, made from primary sources only, and it costs one call.

**Before any code:** a decision issue for Roman: company newsrooms as official sources (a change to the fixed principle), the first list above, the permission emails, and the Verified Bots application once the domain exists.

Raw fetched files from the check are in the session's scratchpad, not in the repo.
