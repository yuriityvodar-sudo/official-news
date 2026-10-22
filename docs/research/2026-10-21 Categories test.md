# Categories test: the IPTC Media Topics top level (#127)

Roman, 21 October 2026. A proposal for the categories an article is filed under, and the evidence for it. Nothing here is built yet: the contract, the prompt and the style guide change in the implementation pull request, once this is agreed.

## Why

What a reader sees depends on the article's category: the Topics filter, and later the "For you" feed (#83) and the part of the summary written for a reader's interest. A doctor following health should not get a court decision, or a line written for lawyers. Today the summarizer picks 1 to 3 of our own 14 topics in passing, in the same call that writes the summary, and nothing checks them.

On 30 real news articles from the live database (20 October, all 13 source countries, every kind of page), 17 had no topic their reader would pick. Transport, farming and fisheries, jobs and civil service, family and benefits all ended up in `economy`, or in a topic that does not fit (driver exams in `education`, a ministry's code of conduct in `justice`).

## The proposal

**Categories are standard and broad.** We use the top level of [IPTC Media Topics](https://iptc.org/standards/media-topics/), the vocabulary news agencies tag their stories with (CC BY 4.0, so the app credits IPTC). 13 of its 17 top-level categories fit official decisions, as 12 categories of ours (culture and sport share one):

| Our id | IPTC top level | What belongs |
| --- | --- | --- |
| `politics` | politics and government (medtop:11000000) | government and parliament, elections and referendums, how the state and its ministries are organised and run, international relations, treaties and diplomacy |
| `economy` | economy, business and finance (medtop:04000000) | taxes, budgets and public spending, business and competition rules, banking and finance, trade, energy, transport, agriculture and fisheries, housing and construction, prices |
| `labour` | labour (medtop:09000000) | jobs, wages, working conditions, labour law, employment programmes, public servants' and veterans' work rights |
| `society` | society (medtop:14000000) | social protection (benefits, pensions, family support), migration and citizenship, human rights, equality, land rights, communities |
| `health` | health (medtop:07000000) | medicine, care, hospitals, medicines, public health, addiction |
| `education` | education (medtop:05000000) | schools, universities, exams, vocational training and qualifications |
| `justice` | crime, law and justice (medtop:02000000) | courts, criminal and civil law, police and their powers, prisons, public records |
| `conflict` | conflict, war and peace (medtop:16000000) | armed forces, defence, war and peace, military service |
| `disaster` | disaster, accident and emergency incident (medtop:03000000) | natural disasters, fires, floods, accidents, emergency response and civil protection |
| `environment` | environment (medtop:06000000) | climate, emissions, nature and protected areas, pollution, waste and water |
| `science-technology` | science and technology (medtop:13000000) | research and science funding, digital services, data and privacy, telecoms, AI and online platforms |
| `culture-sport` | arts, culture, entertainment and media (medtop:01000000) and sport (medtop:15000000) | culture, heritage, media, sport and major public events |

Not used: human interest, lifestyle and leisure, religion and weather; official decisions are rarely about them.

**Each article gets one main category and 0 to 2 secondary ones.** The main category is the reader whose life or work the decision changes most, not the ministry that decided and not the words in the title. A secondary category is added only when the decision directly changes something for that reader too. Filters show an article under its main and its secondary categories; a "For you" ranking weighs the main category more.

**Still one AI call per article.** The categories are part of the summarizer's one answer, decided first, before the summary is written for the main category's reader.

## The test

The same 30 articles, labelled by hand first (Roman with Claude Code, before any model run), then sorted by Gemma 4 26B (`@cf/google/gemma-4-26b-a4b-it`, temperature 0.2, JSON schema with the 12 ids, thinking off) with the prompt below, categories only. About 9 Neurons per article.

**Result: the main category matched the hand label in 24 of 30 articles. In the other 6 the model and the label swapped main and secondary. There were no misses, and every article found a fitting category.**

The 6 swaps are cases a person could argue either way: parents' tax numbers on birth certificates (`justice` or `society`), NFC access on Apple's platform (`science-technology` or `economy`), driver training (`education` or `labour`), the Andorra and San Marino agreement (`politics` or `economy`).

The model adds secondary categories too readily: the Polish VAT bill also got `environment`, Korea's livestock rules `justice`, Germany's investment overview `society`. The rule above ("only when the decision directly changes something for that reader") goes into the prompt, and secondary categories weigh less in any ranking.

| # | Article | Human label | Model | Same main | Old topics (stored) | Fitting old topic? |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | Brazil, bill: parents' CPF numbers on birth certificates | `justice` + `society` | `society` + `justice` | swapped | `justice` | no (family, public services) |
| 2 | Brazil, bill: speed control system for large trucks and buses | `economy` + `science-technology` | `economy` + `justice`, `disaster` | yes | `security-defence`, `technology` | no (transport) |
| 3 | Brazil, bill: Rio Doce basin environmental protection area | `environment` | `environment` + `economy` | yes | `climate` | yes |
| 4 | Brazil, bill: training programme for vulnerable teenagers | `education` + `society` | `education` + `society`, `labour` | yes | `education` | no (social support) |
| 5 | Poland: capacity auction parameters for 2028 | `economy` | `economy` | yes | `energy` | yes |
| 6 | Poland, VAT bill: KSeF penalties delayed, reverse charge for gas and power | `economy` | `economy` + `science-technology`, `environment` | yes | `economy`, `energy` | yes |
| 7 | Poland: training and exams for road haulage drivers | `education` + `economy`, `labour` | `labour` + `economy` | swapped | `education` | no (transport) |
| 8 | UK: Digital and Technologies Jobs Plan | `labour` + `science-technology`, `education` | `labour` + `education`, `science-technology` | yes | `economy`, `technology`, `education` | no (jobs) |
| 9 | UK, CMA consultation: NFC access on Apple's platform | `science-technology` + `economy` | `economy` + `science-technology` | swapped | `technology` | yes |
| 10 | UK: Construction Jobs Plan | `labour` + `economy` | `labour` + `economy`, `education` | yes | `economy` | no (jobs) |
| 11 | South Africa: labour tenants' land claim, farm Mooiplaats | `society` + `economy` | `society` + `economy` | yes | `human-rights` | no (land, farming) |
| 12 | South Africa: labour tenants' land claim, farm Grootpan | `society` + `economy` | `society` + `economy` | yes | `justice` | no (land, farming) |
| 13 | Argentina: higher grants in addiction prevention | `health` | `health` + `society` | yes | `health` | yes |
| 14 | Argentina: employer contribution withholding for staffing agencies ended | `economy` + `labour` | `labour` + `economy` | swapped | `economy` | no (jobs) |
| 15 | Argentina: voluntary redundancy for federal civil servants | `labour` + `politics` | `labour` + `economy` | yes | `justice`, `economy` | no (jobs, civil service) |
| 16 | Korea: livestock rules (permits, cages, fines) | `economy` | `economy` + `justice` | yes | `economy`, `justice` | no (farming) |
| 17 | Korea: personal data in the young farmers' support scheme | `economy` + `science-technology` | `economy` + `science-technology`, `society` | yes | `economy`, `justice` | no (farming) |
| 18 | Korea: military service counts as work experience in the public sector | `labour` + `conflict` | `labour` + `society` | yes | `economy` | no (jobs) |
| 19 | Mexico: early voting model for the 2026-2027 elections | `politics` | `politics` | yes | `elections` | yes |
| 20 | Mexico: code of conduct of the transport ministry | `politics` | `labour` + `politics` | swapped | `justice` | no (public administration) |
| 21 | Mexico: new boundaries of the port of Mazatlán | `economy` | `economy` + `politics` | yes | `trade` | no (transport) |
| 22 | EU: Vision 2040 for fisheries and aquaculture | `economy` + `environment` | `economy` + `environment`, `labour` | yes | `economy`, `climate`, `technology` | no (farming, fisheries) |
| 23 | EU: association agreement with Andorra and San Marino | `politics` + `economy` | `economy` + `politics`, `society` | swapped | `trade`, `economy` | yes |
| 24 | Canada, bill C-22: police access to data (Senate debate) | `justice` + `science-technology` | `justice` + `science-technology`, `politics` | yes | `security-defence`, `justice` | yes |
| 25 | Canada, bill C-219: Magnitsky sanctions | `politics` + `society` | `politics` + `society` | yes | `foreign-affairs`, `human-rights` | yes |
| 26 | Indonesia: economic report, Q4 budget spending | `economy` | `economy` + `society`, `politics` | yes | `economy` | yes |
| 27 | Indonesia: president orders a bigger forest fire response | `disaster` + `environment` | `disaster` + `environment`, `conflict` | yes | `climate`, `security-defence` | yes |
| 28 | Germany: what the government does for investment (overview) | `economy` | `economy` + `science-technology`, `society` | yes | `economy`, `technology` | yes |
| 29 | US: executive order on women's health | `health` + `science-technology` | `health` + `science-technology`, `politics` | yes | `health`, `economy` | yes |
| 30 | Czechia: results of the government meeting, 19 Oct | `politics` + `environment`, `education` | `politics` + `economy`, `society` | yes | `education`, `climate`, `migration` | no (several decisions in one) |

The prompt used in the test:

```text
You sort official government decisions into categories for a news app, so that each reader sees the decisions about what they care about. You get one page from an official website.
Ask: whose life or work does this decision change? The category is that reader's interest, not the ministry that decided and not the words in the title.
The categories (based on the IPTC Media Topics top level):
- politics: government and parliament, elections and referendums, how the state and its ministries are organised and run, international relations, treaties and diplomacy.
- economy: taxes, budgets and public spending, business and competition rules, banking and finance, trade, energy, transport, agriculture and fisheries, housing and construction, prices.
- labour: jobs, wages, working conditions, labour law, employment programmes, public servants' and veterans' work rights.
- society: social protection (benefits, pensions, family support), migration and citizenship, human rights, equality, land rights, communities.
- health: medicine, care, hospitals, medicines, public health, addiction.
- education: schools, universities, exams, vocational training and qualifications.
- justice: courts, criminal and civil law, police and their powers, prisons, public records.
- conflict: armed forces, defence, war and peace, military service.
- disaster: natural disasters, fires, floods, accidents, emergency response and civil protection.
- environment: climate, emissions, nature and protected areas, pollution, waste and water.
- science-technology: research and science funding, digital services, data and privacy, telecoms, AI and online platforms.
- culture-sport: culture, heritage, media, sport and major public events.
Return one JSON object: {"primaryTopic": the one category whose reader this decision changes most, "secondaryTopics": 0 to 2 other categories whose readers it also directly concerns}. Answer with the JSON object only.
```

## Moving over

**Stored articles** keep working through a fixed map from the 14 topics to the new ids. The first mapped topic becomes the main category. `labour` and `culture-sport` appear only on newly summarized articles.

| Old topic | New category |
| --- | --- |
| `foreign-affairs`, `elections` | `politics` |
| `economy`, `trade`, `energy` | `economy` |
| `migration`, `human-rights` | `society` |
| `health` | `health` |
| `education` | `education` |
| `justice` | `justice` |
| `security-defence` | `conflict` |
| `climate` | `environment` |
| `science`, `technology` | `science-technology` |

**The API:**
- `primaryTopic` is added to the article.
- `topics` keeps its form: main category first, then the secondary ones.
- `topic=` and `GET /topics` use the new ids. An old id is still accepted and mapped, so app builds from before the change keep filtering.

**The app (Yurii, #67):** names in 5 languages and icons for the 12 categories, the Topics chips, and an "IPTC Media Topics, CC BY 4.0" credit line.
