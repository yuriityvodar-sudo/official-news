# More translation options (research notes)

Checked 15 Oct 2026. Not a decision; nothing here changes `docs/decisions.md` yet.

Goal: translate each article's headline (≤90 chars), short summary (≤200) and summary (≤1,200) from English into Ukrainian, Spanish, Portuguese, Czech, Polish and Russian, as free as possible, at good quality.

Already settled elsewhere (not repeated here): Ukrainian via Groq's free plan; Mistral free, Gemini free tier, GitHub Models, Cerebras, Cohere, Hugging Face credits, DeepSeek free and the DeepL, Google and Azure free quotas are not usable.

## Volume and cost formula

- 300 articles × 6 languages × 30 days = **54,000 translations a month** (1,800 a day).
- Tokens per translation: about 700 (the team's figure), split here as **300 input + 400 output**. This is an estimate: Slavic and Cyrillic output usually takes more tokens than the English input.
- That gives **16.2M input + 21.6M output tokens a month**.
- **Monthly cost = 16.2 × input price + 21.6 × output price**, with prices in $ per 1M tokens.
- Example, gpt-5-nano on Batch: 16.2 × 0.025 + 21.6 × 0.20 = 0.41 + 4.32 = **$4.73**.
- The team's own Workers AI measurement (Gemma 4: 9.8 Neurons per article per language) implies fewer tokens than 700. The token-based costs below are therefore probably on the high side.
- "Bundled" means one call per article returns all languages, so the English input is paid once instead of six times. That cuts input to about 3.2M tokens a month.

## Ranked shortlist (top 5)

All costs cover the full volume of 300 articles × 6 languages a month. With Ukrainian staying on Groq's free plan, the costs are about 5/6 of these.

| # | Option | $/month at 300 × 6 | Quality evidence (UK / CS / PL) | Limits | Terms | Main risks |
|---|---|---|---|---|---|---|
| 1 | **OpenRouter `google/gemma-4-26b-a4b-it:free`** (or `gemma-4-31b-it:free`) | **$0**, plus a one-time $10 credit purchase to unlock 1,000 requests a day | Same model the team already tested on Workers AI, so our own test applies directly. No public translation score for Gemma 4 (the model card shows only MMMLU: 26B 86.3%, 31B 88.4%). Its predecessor Gemma-3-27B scored EN→CS 75.6 in WMT25 human evaluation (news 72.3), against 84.5 for the human reference. | 20 requests/min. 50/day, or 1,000/day after ≥$10 lifetime purchase. Bundling 5 languages per request = 300 requests/day. | OpenRouter's terms. The upstream provider is Google AI Studio's free tier, so Google may use the content to improve its products (fine for public news). Google's EEA clause binds the Gemini API customer, which here is OpenRouter: a grey area. | Free variants come and go without notice; no SLA; capacity is shared, so expect 429s. Needs a paid fallback (the same model is $0.09/$0.30 on OpenRouter ≈ $7.94/month, or Workers AI). |
| 2 | **Workers AI Gemma 4 26B**: free allocation first, Workers Paid for the overflow | **$8.11** for 5 languages, **$9.08** for all 6 (each including the $5 Workers Paid plan) | Already tested by the team. Same public evidence as #1. | About 540 translations/day fit in the free 10,000 Neurons after summaries (10,000 − 300 × 15.7 = 5,290 Neurons ÷ 9.8). The rest is $0.011 per 1,000 Neurons. | Existing Cloudflare account; no new vendor | Needs the Workers Paid plan, which the "free plan only" rule excludes, so this needs a decision. Neurons are shared with summaries. |
| 3 | **On-device: ML Kit on Android and iOS** (`google_mlkit_translation`), optionally Apple Translation on iOS | **$0**, no server work | Google says on-device translation "is intended for casual and simple translations". No public EN→UK/CS/PL benchmark found. Apple Translate has no Czech, even in the iOS 27 beta 3 list. | About 30 MB to download per language. 30–150 MB of memory while a translator is loaded. Plugin needs Android API 23+ and iOS 15.5+. | ML Kit requires Google Translate attribution in the app. Apple: no attribution rule found. | Each device makes its own translation, which nobody can review or check. Changes the plan's principle "one AI call per article, run once on the server" (needs a decisions.md entry). English shows until the language model is downloaded. |
| 4 | **Tencent HY-MT2-30B-A3B** (or 7B) via OpenRouter: a model built only for translation | **$7.57** ($6.61 bundled) | The best public evidence among the cheap options, through its predecessor Hunyuan-MT-7B ("Shy-hunyuan-MT") in WMT25 human evaluation: **EN→CS 87.1, 2nd of 20, above the human reference (84.5)**; EN→UK 88.4 (human reference 87.3); EN→RU 80.2 (2nd). Tencent says HY-MT2 is better still, which is unverified. Polish is supported but not scored. | 8K context (enough). One provider (Tencent). | The open-weight Hunyuan licences exclude the EU, UK and South Korea. I did not check the terms of Tencent's hosted API. | Legal ambiguity for an app with Czech and Polish users in the EU. Listed on OpenRouter only since Aug 2026. China-based provider. |
| 5 | **Small models from the big vendors at 50% off (Batch or Flex)**: Claude Haiku 5.5, gpt-5-nano, Gemini 3.1 Flash-Lite | Haiku 5.5 Batch **$6.21**; gpt-5-nano Batch/Flex **$4.73**; Gemini 3.1 Flash-Lite Batch **$18.23** | No evaluation of these small models found. Their larger siblings lead WMT25: Gemini 2.5 Pro was 1st for CS, UK and RU; GPT-4.1 scored UK 87.9 and CS 80.8; Claude-4 scored UK 85.6 and CS 79.6. | Batch can take up to 24 hours. OpenAI Flex is synchronous but slower and can return "resource unavailable". | Paid plans: inputs are not used for training, and the EEA clause is not a problem | Needs a card and a paid account. Reasoning or thinking tokens are billed as output, so set the effort to minimal or low. A batch delay hurts fresh news. |

Close runners-up:

- **DeepSeek V4.1 Flash**: $15.39/month off-peak, $30.78 at peak (direct API). Its predecessor DeepSeek-V3 scored EN→CS 85.1 in WMT25 (3rd, above the human reference) and EN→UK 85.8. China-based provider.
- **Groq Batch** on the paid Developer plan: gpt-oss-20b for $3.85/month.
- **Ministral 8B**: $5.67/month, with no evaluation found.

### Suggested combination (for discussion)

1. **Cut the volume first** (section 5). With 2 active languages, headline and short summary translated up front, and the full summary translated on open, the need is about 13% of 1,800, roughly 240 translations a day (estimate). That fits in the **Workers AI free allocation (~540/day)** at $0, with no new vendor.
2. As languages fill up, add **#1 (Gemma 4 :free on OpenRouter)** for the overflow. Keep #2 as the paid fallback with the same model, so quality does not change between paths.
3. Use **#3 (ML Kit on the device)** only as a last fallback: when the server has no translation yet, or for languages nobody has turned on.
4. Run **#4 (HY-MT2)** through the plan's 20–30-article model test before any decision. It is the strongest quality candidate, but its terms must be cleared first.

## 1. On-device translation in the app

### Apple Translation framework (iOS)

- **`TranslationSession`**: iOS 18.0+. It is normally obtained from SwiftUI's `.translationTask()`.
- **Translating without any UI**: `init(installedSource:target:)` exists only on **iOS 26.0+**. It throws if the languages are not already installed. Only a session from `.translationTask` can ask the user to download them (`prepareTranslation()` shows the consent sheet).
- **Batch calls**: `translations(from:)` returns results in order; `translate(batch:)` streams them out of order.
- **Strategies (iOS 26.4+)**: `TranslationSession.Strategy.highFidelity` uses Apple Intelligence; Apple says it is "more fluent" and "supports additional languages", and it falls back to `.lowLatency` on devices without Apple Intelligence. The Apple Intelligence language list (iOS 26.1 and 27) has no Ukrainian, Czech, Polish or Russian, so highFidelity probably helps only Spanish and Portuguese (my inference).
- **Translate app languages**: Polish (2022), Ukrainian (iOS 17), Russian, Spanish (Spain; Mexico and US added in iOS 27) and Portuguese (Brazil; Portugal added in iOS 27). **Czech is not in the list**, including the iOS 27 beta 3 list of 30. The framework list is assumed to match; confirm with `LanguageAvailability().supportedLanguages` on a device.
- **Downloads**: models are shared with all apps, including Apple's Translate, so a user who already downloaded a language needs no new download. Apple does not publish the download size (not found).
- **Privacy**: everything is processed on the device. Apple may collect the bundle ID and the language pair, but not the text.
- **Simulator**: does not work; a real device is needed.
- **Quality**: no public benchmark of Apple's on-device translation for EN→UK/CS/PL found.

### Google ML Kit on-device translation (Android and iOS)

- **59 languages**, including uk, cs, pl, ru, es and pt (language page updated 13 Oct 2026).
- **Size**: models are about 30 MB per language and take 30–150 MB of memory when loaded. They download on demand; Google recommends Wi-Fi only.
- **Requirements**: Android API 23+; iOS 64-bit only.
- **Quality**: Google says it "is intended for casual and simple translations" and that quality depends on the language pair. English is the pivot language, which does not matter here because our source is English. Google recommends Cloud Translation for higher fidelity.
- **Terms**: the app must follow Google Cloud Translation's attribution requirements ("translated by Google" style). It is allowed only on phones, tablets and computers, not embedded devices.
- No public EN→UK/CS/PL quality figures found. Indirect evidence: the dedicated translation model NLLB (3.3B) ranked at or near the bottom wherever WMT25 human-evaluated it (EN→Icelandic 24.1, EN→Serbian 53.5, against about 90 for the best). ML Kit's 30 MB models are far smaller. This is my inference, not a measurement.

### Flutter plugins

| Plugin | Version and date (approx.) | pub points / likes / downloads | Publisher | What it wraps |
|---|---|---|---|---|
| `google_mlkit_translation` | 0.15.1, about 18 Aug 2026 | 150 / 74 / 38.3k | flutter-ml.dev (verified; community, not Google) | ML Kit on Android and iOS. iOS 15.5+. You manage models yourself (`OnDeviceTranslatorModelManager`). |
| `local_translation` | 0.1.1, about 17 Sep 2026 | 150 / 1 / 1.31k | ae1.dev (verified) | Apple Translation on iOS 18+ (physical devices only). Android 12+ `TranslationManager`, which is unavailable on many phones and emulators. |
| `apple_native_translate` | 0.1.7, about 4 Sep 2026 | 140 / 0 / 200 | 8-order.co.jp (verified) | iOS only. On iOS 18–25 it gets a session through a hidden 1×1 SwiftUI view; on iOS 26+ it can use the UI-less init. Unsupported pairs return null. |

Takeaway: only ML Kit covers all 6 languages on both platforms with one well-used plugin. Apple adds better integration on iOS but no Czech.

## 2. Batch and discounted APIs

| API | Discount | Can the free plan use it? | Window | Fits fresh news? |
|---|---|---|---|---|
| Groq Batch | 50% (does not stack with prompt caching) | **No.** The rate-limits page says to "Upgrade to Developer plan to access … Batch and Flex processing". | 24 h to 7 days. Does not use the standard per-model limits. | Poorly |
| OpenAI Batch | 50% | Paid account | 24 h | Poorly |
| OpenAI Flex | Same prices as Batch | Paid account; gpt-5 / gpt-5.4 nano and mini only | Synchronous, slower, can be unavailable | Yes, with retries |
| Anthropic Message Batches | 50% | Paid account | Up to 24 h | Poorly |
| Gemini Batch | 50% | Paid tier | Up to 24 h | Poorly |

Monthly cost at 300 × 6 (16.2M input, 21.6M output):

| Model | Standard | Batch/Flex |
|---|---|---|
| Groq gpt-oss-20b ($0.075/$0.30) | $7.70 | $3.85 |
| Groq gpt-oss-120b ($0.15/$0.60) | $15.39 | $7.70 |
| OpenAI gpt-5-nano ($0.05/$0.40) | $9.45 | $4.73 |
| OpenAI gpt-4.1-nano ($0.10/$0.40) | $10.26 | $5.13 |
| OpenAI gpt-4o-mini ($0.15/$0.60) | $15.39 | $7.70 |
| OpenAI gpt-5.4-nano ($0.20/$1.25) | $30.24 | $15.12 |
| OpenAI gpt-5-mini ($0.25/$2.00) | $47.25 | $23.62 |
| Claude Haiku 5.5 ($0.10/$0.50; Batch $0.05/$0.25) | $12.42 | $6.21 |
| Claude Haiku 4.5 ($1/$5) | $124.20 | $62.10 |
| Gemini 2.5 Flash-Lite ($0.10/$0.40) | $10.26 | $5.13 |
| Gemini 3.1 Flash-Lite ($0.25/$1.50) | $36.45 | $18.23 |
| Gemini 3.5 Flash-Lite ($0.30/$2.50) | $58.86 | $29.43 |

Notes:

- gpt-5-nano, Haiku 5.5 (adaptive thinking, default effort medium) and Gemini Flash models can produce reasoning tokens, which are billed as output. Set the lowest effort, or the real cost can be several times higher.
- Gemini 2.5 Flash-Lite has no shutdown date, but Google limits 2.5 access to users who used it recently and recommends 3.5 Flash-Lite for new projects. A new project should expect the 3.1 price or higher.
- Gemini 3.1 Flash-Lite shuts down on 7 May 2027 at the earliest.

## 3. Cheapest paid per-token options (beyond the table above)

| Model and route | $/1M input/output | $/month (300 × 6) | Bundled |
|---|---|---|---|
| Tencent HY-MT2 30B-A3B or 7B (OpenRouter, provider Tencent) | 0.074 / 0.295 | $7.57 | $6.61 |
| Tencent HY-MT2 1.8B (OpenRouter) | 0.044 / 0.177 | $4.54 | $3.96 |
| Gemma 4 26B (OpenRouter, paid) | 0.09 / 0.30 | $7.94 | $6.76 |
| Gemma 4 31B (OpenRouter, paid) | 0.20 / 0.40 | $11.88 | $9.27 |
| Workers AI Gemma 4 26B (9.8 Neurons each, measured by the team) | 0.10 / 0.30 | $5.82 of Neurons + $5 plan; $9.08 after the free allocation | — |
| DeepSeek V4.1 Flash, direct API | 0.15 / 0.60 off-peak; 0.30 / 1.20 peak | $15.39 off-peak; $30.78 peak | $13.43 off-peak |
| DeepSeek V4 Flash via OpenRouter (third-party host) | 0.091 / 0.182 | $5.41 | $4.22 |
| Mistral Small 2603 (OpenRouter list; Batch half) | 0.15 / 0.60 | $15.39 (Batch $7.70) | $13.43 |
| Ministral 8B 2512 (OpenRouter list) | 0.15 / 0.15 | $5.67 (Batch $2.83) | $3.71 |
| Qwen3.5 Flash (OpenRouter) | 0.065 / 0.26 | $6.67 | $5.82 |
| Qwen-MT Flash (Alibaba, Singapore; USD from third parties) | 0.16 / 0.49 | $13.18 (Batch $6.59) | $11.09 |

Peak hours for DeepSeek: 01:00–04:00 and 06:00–10:00 UTC, Monday to Friday.

## 4. Other free tiers in 2026

| Provider | What is free | Production allowed? | Verdict for us |
|---|---|---|---|
| **OpenRouter `:free`** | 20 requests/min. 50/day, or **1,000/day after a ≥$10 lifetime credit purchase** (official limits page). 14 free models today, including **Gemma 4 26B and 31B** (upstream: Google AI Studio). | Yes under OpenRouter's terms. Free endpoints may log or train depending on the provider, and you can filter that in settings. | **Usable**: shortlist #1 |
| **Groq** (update) | Free and Developer chat models are now only **gpt-oss-120b, gpt-oss-20b, gpt-oss-safeguard-20b and qwen3.8-27b (preview, "evaluation only")**. **Llama 3.3 70B and 3.1 8B were shut down for free and Developer tiers on 16 Aug 2026.** Limits are per model, so gpt-oss-20b adds about 285 more free translations a day. | Previews are not for production | Check which model the Ukrainian decision assumed. gpt-oss quality for CS/PL is untested. |
| SambaNova Cloud | Free tier without a card: about 20 requests/day per model (third-party figure; the official page returned 404) | Too small | Not usable |
| Together AI | No free trial; $5 minimum purchase (official support article, updated 1 Jun 2026) | — | Not free |
| Fireworks | About $1 one-time signup credit | — | Not free |
| Nebius Token Factory | About $1 trial credit (unverified) | — | Not free |
| Scaleway Generative APIs | 1M tokens once, shared across models (about 1,400 translations in total) | — | Trial only |
| OVHcloud AI Endpoints | Without a key: **2 requests/min per IP per model** (official). With a key: 400/min, billed per token (gpt-oss-120b about $0.08–0.09 in / $0.40–0.47 out, from aggregators). EU-hosted (Gravelines). | Not stated for anonymous use | Anonymous calls from Workers come from shared Cloudflare IPs, so expect 429s. The paid key is a reasonable EU option. |
| Chutes | Moved to subscriptions ($3/$10/$20); free tier unclear | — | Not free |
| NVIDIA build.nvidia.com | About 40 requests/min with trial credits | Forum moderators: production needs paid or self-hosted NIM | Not for production |
| SiliconFlow | **Hunyuan-MT-7B listed at $0** (model page, read 15 Oct 2026). Rate limits not published. | Unclear; China-based; same licence question as #4 | Worth a test, not a plan |
| Gemini API: Gemma 4 | Free tier only; no paid option exists | EEA clause: only paid services for EEA users | Not usable |
| Workers AI translation models | Only `@cf/meta/m2m100-1.2b` and `indictrans2` (Indic languages). m2m100 costs $0.342 per 1M tokens each way, about **21.7 Neurons per translation (2.2× Gemma 4)**, and it is a 2020 model. No TranslateGemma in the catalogue. | Yes | Not worth it |

Related open model: **TranslateGemma** (Google, Jan 2026; 4B, 12B and 27B; 55 languages). Its 27B has 23.5% lower MetricX error than Gemma 3 27B on WMT24++. It is not hosted on Workers AI or OpenRouter. The one host found is Featherless, with 12B at $0.20 in / $0.60 out.

## 5. Ways to cut the volume

The baseline is 1,800 translations a day. Each step below scales it down.

1. **Translate the headline and short summary up front; translate the full summary when someone opens the article.**
   - The headline and short summary are ≤290 of ≤1,490 characters, about 20% of the text. With prompt overhead, assume about 25% of the tokens (estimate).
   - If a share p of articles is opened in a language, the cost per language is about 0.25 + 0.75 × p. At p = 20% that is **~40% of the baseline**.
   - The worst case never exceeds the baseline: each article-language pair is translated at most once, then stored.
   - Opening an article should show English (or an on-device ML Kit translation) and then swap in the server translation.
2. **Translate up front only the languages people use.** Count active installs per language, for example from the feed request's language parameter. Languages with no users get lazy translation only.
   - Cost scales with active languages ÷ 6. With 2 active languages and step 1: 2/6 × 0.40 ≈ **13% of the baseline, about 240 a day**. That fits in the Workers AI free allocation (~540/day).
3. **Store translations; never translate twice.** Store them in D1, keyed by article, language, field and prompt version.
   - When a lazy translation lands, invalidate or bypass the cached feed for that language, otherwise readers keep seeing English.
4. **Bundle languages in one call** (JSON with one key per language). The English input is paid once.
   - Estimate for Workers AI Gemma 4: if about 4.1 of the 9.8 Neurons are input, 5 languages cost 4.1 + 5 × 5.7 = 32.6 instead of 49 Neurons, **about −33%**.
   - Bundling also keeps OpenRouter at 300 requests a day instead of 1,500.
   - Risk: one failed call loses every language. Validate each language's output (script and language check) and retry only what failed.
5. **Skip what isn't news.** Translate only articles that pass the news-or-noise check, and translate only the headline for low-importance items.
6. **Use Flex rather than Batch** wherever a paid API is used. News loses value within hours, and a batch can take 24 hours.

How these fit the plan's principle "one AI call per article, run once on the server":

- Step 4 (bundling) keeps translation to one call per article.
- Steps 1 and 2 (lazy translation on open) and on-device translation would each change that principle, so they need a `docs/decisions.md` entry before they are built.

## Quality evidence (WMT25, human evaluation)

WMT25 general task, professional annotators, ESA score 0–100. Overall score, with the news-domain score in brackets. The test sets were deliberately hard (literary, social and speech texts), and short official summaries should be easier.

| System | EN→Czech | EN→Ukrainian | EN→Russian |
|---|---|---|---|
| Gemini 2.5 Pro | 88.7 (86.5) — 1st | 90.3 (90.5) — 1st cluster | 83.4 (82.5) — 1st |
| Hunyuan-MT-7B ("Shy-hunyuan-MT") | 87.1 (89.8) — 2nd | 88.4 (90.2) | 80.2 (83.4) — 2nd |
| DeepSeek-V3 | 85.1 (85.6) | 85.8 (88.0) | 73.6 (66.5) |
| Human reference | 84.5 (84.0) | 87.3 (85.3) | 70.5 (65.9) |
| GPT-4.1 | 80.8 (80.7) | 87.9 (88.9) | 76.2 (73.3) |
| Mistral-Medium | 80.4 (78.7) | 84.5 (86.0) | — |
| Claude-4 | 79.6 (78.9) | 85.6 (85.3) | 75.9 (73.5) |
| Llama-4-Maverick | — | 86.2 (86.0) | — |
| Gemma-3-27B | 75.6 (72.3) | not human-evaluated | 61.7 (56.5) |

- **Polish**: no human evaluation of EN→PL in WMT25. WMT24++ (55 languages including Polish; automatic metrics) found frontier LLMs ahead of Google Translate, DeepL and Microsoft in every language. It did not test small models.
- **Small models** (Gemma 4, gpt-oss, Haiku 5.5, gpt-5-nano, Flash-Lite): no public EN→UK/CS/PL scores found. The plan's 20–30-article test is the only reliable check. Add Czech and Polish native-speaker review to it.

## What I could not confirm

- Apple: language download size; any quality benchmark; whether highFidelity adds Czech, Ukrainian or Polish; whether the framework's language list matches the Translate app's list exactly.
- ML Kit: EN→UK/CS/PL quality figures; how much it adds to the iOS app size.
- Groq: the free-plan tab of the rate-limits page did not load. Only the Developer table was readable; its gpt-oss-120b limits match the team's figures (30 RPM, 1K RPD, 8K TPM, 200K TPD).
- OpenRouter Gemma 4 `:free`: upstream capacity and uptime under load; whether Google's EEA clause reaches OpenRouter's users.
- Tencent HY-MT2: the hosted API terms; the exact licence for EU use; Tencent's own benchmark claims.
- SambaNova (official page 404), Nebius and Fireworks free figures (third-party only); OVH per-token prices (aggregators only).
- Gemma 4 translation benchmarks (none in the model card).
- Real token counts per translation. 300 + 400 is an estimate; measure on 20 real articles per language, especially Cyrillic output.

## Sources (read 15 Oct 2026 unless noted)

- Apple: [TranslationSession](https://developer.apple.com/documentation/translation/translationsession), [init(installedSource:target:)](https://developer.apple.com/documentation/translation/translationsession/init(installedsource:target:)), [Strategy](https://developer.apple.com/documentation/translation/translationsession/strategy), [highFidelity](https://developer.apple.com/documentation/translation/translationsession/strategy/highfidelity), [LanguageAvailability](https://developer.apple.com/documentation/translation/languageavailability), [WWDC24 notes](https://wwdcnotes.com/documentation/wwdc24-10117-meet-the-translation-api/), [Translate (Apple), Wikipedia](https://en.wikipedia.org/wiki/Translate_(Apple)), [iOS 27 Translate languages (MacTrast, Jul 2026)](https://www.mactrast.com/2026/07/ios-27-adds-new-languages-and-accents-to-apple-translate/amp/), [Apple Intelligence languages (9to5Mac, Nov 2025)](https://9to5mac.com/2025/11/11/ios-26-1-brings-apple-intelligence-to-these-eight-new-languages/)
- ML Kit: [overview](https://developers.google.com/ml-kit/language/translation), [languages](https://developers.google.com/ml-kit/language/translation/translation-language-support), [Android](https://developers.google.com/ml-kit/language/translation/android), [iOS](https://developers.google.com/ml-kit/language/translation/ios), [terms](https://developers.google.com/ml-kit/language/translation/translation-terms) (all updated 13 Oct 2026)
- pub.dev: [google_mlkit_translation](https://pub.dev/packages/google_mlkit_translation), [local_translation](https://pub.dev/packages/local_translation), [apple_native_translate](https://pub.dev/packages/apple_native_translate)
- Groq: [Batch](https://console.groq.com/docs/batch), [rate limits](https://console.groq.com/docs/rate-limits), [models](https://console.groq.com/docs/models), [deprecations](https://console.groq.com/docs/deprecations), [batch blog (Developer and Enterprise only)](https://groq.com/blog/batch-processing-with-groqcloud-for-ai-inference-workloads)
- Prices: [OpenAI](https://developers.openai.com/api/docs/pricing), [Anthropic](https://platform.claude.com/docs/en/about-claude/pricing), [Claude models](https://platform.claude.com/docs/en/about-claude/models/overview), [Gemini](https://ai.google.dev/gemini-api/docs/pricing), [Gemini deprecations](https://ai.google.dev/gemini-api/docs/deprecations), [Gemini API terms (updated 28 Apr 2026)](https://ai.google.dev/gemini-api/terms), [DeepSeek](https://api-docs.deepseek.com/quick_start/pricing), [Workers AI pricing](https://developers.cloudflare.com/workers-ai/platform/pricing/), [Workers AI models](https://developers.cloudflare.com/workers-ai/models/), OpenRouter public API `https://openrouter.ai/api/v1/models` (prices and free list, 15 Oct 2026), [Qwen-MT Flash](https://help.aliyun.com/en/model-studio/qwen-mt-flash)
- Free tiers: [OpenRouter limits](https://openrouter.ai/docs/api/reference/limits), [OVHcloud AI Endpoints capabilities](https://docs.ovhcloud.com/en/guides/public-cloud/ai-machine-learning/ai-endpoints-capabilities), [Together AI free tier change](https://support.together.ai/articles/1862638756-changes-to-free-tier-and-billing-july-2025), [SambaNova free plan (third party)](https://www.costbench.com/software/llm-api-providers/sambanova-cloud/free-plan/), [NVIDIA forum on limits](https://forums.developer.nvidia.com/t/request-for-nvidia-nim-api-rate-limit-increase-40-200-rpm/375340), [Scaleway free tier (docs PR)](https://github.com/scaleway/docs-content/pull/4819/files), [SiliconFlow Hunyuan-MT-7B](https://www.siliconflow.com/models/hunyuan-mt-7b)
- Quality: [WMT25 findings (ACL Anthology)](https://aclanthology.org/2025.wmt-1.22.pdf), [WMT24++](https://arxiv.org/html/2502.12404), [TranslateGemma report (Jan 2026)](https://hyper.ai/papers/2601.09012), [Hunyuan-MT-7B model card](https://huggingface.co/tencent/Hunyuan-MT-7B/blob/main/README.md), [Gemma 4 model card](https://ai.google.dev/gemma/docs/core/model_card_4), [Hunyuan licence EU exclusion (HN discussion)](https://hn.svelte.dev/item/45114379)
