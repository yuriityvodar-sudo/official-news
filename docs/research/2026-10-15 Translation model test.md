# Translation model test

15 October 2026. Translations are a candidate next step (see `Languages and countries to add.md`). The question: which AI translates our summaries into Ukrainian well, and stays free or nearly free.

**Not a decision yet.** Yurii (a native speaker) judges the Ukrainian, then we decide together and record it in `docs/decisions.md`.

## What we ran

- **Input:** the 20 newest real summaries from the live feed (headline, short summary, summary), English into Ukrainian.
- **Prompt:** the same instructions for every model (translate only, copy numbers and names exactly, usual Ukrainian names for institutions, neutral news style), in `server/scripts/translate-test.mjs`.
- **Side by side:** `translation-test/cloudflare-models.html` and `translation-test/groq-models.html`. Open them in a browser.

| Model | Where | OK | Time each | Output tokens | Cost each |
|---|---|---|---|---|---|
| GLM-4.7 Flash (our summarizer) | Cloudflare | 20/20 | 8.7 s | 267 | 11.4 Neurons |
| **Gemma 4 26B** (Google) | Cloudflare | 20/20 | 4.0–4.5 s | 249–257 | **9.7–9.9 Neurons** |
| Mistral Small 3.1 | Cloudflare | 20/20 | 6.1 s | 268 | 23.4 Neurons |
| GPT-OSS 120B (OpenAI) | Groq | 20/20 | 1.3 s | 319 | free tier |
| Qwen 3.8 27B (Alibaba) | Groq | 20/20 | 0.9 s | 276 | free tier |

Thinking was off: `chat_template_kwargs.enable_thinking: false` for GLM and Gemma, `reasoning_effort` "low" for GPT-OSS and "none" for Qwen. With thinking on, Gemma used 1,004 output tokens and 28.6 Neurons for a single translation.

## Quality: first read

This is Claude's first read; Yurii's judgement as a native speaker decides.

- **Gemma: the most natural.** For example, "Уряд Мексики заборонив компанії Avetronic брати участь у державних закупівлях".
- **Qwen: close behind,** with a few clumsy phrases ("забороняє Avetronic на державних закупівлях").
- **GPT-OSS: the most literal.**
  - "Мексиканський уряд забороняє Avetronic у державних контрактах"
  - "торгове рішення" where the standard form is "торговельне"
  - "ІНЕ" for INE
  - Once it added a word that is not in the English ("технічних керівних принципів").

## Free limits we saw

**Cloudflare Workers AI** gives 10,000 Neurons a day, shared with the summaries (about 15.7 per article, see `2026-10-15 Cloudflare usage and free limits.md`). At about 170 articles a day, with a translation costing about 9.8 Neurons per language per article:

| | Neurons a day | Share of the free 10,000 |
|---|---|---|
| Summaries only | about 2,700 | 27% |
| Summaries and 3 languages | about 7,700 | 77% |
| Summaries and 6 languages | about 12,700 | 127%, over the limit |

The Workers Paid plan costs at least $5 a month, and Neurons above the free 10,000 cost $0.011 per 1,000. So 6 languages at 170 articles a day would add about $1 a month (estimate). That plan also lifts the 10 ms CPU limit per run to 30 s (Cloudflare limits page, 15 Oct).

**Groq, free plan:** 1,000 requests a day and 8,000 tokens a minute for `openai/gpt-oss-120b`, from the response headers on 15 Oct. `qwen/qwen3.8-27b` allows 1,000 output tokens a minute, so a request must set `max_tokens` to 1,000 or less. A translation takes about 700 tokens, which covers about 1 to 2 languages a day at our volume (estimate). On 15 Oct Groq's only text models were `openai/gpt-oss-120b`, `openai/gpt-oss-20b` and `qwen/qwen3.8-27b`.

**Mistral:** the free plan no longer allows API keys. On 15 Oct the console said "Upgrade to activate your API keys", and the plans were:
- Free: no API.
- Pro: $11.99 a month, including $30 of API credits.
- Team: $19.99 per user a month.
- Pay-as-you-go.

Mistral Small 3.1 is also on Cloudflare (row above), at more than twice Gemma's cost.

## Round 2: Spanish, German, Polish, Czech and Russian (15 Oct afternoon)

Same prompt, 15 real summaries from the live feed. For the four new languages, all four in one request (the translator itself sends one language per request). Side by side, to open in a browser: `translation-test/openrouter.html`, `translation-test/zai.html` and `translation-test/groq-russian.html`.

| Model | Where | Complete | Time per article | Output tokens per article |
|---|---|---|---|---|
| Gemma 4 31B (`google/gemma-4-31b-it:free`) | OpenRouter, free | 0/15 (HTTP 429, rate limited upstream) | – | – |
| Nemotron 3 Super 120B (`nvidia/nemotron-3-super-120b-a12b:free`) | OpenRouter, free | 6/15 | 70.2 s | 2,504 |
| Nemotron 3 Ultra 550B (`nvidia/nemotron-3-ultra-550b-a55b:free`) | OpenRouter, free | 5/15 | 73.1 s | 2,589 |
| **GLM-4.5-Flash** (`glm-4.5-flash`) | Z.ai, free | **15/15** | 39.9 s (4 languages) | 810 (4 languages) |
| GLM-4.7-Flash (`glm-4.7-flash`) | Z.ai, free | 8/15 | 76.2 s (4 languages) | 812 (4 languages) |
| GPT-OSS 120B, Russian only | Groq, free | 15/15 | 1.2 s | 181 |
| Qwen 3.8 27B, Russian only | Groq, free | 15/15 | 0.8 s | 170 |

- **OpenRouter's free models are not usable:** 0 to 6 of 15 complete, from upstream rate limits and overloads.
- **Z.ai `glm-4.5-flash` completed all 15.** Independent scoring of its answers, 2 reviewers per language, out of 5:

| Language | Accuracy | Fluency | Verdict |
|---|---|---|---|
| Spanish | 4.3 | 3.8 | close: 8/15 publishable unchanged |
| German | 4.4 | 3.3 | facts all right; 2 broken headlines, clumsy phrasing |
| Polish | 3.8 | 2.9 | non-words, false friends: not publishable |
| Czech | 4.1 | 3.0 | misspelled ministry names in headlines: not publishable |

Every number, date and name was right; the weak part is grammar and wording.

- **Decided (Yurii, 15 Oct, `docs/decisions.md`):** Spanish and German go in through Z.ai `glm-4.5-flash`, with `glm-4.7-flash` as its fallback. Polish and Czech wait for a better model. An editor pass, a second call that corrects the wording before publishing, is backlog #54.
- **Russian:** both Groq models completed all 15, so Russian stays on Groq (GPT-OSS first, then Qwen).
- More options checked the same day (batch APIs, other free tiers, translation-only models, on-device translation): `notes/Free AI for translations/more_translation_options.md`.

## Open questions for the decision

1. **Which model reads best in Ukrainian:** Yurii's read of the pages.
2. **One AI call per article (a fixed rule):** translating in the summary's own call keeps the rule. A separate translation call, as tested here, changes the rule, which needs our agreement.
3. **When to translate:** every article into every language, or only the languages people actually read (on demand), which keeps the free limit for longer.
4. **Plan:** stay free (summaries and about 3 languages on Cloudflare, Groq as a helper), or take Workers Paid ($5 a month plus about $1 to $3 of AI at today's volume) for all languages and no CPU limit.
