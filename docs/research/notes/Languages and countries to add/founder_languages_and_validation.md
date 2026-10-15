# Ukrainian, Russian and Czech versions of Official News, and cheap ways to validate language/country demand

Research date: 2026-10-15. Each figure has its year. "Inference" means my reasoning from the cited facts, not a sourced fact. Some fetches were blocked (Internews full report 403, AppleInsider 403, a 2026 Diia article 410), so a few figures come from secondary reports. Those are labelled.

Repo context checked on 2026-10-15 (`docs/sources.csv`): the current G20 list already includes `ru-kremlin-acts` (Kremlin decrees and laws, Russian-language source), `eu-commission-press-releases` (EU), `de-government-articles` (Germany), plus GB, US, CA, and others. All summaries are in English today.

## Ukrainian: how many speakers, and where (Ukraine, EU temporary protection by host country, Poland, Germany, Czechia, US, Canada)

### Takeaway
About 5.8 million refugees from Ukraine were recorded outside Russia in April 2026, and 4.43 million held EU temporary protection on 31 July 2026. The audience is concentrated in Germany (1.29M), Poland (0.95M) and Czechia (0.40M), and North America adds about 0.55 million more. Czechia has by far the highest share per head of population.

### Cited Findings
- EU total under temporary protection, 31 July 2026 (Eurostat): 4.43 million. Germany 1,290,225 (29.1%), Poland 953,060 (21.5%), Czechia 395,225 (8.9%). Czechia had the highest ratio per head at 36.2 per 1,000 people, then Slovakia 27.5 and Cyprus 26.7, against an EU average of 9.8. These are secondary reports of Eurostat data. — [Censor.net citing Eurostat](https://censor.net/en/news/4017921/over-4-4-million-ukrainians-hold-eu-temporary-protection); [Sofia Globe citing Eurostat, July 2026](https://sofiaglobe.com/?p=128941)
- 30 June 2026: 4.41 million, the highest since the mechanism was activated in March 2022. Germany 1,286,230, Poland 961,170, Czechia 390,810. Between June and July 2026 the largest increases were in Czechia (+4,415), Romania (+4,055) and Germany (+3,995), while Poland fell. — [Euromaidan Press, 12 Aug 2026](https://euromaidanpress.com/2026/08/12/a-record-4-41-million-ukrainians-are-under-eu-protection-and-few-are-going-home/); [Ukrinform](https://www.ukrinform.net/rubric-society/4121483-number-of-ukrainian-refugees-in-eu-slightly-decreases-eurostat.html)
- UNHCR data cited by Ukraine's Ministry of Economy: 5.762 million Ukrainian refugees worldwide excluding Russia on 30 April 2026, of whom 5.213 million were in Europe and 0.549 million outside it. — [Interfax-Ukraine](https://en.interfax.com.ua/news/general/1186730.html). UNHCR's own December 2025 figure is a bit higher: 5.9 million registered refugees worldwide, 5.3 million in Europe, and 9.6 million people displaced in total. — [UNHCR Europe regional update, 2026-03](https://www.unhcr.org/system/files/protected-files/2026-03/europe-95-sc-e.pdf). The two differ on method or date and I could not reconcile them.
- Poland: more than 950,000 Ukrainians held PESEL UKR status (2026, Polish digital ministry data). 61% of holders are women, and 77% of adult holders are women. — [money.pl](https://www.money.pl/gospodarka/status-ukr-i-ochrona-w-polsce-ministerstwo-ujawnia-dane-7318255462611072a.html); [netfreedom.org.ua, 2026](https://netfreedom.org.ua/ru/skilky-ukrayincziv-v-polshhi-aktualni-dani-2026-roku/)
- Czechia: almost 613,000 Ukrainians were legally resident at the end of 2025, more than half of 1,131,197 foreigners. These are Interior Ministry residence registers. — [Expats.cz](https://www.expats.cz/czech-news/article/legal-foreign-population-in-czechia-surpasses-1-1-million-new-data-shows)
- Canada (CUAET): 305,380 arrivals by 31 July 2025, from 1,189,320 applications. The programme closed for arrivals on 31 March 2024. — [IRCC committee data tables, Oct 2025](https://www.canada.ca/en/immigration-refugees-citizenship/corporate/transparency/committees/cimm-oct-2-2025/data-tables-responses-recent-crises.html); [IRCC QP note 2025](https://search.open.canada.ca/qpnotes/record/cic%2CIRCC-2025-QP-00035)
- United States: almost 240,000 Ukrainians were paroled through Uniting for Ukraine between May 2022 and December 2024, and another 30,000–35,000 were paroled at the border. More than 250,000 are estimated to be in the US on parole now. These are advocacy-group estimates, not DHS figures. All parole programmes were suspended in January 2025. — [Ukraine Task Force, U4U four-year retrospective, 2026](https://ukrainetaskforce.org/uniting-for-ukraine-a-four-year-retrospective/). Ukraine's TPS designation is reported to run to 19 October 2026 (secondary source). — [VisaVerge](https://www.visaverge.com/news/187000-ukrainians-granted-temporary-reprieve-from-u-s-deportation-amid-war/)
- The EU extended temporary protection to 4 March 2027 (political agreement 13 June 2025, Implementing Decision (EU) 2025/1460 of July 2025). It also discussed what happens when it ends: a move to national residence status or help with returning home. — [EUAA](https://dip.euaa.europa.eu/node/802); [Eurointegration](https://www.eurointegration.com.ua/eng/news/2025/07/15/7215949/)

### Inferences
- Inference: about 5.8M Ukrainian refugees plus the population inside Ukraine (no reliable 2026 census) make Ukrainian the largest of the three languages by speakers. The diaspora is also spread over a few clear hosts (DE, PL, CZ, then US, CA, UK), which makes country-specific tests easy to run.
- Inference: a large share of the diaspora's legal status depends on dates set by governments: EU TP to 4 Mar 2027, US TPS to 19 Oct 2026, Polish PESEL UKR deadlines. That is the kind of "official decision" content the app already summarises.

### Gaps
- I did not reach the Eurostat dataset (migr_asytpsm) directly. The figures above come from news reports of Eurostat releases.
- I found no 2026 Council decision extending TP beyond 4 March 2027. My search found only the 2025 extension. Check the Council press room.
- No reliable current figure exists for the population inside Ukraine or for how many people there speak Ukrainian versus Russian.

## Ukrainian: smartphone and news habits in Ukraine (wartime consumption, Telegram, trust in official channels, Diia)

### Takeaway
Ukraine is a smartphone-first, social-first news market dominated by Telegram, where about half of people get their news. Trust in Telegram is much lower than its reach, and trust in traditional media recovered in 2025. Diia shows that a state app can reach most adults (about 23–24 million users).

### Cited Findings
- Internews Ukraine / InMind, "Ukrainian Media: News Consumption and Trust in 2025". 1,649 respondents in cities above 50,000 people, May–August 2025, margin of error ≤2.5%. Results:
  - 86% got news from social platforms (up 35 points since 2015).
  - 37% use social media as their only news source.
  - Smartphones are the main news device for 91% (74% among ages 46–65, 96% among ages 18–35).
  - Television audience fell from 85% in 2015 to 33% in 2025.
  - Trust in traditional media rose from 47% (2024) to 53% (2025).
  - Source: [Internews Ukraine](https://internews.ua/en/media-research/ukrainian-media-news-consumption-and-trust-in-2025) (full page returned 403 to me, so the figures come from the search snippet); [UkraineWorld summary](https://ukraineworld.org/articles/opinions/ukrainians-consume-news-2025-survey)
- Same survey, trust by source: family 83%, military leadership (General Staff/MoD) 64%, regional social networks 60%, national social networks 55%, national news websites 52%, national TV 43%. 46% report fatigue with war news. — [UkraineWorld](https://ukraineworld.org/articles/opinions/ukrainians-consume-news-2025-survey)
- Rating Group (July–August 2025): Telegram is the main news source for 51%, up from 47% in 2024. YouTube is second at 25%. — [Ukrainska Pravda, 25 Sep 2025](https://www.pravda.com.ua/eng/news/2025/09/25/7532494)
- Rating Group for Lviv Media Forum / IMS (April 2025): 52% read Telegram channels constantly or often. Trust in Telegram channels is 29% and in YouTube channels 24%. — [Rating Group](https://www.ratinggroup.ua/en/news/media-aug2025); [Komersant](https://komersant.ua/en/ukraintsi-vtrachaiut-doviru-do-bud-iakykh-dzherel-informatsii-opytuvannia)
- Oxford Internet Institute, national survey of 2,014 people (August 2024): 86% have a Telegram account and 47% trust Telegram channels as a news source. — [OII](https://www.oii.ox.ac.uk/who-trusts-telegram-in-wartime-ukraine/)
- State TV telethon (United News), 2024: 37% watch it, and 37% trust it partly or fully. — [Internews release](https://internews.ua/en/opportunity/media_trust_consumption_2025_release); [Komersant](https://komersant.ua/en/telemarafon-b-ie-antyrekordy-ukraintsi-bilshe-ne-viriat-derzhavniy-informatsii)
- Diia: 21 million or more unique app users (October 2024, Cabinet of Ministers), with 24 documents and more than 30 services. — [kmu.gov.ua](https://www.kmu.gov.ua/en/news/ponad-21-milion-ukraintsiv-korystuiutsia-diieiu-de-dostupni-24-dokumenty-ta-ponad-30-servisiv). More than 23 million users in 2025 and more than 24 million app users in 2026 (plus about 7 million portal users), from Ministry-linked figures reported by RazomUA. I could not open the 2026 article (HTTP 410). — [RazomUA 2025](https://razomua.media/en/news/tekhnolohiyi/diya-2025-zymova-1000-lidyrue-yak-tsifrovi-posluhy-zmitsnyuyut-tyl)

### Inferences
- Inference: Ukrainians already get a constant stream of wartime news, and almost half report fatigue. A calm, neutral "what the government decided" feed fits that fatigue. The cited 2025 data show no competitor in that format, but they do not prove demand.
- Inference: Telegram is where Ukrainian readers already are, so a Telegram channel that mirrors the app's Ukrainian summaries is the cheapest test of demand and trust (see the playbook).
- Inference: Diia's reach shows that Ukrainians install and use state-related apps. Diia, though, is about services and documents, not news about decisions.

### Gaps
- The Internews 2025 trust breakdown by platform (Telegram on its own) and any trust figure for official government Telegram channels were not available to me (403).
- KIIS 2025 figures on trust in Telegram were not found in this search.
- No figure was found for the share of Ukrainians reading news in Russian versus Ukrainian in 2025–2026.

## Ukrainian: do refugees want host-country official decisions in Ukrainian, and is that an unmet need?

### Takeaway
The evidence is indirect but consistent. Since 2022, language has been the main barrier to official information, few refugees use host-government sources directly, and the rules on residence and protection keep changing in 2026 (Poland, Czechia, the US, the EU). The specific gap, timely and neutral Ukrainian summaries of host-country decisions, is plausible but not proven. Many NGO and Telegram channels already cover part of it.

### Cited Findings
- CLEAR Global (September 2022, 139 responses from 30 countries, not representative): people who fled the war named information in a language they don't understand as their biggest barrier. Hosts and volunteers named the same barrier. Practical topics (work, education, language courses) ranked highest. — [CLEAR Global](https://clearglobal.org/wp-content/uploads/2022/10/Language-and-information-gaps-for-people-fleeing-war-in-Ukraine-CLEAR-Global-September-2022.pdf)
- Internews, Romania (2022): only about a quarter of refugees use official Romanian sources (21% sometimes, 4% often). Volunteers relay official information instead. — [Internews "Bridges and Barriers"](https://internews.org/wp-content/uploads/2022/09/BRIDGES-AND-BARRIERS-v_FINAL.pdf)
- CDAC Network (June 2023): language barriers still block access, and refugees need up-to-date information on legal status and integration. — [CDAC 4th snapshot](https://www.cdacnetwork.org/s/4th-Ukraine-snapshot-report.pdf)
- FMR (2023): the choice between Ukrainian and Russian is sensitive, and more Russian speakers have switched to Ukrainian since February 2022. — [Forced Migration Review](https://www.fmreview.org/?p=2174)
- Czechia: a Charles University study (22 interviews) found Telegram is the most used network among Ukrainian migrants. They trust information from institutions' web pages only to a limited extent and trust social networks more. — [Charles University IMS report](https://iss.fsv.cuni.cz/sites/default/files/uploads/files/AC%20MINTE%20CZ%20%20REPORT%202.pdf)
- Czech rules keep changing:
  - The Interior Minister said temporary protection would end for Ukrainians in Czechia if a ceasefire is declared. — [Radio Prague](https://english.radio.cz/node/8843246)
  - Protection expires within 90 days for people whose registered address is a Ministry of Interior office. — [UNHCR Help Czechia](https://help.unhcr.org/czech/?p=5748)
  - A Prague "Unity Hub" was set up to inform Ukrainians about protection status and voluntary return. — [EUAA](https://dip.euaa.europa.eu/node/884)
- Polish rules keep changing in 2026:
  - The special act was phased out and Poland moved to the general EU temporary protection regime.
  - PESEL UKR was extended to 4 March 2027.
  - People whose status was based on a declaration had to confirm their identity by 31 August 2026 or lose UKR status on 1 September 2026.
  - From 4 March 2026, applications must be made within 30 days of entry.
  - In June 2026, some applicants were refused because they did not come from an active-hostility region.
  - Sources: [KLR travel blog](https://klr.com.ua/en/blog/timchasovyy-zakhyst-u-polshchi-dlya-ukraintsiv-2026-pesel-ukr-karta-cukr-ta-novi-pravyla); [Dudkowiak law firm](https://www.dudkowiak.com/blog/president-signs-law-phasing-out-the-ukrainian-special-act-temporary-protection-extended-until-2027/); [SUD.UA, June 2026](https://sud.ua/en/news/abroad/364710-ukrayintsi-v-polschi-zishtovkhuyutsya-z-novimi-obmezhennyami-ta-vidmovami-u-vidachi-pesel-ukr)
- US: U4U was suspended in January 2025, re-parole processing resumed in June 2025 after a pause, and DHS sent revocation emails in April 2025 that it later called errors. — [Ukraine Task Force](https://ukrainetaskforce.org/uniting-for-ukraine-a-four-year-retrospective/)

### Inferences
- Inference: the need is strongest in Poland, Czechia and Germany, around legal-status decisions (protection extensions, residence-card transitions, benefit changes) with hard deadlines. This is "host-country decisions translated into Ukrainian", which is not what the app does today: it summarises G20 decisions in English.
- Inference: the competition is not a missing service. NGO pages (UNHCR Help), host-government pages and many Telegram groups already exist. The app's edge would be a neutral, sourced summary linking to the official original, which fits the stated low trust in some institutional sites and the high use of Telegram.
- Inference, a risk: summarising legal-status rules creates expectations close to legal advice. A clear "not legal advice, read the original" notice and a link to the official source on every item are essential.

### Gaps
- I found no 2025–2026 representative survey of refugees' information needs (UNHCR protection profiling 2025, IOM) that measures demand for host-government decisions in Ukrainian specifically.
- I found no subscriber counts for the largest Telegram channels serving Ukrainians in Czechia, Poland or Germany. These would be the practical benchmark for competition.
- I did not verify Germany's 2025–2026 rule changes (for example, moving newly arrived Ukrainians from Bürgergeld to asylum-seeker benefits).

## Russian: number of Russian speakers by country outside Russia

### Takeaway
The audience outside Russia is large but spread out, and most figures are old censuses with mixed definitions. The biggest pools are Kazakhstan, Belarus, the Baltics, Germany and Israel. In Ukraine, the use of Russian has been shrinking since 2022.

### Cited Findings
All figures below come from the Wikipedia compilation of national censuses and surveys. "Native" and "total incl. second language" are different measures. — [Wikipedia: Geographical distribution of Russian speakers](https://en.wikipedia.org/wiki/Geographical_distribution_of_Russian_speakers)
- Kazakhstan: 3,793,800 native speakers (21.2%, 2017); 14,391,085 total (83.7%, 2021). Russian is used on an equal footing with Kazakh in state administration.
- Belarus: 6,672,964 native (70.2%, 2009). Russian is co-official.
- Kyrgyzstan: 482,200 native (8.9%, 2009); 3,432,633 total (49.5%, 2022). Russian is official.
- Uzbekistan: 720,300 native (2.1%, 2021).
- Latvia: 698,757 native (33.8%, 2011); 1,403,776 total (76.2%, 2024).
- Lithuania: 190,733 native (6.8%, 2021); 1,894,158 total (67.4%, 2021).
- Estonia: 383,118 native (29.6%, 2011); 887,270 total (66.6%, 2021).
- Israel: 1,155,960 (15%, 2011).
- Germany: 1,877,000 (2.3%, 2024). Other sources give about 3 million. — [FluentU](https://fluentu.com/blog/russian/countries-that-speak-russian)
- United States: 1,004,815 (2023).
- Ukraine: 14,273,670 native (29.6%, 2001 census); 22.3 million total (2006). These figures are badly out of date.
- Moldova: 264,162 native (2014). Georgia: 3.18 million total (2019). Armenia: 1.91 million total (2022).
- Since February 2022, growing numbers of Russian speakers in Ukraine have begun speaking Ukrainian. — [FMR 2023](https://www.fmreview.org/?p=2174)
- Czechia: Russians are about 3% of the 1.13 million foreign residents (end of 2025). — [Expats.cz](https://www.expats.cz/czech-news/article/legal-foreign-population-in-czechia-surpasses-1-1-million-new-data-shows)

### Inferences
- Inference: outside Russia, the Russian-reading audience is roughly in the tens of millions as a second language. It is split across about 10 countries whose own governments mostly publish in their state languages. Kazakhstan, Belarus and Kyrgyzstan also publish official acts in Russian.
- Inference: many Ukrainian refugees also read Russian. A Russian version aimed at them, though, conflicts with the language sensitivity documented by FMR, and Ukrainian is the safer choice for that audience.

### Gaps
- No consistent, recent cross-country count of Russian readers exists. The census years range from 2001 to 2024.
- I did not research news and app habits in Kazakhstan, Israel or the Baltics.

## Russian: App Store and Google Play in Russia, payments, state restrictions on foreign apps and VPNs, RuStore (2022–2026)

### Takeaway
The iOS App Store still works in Russia, but Apple has removed about 190 apps at the regulator's request (2022–2025), and payments stopped on 1 April 2026. RuStore and the state messenger Max must be preinstalled on devices from 1 September 2025. For a free app, distribution is technically possible, but it depends on Roskomnadzor and Apple's compliance.

### Cited Findings
- Apple stopped processing payments for App Store and other media purchases in Russia from 1 April 2026. New purchases, in-app purchases and subscription renewals fail unless the user already has an Apple Account balance, and apps bought earlier remain available. The last workaround, topping up through mobile operators, was closed. — [MacTrast, Apr 2026](https://www.mactrast.com/2026/04/apple-turns-off-app-store-and-services-payments-in-russia/); [RevenueCat](https://www.revenuecat.com/blog/growth/russia-app-store-payment-block); [Meduza](https://meduza.io/en/news/2026/04/02/report-apple-lets-russian-users-keep-icloud-data-after-subscriptions-lapse)
- Apple disclosed that it removed 190 apps from the Russian App Store at Roskomnadzor's request over three years. In 182 of the 190 cases, the regulator cited the law on "undesirable organisations". — [Novaya Gazeta Europe, 31 Mar 2026](https://novayagazeta.eu/articles/2026/03/31/apple-reveals-it-bowed-to-kremlin-pressure-to-remove-190-apps-from-russian-app-store-over-three-years-en-news)
- VPN apps: Apple removed 25 VPN apps at Roskomnadzor's request in July 2024, and more removals followed, including proxy clients during the Telegram crackdown. Independent media apps were removed in October–November 2024. — [Novaya Gazeta Europe 2024](https://novayagazeta.eu/en/articles/2024/07/04/apple-bows-to-kremlin-pressure-to-remove-leading-vpns-from-russian-appstore-en-news); [TechRadar](https://www.techradar.com/vpn/vpn-privacy-security/apple-removes-custom-vpn-clients-from-russian-app-store-amid-telegram-crackdown); [The Bell](https://en.thebell.io/kremlin-piles-pressure-on-apple/)
- Preinstallation: from 1 September 2025, the state messenger Max must be preinstalled on phones and tablets sold in Russia. RuStore, already preinstalled on Android, must be preinstalled on Apple devices too. — [Cyprus Mail / Reuters, 21 Aug 2025](https://cyprus-mail.com/2025/08/21/russia-to-pre-install-state-backed-max-messenger-on-all-phones-from-september); [bne IntelliNews](https://www.intellinews.com/russian-state-max-messenger-mandatory-across-all-devices-399063/). By July 2026, Apple was reported to face a fine of about $52M for not installing state-required apps (headline only, page blocked). — [AppleInsider, 1 Jul 2026](https://appleinsider.com/articles/26/07/01/apple-in-russias-crosshairs-again-facing-52m-fine-for-not-installing-state-required-apps)
- Law signed 31 July 2025, in force 1 September 2025:
  - Fines of 3,000–5,000 roubles for deliberately searching for "extremist" material.
  - A ban on advertising VPNs, with fines up to 500,000 roubles for companies.
  - VPN use counts as an aggravating circumstance.
  - Source: [Meduza](https://meduza.io/en/news/2025/07/31/putin-signs-law-penalizing-online-searches-for-content-deemed-extremist-by-russian-authorities); [OVD-Info](https://ovd-info.org/en/express-news/2025/07/31/putin-has-signed-law-introducing-fines-searching-extremist-materials-online)
- Apple reportedly closed the Apple Developer Enterprise Program to Russian developers in February 2025 (secondary report). — [The Bell](https://en.thebell.io/kremlin-piles-pressure-on-apple/)

### Inferences
- Inference: a free app with no in-app purchases is not affected by the April 2026 payment stop. Russian users can still download it, but it can be removed on request at any time, as 190 apps were.
- Inference: "official sources only" is not a defence in Russia. The removals cite the "undesirable organisations" law, so a feed that also carries EU or Ukrainian government decisions in Russian could be treated as hostile content.

### Gaps
- Google Play in Russia: I did not verify its 2025–2026 status (paid apps and billing were suspended in 2022, but I did not re-check this session). I also did not check RuStore's rules for publishing foreign apps.
- I did not confirm whether Roskomnadzor has blocked any neutral foreign news-summary app (as opposed to independent media apps).

## Russian: reputational and political risks for a neutral app in Russian, and Russian government sites blocking foreign traffic

### Takeaway
Small apps face low legal risk below the Russian-law thresholds, but the reputational risk with the founder's Ukrainian audience is high. Fetching from Russian government sites is also unreliable: about 46% of Russian government domains were found blocked or restricted from abroad (2023), and two of four sites failed over https in my own test.

### Cited Findings
- "Landing law" (Federal Law 236-FZ, in force July 2021): foreign owners of resources with 500,000 or more daily Russian users must open a Russian office and register with Roskomnadzor. Russian-language content is one of the criteria that brings a resource under the law. — [CMS Law-Now](https://www.cms-lawnow.com/ealerts/2021/07/russia-adopts-law-forcing-foreign-it-companies-to-land-in-the-country)
- News aggregator law (2016):
  - It covers Russian-language aggregators with more than 1 million daily users.
  - They are liable for news not taken from media registered in Russia, must store news for six months, and must remove disputed items within 24 hours.
  - Only Russian citizens or companies may own such aggregators.
  - Source: [RSF](https://rsf.org/en/news/new-russian-law-targets-news-aggregators); [OSCE](https://www.osce.org/fom/246471)
- Geoblocking (USENIX Security 2023): of 542 accessible Russian government domains, 136 (25.09%) blocked every tested foreign country. A further 112 (20.66%) were reachable only from Russia and Kazakhstan. The methods were ad hoc (DNS and TCP timeouts, 403 responses, block pages). — [Lantern corpus summary of Ramesh et al., 2023](https://corpus.lantern.io/findings/2023-ramesh-network__russia-gov-geoblocking-ad-hoc-mechanisms/)
- My own test, 2026-10-15 at 09:31 UTC, from a Kenyan IP (single vantage point, curl):
  - Russian sites: `http://kremlin.ru` 200; `https://government.ru` timed out but `http://government.ru` 200; `https://duma.gov.ru` timed out; `http://publication.pravo.gov.ru` 200.
  - The repo already notes that Kremlin https timed out from Kenya on 14 October (`docs/sources.md`, `docs/sources.csv`).
  - Ukrainian sites: `https://zakon.rada.gov.ua`, `https://www.rada.gov.ua` and `https://data.rada.gov.ua` all timed out at 25 s; `https://www.president.gov.ua` returned 403; `https://www.kmu.gov.ua` 200.
  - Czech, Kazakh and Belarusian sites: `https://vlada.gov.cz`, `https://e-sbirka.gov.cz`, `https://www.psp.cz`, `https://www.mvcr.cz`, `https://www.gov.kz`, `https://adilet.zan.kz` and `https://pravo.by` all returned 200.

### Inferences
- Inference: the app is far below the 500k and 1M daily-user thresholds, so these Russian laws would not formally apply at launch. Removal from the App Store needs no threshold, though.
- Inference, a reputational risk: a Ukrainian founder shipping a Russian-language version during the war can read as normalising Russian state messaging, especially if the feed shows Kremlin decrees in Russian. If Russian is ever offered, it is safer framed as "for Russian readers in Kazakhstan, the Baltics, Israel and Germany", with Russia's own decrees treated like any other G20 source. This is a product judgement, not a sourced fact.
- Inference, a fetcher risk: the Ukrainian parliament's legal database also failed from abroad in my test. A Ukrainian version that relies on zakon.rada.gov.ua needs a test from Cloudflare first. kmu.gov.ua (Cabinet) answered fine. The project's own rule (`docs/sources.md`) is "https only", so the Russian sites that answer only over http would be excluded.

### Gaps
- I tested from one vantage point only (Kenya). Cloudflare Workers egress from varying locations, so the real test is a fetch from the Worker.
- An English web search (2026-10-15) found no published reports that zakon.rada.gov.ua or rada.gov.ua block foreign IPs. The cause of my timeouts (geoblocking, DDoS protection, or an outage) is unknown. A search in Ukrainian or a test from an EU IP would help.
- I did not verify the 2025–2026 "foreign agent" amendments' direct effect on foreign apps (for example, an advertising ban on foreign-agent platforms). I found only a 2024 bill. — [OCCRP](https://www.occrp.org/en/news/russia-plans-to-ban-advertisements-on-websites-of-foreign-agents)

## Czech: market size, smartphone/news habits, existing services (Hlídač státu, e-Sbírka), Seznam, and Ukrainians in Czechia

### Takeaway
Czech is a small market (10.9M people) with low trust in news (31% in 2026), a strong local player (Seznam), and good free official data (e-Sbírka). No free consumer app summarising government decisions was found. Ukrainians are about 5.6% of residents, the highest refugee share per head in the EU, so a Czech plus Ukrainian bundle covering Czech decisions is the most distinctive idea among the three languages.

### Cited Findings
- Population: 10,915,839 on 31 December 2025, the highest since WWII (Czech Statistical Office, published 18 May 2026). — [ČSÚ](https://csu.gov.cz/pocet-struktura-a-projekce-obyvatel); [e15](https://www.e15.cz/domaci/v-cesku-zije-uz-10-55-milionu-lidi-pocet-obyvatel-stoupa-i-diky-imigraci-1281448). The Reuters Digital News Report (DNR) 2026 uses 10.6 million (UN-based), so the two sources differ.
- Reuters DNR 2026, Czech Republic:
  - Internet penetration 88%.
  - Trust in news 31% (down 2 points; global average 37%).
  - Paying for online news 13%.
  - News avoidance 41% (up 4 points).
  - AI is "significantly reducing traffic to Czech websites".
  - Publishers negotiated licensing with Seznam, "the major domestic online player".
  - Source: [Reuters Institute DNR 2026](https://reutersinstitute.politics.ox.ac.uk/digital-news-report/2026/czech-republic)
- Reuters DNR 2025, Czech Republic:
  - "Smartphones have now become the primary devices for news."
  - Trust 33%, and 22% share news via social, messaging or email.
  - Use of online platforms and social media for news was the lowest since 2016.
  - Seznam is "the largest Czech digital media company" and is under competition investigation for suspected abuse of dominance (Newsfeed ad revenue).
  - Public service media are among the most trusted brands.
  - Source: [Reuters Institute DNR 2025](https://reutersinstitute.politics.ox.ac.uk/digital-news-report/2025/czech-republic); [MediaGuru](https://www.mediaguru.cz/clanky/2025/06/ct-a-cro-veri-nejvice-lidi-nasleduje-cnn-prima-news/)
- e-Sbírka: a free official database of consolidated laws since 1945, fully operational since 1 January 2024. Lupa.cz notes that consolidated texts can lag behind amendments. — [EU Publications Office forum](https://op.europa.eu/en/web/forum/czechia-oj); [Lupa.cz](https://www.lupa.cz/clanky/co-nabizi-nova-e-sbirka-a-jak-se-s-ni-pracuje/)
- Hlídač státu is run by Hlídač státu, z. ú. (not by Transparency International, despite one search summary). It covers state contracts, subsidies, public tenders, salaries of officials and politicians, political sponsorship, K-Index and state websites, and sends alerts on new items. Its homepage lists no coverage of laws, bills or government resolutions, and I saw no mobile app. — [hlidacstatu.cz](https://www.hlidacstatu.cz/)
- Paid alternative: ASPI Monitor legislativního procesu (Wolters Kluwer) tracks bills from intent to publication, with email alerts, for 3,990 CZK per user per year excluding VAT. — [Wolters Kluwer](https://www.wolterskluwer.com/cs-cz/solutions/aspi/svet-aspi/nastroje/aspi-monitor-legislativniho-procesu)
- Ukrainians in Czechia:
  - 395,225 under temporary protection (July 2026), 36.2 per 1,000 inhabitants, the highest in the EU. — [Censor.net citing Eurostat](https://censor.net/en/news/4017921/over-4-4-million-ukrainians-hold-eu-temporary-protection)
  - About 613,000 Ukrainians legally resident in total (end of 2025). — [Expats.cz](https://www.expats.cz/czech-news/article/legal-foreign-population-in-czechia-surpasses-1-1-million-new-data-shows)
  - In 2025, 23.1 thousand of the 42.0 thousand net migrants were Ukrainian citizens (ČSÚ). — [Expats.cz](https://www.expats.cz/czech-news/article/legal-foreign-population-in-czechia-surpasses-1-1-million-new-data-shows)
  - Telegram is their most used network, and their trust in institutional websites is limited. — [Charles University](https://iss.fsv.cuni.cz/sites/default/files/uploads/files/AC%20MINTE%20CZ%20%20REPORT%202.pdf)

### Inferences
- Inference: Czech readers who distrust media (31% trust) and avoid news (41%) may value a neutral "only what the government decided, linked to the source" format. That is a hypothesis to test, not a finding.
- Inference: the cost of entry is low. vlada.gov.cz, psp.cz, mvcr.cz and e-sbirka.gov.cz all answered from abroad in my test (above). Czechia is not G20, so a Czech version means new sources, not just a translation.
- Inference: Seznam controls search, homepage and news distribution in Czechia. A small app will not be found through Seznam without effort, and the App Store, Google Play and Telegram are the realistic channels.

### Gaps
- No 2025–2026 figures were found for Czech platform use for news (Facebook, YouTube, TikTok percentages), weekly reach of Seznam Zprávy, or the share of news read through apps. These are in the DNR PDF country tables, which I did not extract.
- I did not check whether a Czech government decisions app or Telegram channel exists (for example, the government's own "Vláda ČR" channels or an app from the Chamber of Deputies). Competitor work is in `competitors.md` in this folder.

## For each language: what users would most likely want, and whether the current G20 English sources are relevant

### Takeaway
Each of the three audiences mostly wants decisions from its own or its host government. The current English G20 feed is relevant to them only at the edges: the EU, Germany, the US, Canada and the UK for Ukrainian refugees, and the Kremlin source for Russian readers. Translating today's feed alone is unlikely to be enough. Each language needs at least one or two new national sources.

### Cited Findings
- Ukrainian refugees' top information needs are practical: legal status, work, education, services. — [CLEAR Global 2022](https://clearglobal.org/wp-content/uploads/2022/10/Language-and-information-gaps-for-people-fleeing-war-in-Ukraine-CLEAR-Global-September-2022.pdf); [CDAC 2023](https://www.cdacnetwork.org/s/4th-Ukraine-snapshot-report.pdf)
- The current repo sources include the EU Commission press releases, Germany's Federal Government, the UK, the US, Canada and Russia's Kremlin acts (`docs/sources.csv`, checked 2026-10-15). Ukraine (not G20), Poland (not G20) and Czechia (not G20) are not covered.
- In 2024, 37% of Ukrainians watched the state telethon and 37% trusted it partly or fully, while 64% trusted military leadership (2025). — [Komersant](https://komersant.ua/en/telemarafon-b-ie-antyrekordy-ukraintsi-bilshe-ne-viriat-derzhavniy-informatsii); [UkraineWorld](https://ukraineworld.org/articles/opinions/ukrainians-consume-news-2025-survey)

### Inferences
- **Ukrainian, inside Ukraine:** they would want decisions of Ukraine's Cabinet (kmu.gov.ua answered), the Verkhovna Rada (failed from abroad in my test) and the President (403 in my test). They may also want EU decisions on accession and aid. G20 decisions matter only where they touch Ukraine (sanctions, aid), so the current feed is weakly relevant without a Ukraine source.
- **Ukrainian, abroad:** they would want host-country decisions (Germany, Poland, Czechia, US, Canada, UK) plus EU temporary protection decisions. The current feed already has DE, US, CA, GB and EU, so a Ukrainian translation of those, filtered to migration and residence topics, is a meaningful slice even before adding Poland or Czechia. This is the best fit with the existing pipeline. Inference only.
- **Russian:** readers in Kazakhstan, Belarus or Kyrgyzstan would want their own governments' decisions, which are mostly not in G20. Kazakhstan's gov.kz and adilet.zan.kz and Belarus's pravo.by answered in my test. Russian readers in Germany, Israel or the Baltics would want host-country decisions, which are only partly in the current feed (DE, EU). Russia's own decrees are already a source. Inference: the relevance of the current feed is mixed.
- **Czech:** readers would want Czech government and parliament decisions plus EU decisions. G20 decisions are interesting but secondary. Inference: the current feed is of low direct relevance without Czech sources.

### Gaps
- I found no survey asking any of these audiences directly whether they want foreign (G20) government decisions summarised in their language. The validation playbook below is meant to produce that evidence.

## Validation playbook: cheap or free ways to measure language/country demand after launch

### Takeaway
Free first-party tools can show demand by storefront country (App Store Connect, Play Console) and by device language (Firebase). Apple's keyword popularity and custom product pages let you test messages per locale at no cost. The cleanest cheap signal combines device language with a fake-door "Want this in Ukrainian/Czech/Russian?" tap rate measured in Firebase, and a Telegram mirror channel for each language.

### Cited Findings
- **App Store Connect analytics:**
  - Impressions count an icon seen for more than 1 second anywhere on the App Store, with a unique-devices variant. — [AppTweak](https://www.apptweak.com/en/aso-blog/measure-your-aso-efforts-with-app-store-connect)
  - Product page views are counted per visit. — [AppTweak](https://www.apptweak.com/en/aso-blog/measure-your-aso-efforts-with-app-store-connect)
  - Territory is the App Store storefront, set by the customer's billing address. — [App Store Connect Help, dimensions](https://developer-rno.apple.com/help/app-store-connect/reference/app-analytics-filters-and-dimensions)
  - Source Type shows where the user found the app (App Store Search, Browse, web or app referrer). — [App Store Connect Help, dimensions](https://developer-rno.apple.com/help/app-store-connect/reference/app-analytics-filters-and-dimensions)
  - Downloads straight from search results count without a product-page view, so the search conversion rate can exceed 100%. — [Onde](https://onde.app/blog/app-performance-itunes)
- **Apple keyword popularity:**
  - Apple Ads gives a 5–100 popularity score per keyword and storefront, updated daily. It is relative, not a search count, and appears to be a 7-day moving average. — [Sonar](https://trysonar.app/blog/apple-search-popularity); [MobileAction](https://helpcenter.mobileaction.co/what-is-popularity-score)
  - A single blog reports that since October 2025 the API returns scores only for keywords at 35 or above. Unverified with Apple. — [Sonar](https://trysonar.app/blog/apple-search-popularity)
  - Creating an Apple Ads account costs nothing until a campaign runs. — [Sonar setup guide](https://trysonar.app/blog/how-to-set-up-apple-search-ads.md)
  - Apple Ads runs in 91 countries and regions. — [Apple Ads help](https://ads.apple.com/app-store/help/ad-placements/0081-ad-placement-options)
- **Custom product pages:**
  - Up to 70 per app, each localisable, each with its own keywords so it appears in search for those keywords.
  - Per-page analytics show impressions, downloads, redownloads, conversion rate and retention.
  - Apple says referring users to a custom page adds 2.5 percentage points to conversion on average, against a 1.6% average on default pages.
  - Source: [Apple Developer](https://developer.apple.com/app-store/custom-product-pages/)
  - Keyword assignment arrived around July 2025 and the 35→70 limit around October 2025 (third-party dates). — [Adapty](https://adapty.io/blog/custom-product-pages-app-store/); [AppDrift](https://appdrift.co/blog/app-store-custom-product-pages-guide)
- **Google Play Console:**
  - The Listing conversion analysis report shows visitors, acquisitions and conversion rate, filterable by country, language, traffic source, store listing and UTM. It includes peer conversion benchmarks per country, and Google suggests high-visitor countries as candidates for a custom store listing. — [Play Console Help 9859173](https://support.google.com/googleplay/android-developer/answer/9859173?hl=en)
  - Store listing experiments can test icon, graphics, screenshots, video and descriptions in up to 5 languages, with a minimum detectable effect and a sample calculator. — [Play Console Help 6227309](https://support.Google.com/googleplay/android-developer/answer/6227309); [Play Console Help 12053285](https://support.google.com/googleplay/android-developer/answer/12053285?hl=en)
  - Confidence can be set from 90% to 99% (third-party report). Run tests for at least a week. — [Yellowhead](https://www.yellowhead.com/blog/google-play-experiments-tool-now-in-beta/)
- **Firebase Analytics (Flutter):**
  - "Language" is an automatically collected user property, the device's OS language setting such as en-us. "Country" is also automatic. — [AdMob/Firebase help](https://support.google.com/admob/answer/9755590?hl=en); [Firebase user properties](https://firebase.google.com/docs/analytics/flutter/user-properties)
  - Up to 25 custom user properties can be set with `setUserProperty`. — [Firebase user properties](https://firebase.google.com/docs/analytics/flutter/user-properties)
- **TestFlight public link:** it accepts up to 10,000 testers. Filters are device, platform and OS version only. Metrics show how many viewed and accepted the invite. No country filter or country breakdown is documented. — [App Store Connect Help, external testers](https://www.developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers)

### Inferences
These steps are proposed by me, not sourced, and are ordered from cheapest to costliest.
1. **Device language first (free, about 1 hour of work).** Firebase's automatic Language property shows how many current English-app users have a uk, ru or cs device. This is the best single proxy, because storefront country hides refugees: a Ukrainian in Germany with a German Apple ID shows as "Germany" in App Store Connect. Read it as "language × country".
2. **Fake door in the app (free).** Add a one-time card or settings row, "Read in: Українська / Čeština / Русский (coming soon), tap to vote". It should log an event with the chosen language and show "Thanks, we'll tell you when it's ready". Show it only to users whose device language is not English, plus a random 10% of others as a control. Disclose that it is a poll, not a broken feature, to stay honest and within App Review guidance.
3. **Store-side message test (free).** Localise the store listing metadata (title, subtitle, keywords, screenshots) for uk, cs and ru before translating the app. Keep the description honest: "summaries in English; Ukrainian coming". Then compare impressions, product page views and conversion by territory in App Store Connect and Play Console. On iOS, a custom product page per language with its own keywords isolates the effect. Check Apple Ads popularity for terms like "закони", "рішення уряду", "zákony" or "vláda" per storefront before choosing keywords. Low or absent scores (below 35 is now hidden) mean organic store demand is small.
4. **Telegram mirror channel per language (free).** Post the daily summaries of host-country and EU decisions, machine-translated and reviewed, for 4–6 weeks. Track subscribers, views per post and forwards, and put a UTM-tagged store link in the channel bio. This tests the audience where Ukrainians and Czech-based Ukrainians already are (cited above).
5. **Landing pages per language (free with Cloudflare Pages).** Add one page each for /uk, /cs and /ru with a store button and an email/Telegram "notify me". Google Search Console, free, shows impressions and clicks by query and country. This was not re-verified this session.
6. **TestFlight public link per language.** This is weak for country data (none is documented), but separate links posted in different channels (a Ukrainian Telegram group, a Czech forum) give a count per link through the viewed/accepted metrics.

### Gaps
- I could not confirm whether App Store Connect now shows organic search terms (Apple Ads shows search terms only for paid campaigns), or the exact 2025 changes to App Store Connect analytics.
- I could not confirm whether Apple Ads, and therefore popularity scores, is available in the Ukrainian, Czech, Kazakh or Russian storefronts. Russia is very likely unavailable. Check the storefront list in Apple Ads.
- Details of Apple's product page optimisation tests (number of treatments, duration) were not verified this session.

## Benchmarks: what counts as a meaningful signal (conversion rates, minimum sample sizes)

### Takeaway
I found no public News-category conversion benchmark. The general 2025 US benchmarks are about 8.6% page-view-to-install on the App Store and about 16% on Google Play. Apple's own figure for default pages is 1.6%, measured on a different definition. With small traffic, read only large differences: about 400 views per variant are needed to see a 5-point difference, and about 900 per variant to tell 8% from 12%.

### Cited Findings
- AppTweak 2025 (US only):
  - App Store conversion rate (downloads ÷ page views) averages 8.56%, from 52.8% for Food & Drink down to 5.2% for Trivia games.
  - Google Play averages 16.15%.
  - The App Store install rate (downloads ÷ impressions) averages 3.8%.
  - News was not reported. The article also contains internal inconsistencies (it mentions a "25%" figure).
  - Source: [AppTweak, May 2026](https://www.apptweak.com/aso-blog/mobile-app-store-conversion-rate-benchmarks-per-category)
- An older AppTweak-based figure (H1 2024) gave a 25% average App Store conversion rate, so the methods differ between years. — [Adapty](https://adapty.io/blog/markdown/app-store-conversion-rate.md)
- Apple says default product pages average 1.6% conversion, and custom pages add 2.5 points on average. Apple's definition is probably impressions-based. — [Apple Developer](https://developer.apple.com/app-store/custom-product-pages/)
- Google Play offers peer conversion benchmarks per country inside the console (free), which is the most relevant benchmark for this app's own category. — [Play Console Help](https://support.google.com/googleplay/android-developer/answer/9859173?hl=en)

### Inferences
These are my calculations with standard formulas (95% confidence, 80% power), not sourced benchmarks.
- **Estimating a single rate**, for example the fake-door tap rate in one language: about 385 exposed users give ±5 points, and about 100 give ±10 points (n = 1.96² × 0.25 / margin²).
- **Comparing two rates**, for example store conversion with and without Ukrainian metadata: 8% against 12% needs about 880 page views per variant, and 10% against 20% about 200 per variant.
- **Practical thresholds** for a small free app (my suggestions, to agree with Roman):
  - Do not read a locale until it has at least 100 exposed users and at least 10 conversions.
  - Treat a fake-door tap rate of 15% or more among users with a matching device language as a strong signal, and below 3% as weak. These are judgement calls, not industry benchmarks.
  - For the Telegram mirror, a views-per-post to subscribers ratio above about 30% after 4 weeks suggests real reading. This is also a judgement call, and I found no source.
- **Store conversion in a new locale:** compare against the app's own English baseline and against Play's peer benchmark for that country, not against the US averages above. This matters especially for Ukrainian, where many readers sit in DE, PL or CZ storefronts.

### Gaps
- I found no published conversion benchmark for the App Store "News" category in 2025–2026, and none at all for the UA or CZ storefronts.
- I found no benchmark for fake-door tap rates or Telegram view rates from a reliable source.
