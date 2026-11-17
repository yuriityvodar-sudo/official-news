# App Store search (ASO) for Outer News, 16 Nov 2026

Outer News 1.0 went live on 16 Nov. This note measures how people look for an app like ours in the App Store and what our page lacks, and proposes changes. The texts proposed for each language are in `store/listing/`; the decision is `docs/decisions/2026-11-16-aso-plan.md`. M = measured today, A = assumption.

## Our page today (M, App Store Connect)

- Name "Outer News: AI Brief", subtitle "News that brings values" (a grammar slip; the agreed subtitle was "What the news means for you", `docs/decisions/2026-11-05-store-listing.md`).
- Keywords: `headlines,daily,explained,summary,world,politics,economy,breaking,current events,digest,finance`.
- One language: English (U.S.). The app itself speaks English, Ukrainian, Russian, German and Spanish.
- 3 iPhone and 3 iPad screenshots (Roman's panorama, no captions). No header, no search-results picture, no preview video, no In-App Events.
- Where we rank (iTunes search, US): 14th for "outer news", not in the top 50 for any other news phrase tried. Apple's search box already suggests "outer news: ai brief" first when one types "news ai".

## What people search (M, Apple Ads › Insights › Monthly Search Term Popularity, Oct 2026, read only)

Popularity is Apple's 1–100 scale; the report lists only the top 500 words of a genre, so a phrase missing from it is small, not zero (the 500th word of the news genre scores about 50).

| Store | General news words in the top 500 | Popularity |
| --- | --- | --- |
| US | news | 67 |
| UK | news | 66 |
| Germany | nachrichten / news / nachrichten app kostenlos | 63 / 58 / 56 |
| Spain | noticias | 52 |
| Mexico | noticias | 47 |

Every other entry is a brand (CNN 61, Ground News 61, Apple News 60, Google News 57…). "summary", "brief", "headlines", "politics", "digest", "current events" are not in the US top 500. Ukraine and Kazakhstan are not covered by Apple Ads.

## What people type (M, Apple's search suggestions)

US: "ai news", "news summary", "ai news summary", "unbiased news", "news aggregator", "current events", "news digest", "world news", "headline news". UK the same. Germany: "ki nachrichten", "nachrichten app kostenlos". Spain: "noticias ia", "resumen ia". Ukraine: "новини україни", "новини світу".

## How hard each phrase is (M, US, first 10 apps)

| Phrase | Median ratings of the first 10 | Apps under 100 ratings |
| --- | --- | --- |
| ai news | 4 | 8 of 10 |
| ai news summary | 17 | 8 of 10 |
| unbiased news | 301 | 4 of 10 |
| ask ai news | 1,256 | 2 of 10 |
| headlines | 2,234 | 3 of 10 |
| news summary | 3,058 | 2 of 10 |
| daily news digest | 6,732 | 4 of 10 |
| news aggregator | 38,966 | 1 of 10 |
| news brief | 48,119 | 2 of 10 |
| current events | 226,132 | 1 of 10 |

"ai news" and "ai news summary" are open doors: the apps there are new and small, and their names carry exactly those words. "news" itself belongs to the giants and stays out of reach until we have many ratings.

## What our other apps taught us (M, Drill Sergeant Alarm, Sola Bible, phone themes, 13–16 Nov)

- The name counts most: apps with almost no ratings rank for a phrase their name holds; a subtitle alone did not get Sola Bible ranked.
- Never repeat a name or subtitle word in the keywords; Apple combines words across the three fields.
- Each language page is a page of its own: a store without its language shows English. English (U.K.) is also what the UK, Ukrainian and Polish stores read.
- Name and subtitle change only with a new version; the promotional text can change any time.
- Words that are indexed but do not rank point to ratings, not words: ask for a rating after the reader's second good moment, once per version.
- Header, search picture and preview video: sizes, safe areas and API steps in `~/Documents/independence-army-alarm/products/army-alarm/store/ASSET-PLAYBOOK.md`.

## Proposals

1. **Name "Outer News: AI News Summary"** (27 of 30): holds "ai news", "news summary" and "ai news summary", the open doors. The home screen stays "Outer News".
2. **Subtitle "World headlines, explained"**: fixes the slip and adds "world", "headlines", "explained".
3. **Keywords** without the words already in the name and subtitle, so the 100 characters reach further: `unbiased,current,events,aggregator,brief,digest,daily,briefing,politics,economy,breaking,ask,chat`.
4. **Six more language pages** (English U.K., German, Spanish for Spain and Mexico, Ukrainian, Russian), each with its own words ("KI-Nachrichten", "Noticias con IA", "AI-новини").
5. **Header and search-results picture** in each language, in the style of Roman's screenshots; later a preview video and captioned screenshots.
6. **Rating prompt** after the second good moment (an article read to the end, say), once per version.
7. **Apple Ads** (needs a budget decision): an exact-match test on "ai news", "ai news summary", "news summary" and "unbiased news" in the US and UK at a few dollars a day, to learn which words bring readers before spending more. The account is RS Elite Pro's (Roman's invite); no campaign is created without Yurii's and Roman's yes.

Points 1–4 ship with the next version (any new build); point 5 can go out on its own, since Apple reviews the pictures apart from the version.
