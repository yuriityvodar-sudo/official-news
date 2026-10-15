# Free AI APIs for translating summaries (status 2026-10-15)

> **Correction (2026-10-15, measured):** the summarizer uses about **15.7 Neurons per article**, not the 60–70 in `docs/decisions.md` (Cloudflare analytics: 2,615 Neurons for 167 calls on 14 Oct; see `docs/research/2026-10-15 Cloudflare usage and free limits.md`). So at 170 articles a day the summaries use about 2,700 of the free 10,000 Neurons, and Workers AI itself has room for 1–2 extra languages (about 8 Neurons per language per article, estimate). The Workers AI figures below that use 60–70 are too high; a second provider matters from about 3 languages.


The question: which free AI API could translate our summaries into Ukrainian, Spanish, Portuguese, Czech, Polish and Russian, as a second provider next to Workers AI? It has to be callable from a Cloudflare Worker (free plan), allowed in a free public app, and good in those six languages.

How to read the evidence in these notes:

- **"Official page (date)"** is a provider's own pricing, limits, terms or docs page, read on 2026-10-15. The date in brackets is the "last updated" date the page shows. "No date" means the page shows none.
- **"Third party"** means a blog, tracker or aggregator. Free-tier numbers there often conflict and go stale, so they are marked as such.
- **"Probe"** means a live request I made on 2026-10-15 from a test machine, which is on a Kenyan IP. It shows what that request got back. It does **not** show what a Cloudflare Worker gets back.
- **"Repo"** means files in this repository (`server/wrangler.jsonc`, `docs/decisions.md`).
- **Estimates are labelled "estimate".** All arithmetic is shown.
- **Not tested:** I have no API keys, so I made no calls from a Worker to any provider. One test call per provider from the deployed Worker would settle whether that provider is reachable from there.

---

## 1. The workload everything is compared against

### Characters (exact, from the length limits)
- Text per article: headline 90 + short summary 200 + summary 1,200 = **1,490 characters**, rounded to 1,500.
- One language for a day: 170 articles × 1,500 = **255,000 characters**.
- All six languages for a day: 255,000 × 6 = **1,530,000 characters**.
- For a 30-day month: one language is 7,650,000 characters, and all six are **45,900,000 characters**.

### Tokens and requests (estimates)
- English source: 1,490 characters ÷ about 4 characters per token is about **375 tokens**. The 4-characters rule of thumb is for English text.
- Instructions plus JSON wrapper: about 300 tokens (estimate).
- Output per language: translations run about 10–20% longer than the English, and Cyrillic and Czech/Polish diacritics split into more tokens. That gives about 470–715 tokens; **600 is used below** (estimate, depends on the tokenizer).

| Way of calling | Requests a day | Tokens per request (in + out) | Tokens a day |
|---|---|---|---|
| A. One request per article per language | 170 × 6 = **1,020** | 675 + 600 | 1,020 × 1,275 ≈ **1.30 M** (~39 M/month) |
| B. One request per article, all six languages in one JSON | **170** | 750 + 3,600 | 170 × 4,350 ≈ **0.74 M** (~22 M/month) |
| C. Two requests per article, three languages each | **340** | 725 + 1,800 | 340 × 2,525 ≈ **0.86 M** |

Option B needs a model that can return about 3,600–4,200 output tokens per call.

### Why Workers AI's free allocation cannot also do translations (official prices, math)
- Free allocation: **10,000 Neurons a day** on Workers Free. Above that, use needs Workers Paid at $0.011 per 1,000 Neurons — [Workers AI pricing](https://developers.cloudflare.com/workers-ai/platform/pricing/) (official, no date shown).
- `@cf/zai-org/glm-4.7-flash` costs 5,500 Neurons per M input tokens and 36,400 per M output tokens (same page).
  - Option A: 1,020 × (675 × 0.0055 + 600 × 0.0364) = 1,020 × 25.5 ≈ **26,000 Neurons a day**.
  - Option B: 170 × (750 × 0.0055 + 3,600 × 0.0364) = 170 × 135 ≈ **23,000 Neurons a day**.
- Cheaper models on Workers AI, same page:
  - `@cf/google/gemma-4-26b-a4b-it` costs 9,091 Neurons per M input and 27,273 per M output. Option B: 170 × (6.8 + 98.2) ≈ **17,900 Neurons a day**.
  - `@cf/meta/m2m100-1.2b` costs 31,050 Neurons per M tokens. Option A: 1,020 × 975 × 0.03105 ≈ **30,900 Neurons a day**.
- The summaries already use most of the allocation. `docs/decisions.md` (2026-10-14) records about **60–70 Neurons per article**. At 170 articles that is 10,200–11,900 Neurons a day, which is already at or above the free 10,000 (repo).
- So translations need another provider, and summaries may need one too at 170 articles a day.

---

## 2. Summary table

"Fits?" compares the free limit with Option B (170 requests and ~0.74 M tokens a day). For per-model limits it uses one model.

| Provider | Free limit today | Fits? | Production / commercial use on free tier | Free-tier data used for training | Card |
|---|---|---|---|---|---|
| **Google Gemini API** | New projects (measured Sep 2026, third party): Flash-Lite models **15 RPM, 500 RPD**; Flash models 5 RPM, 20 RPD. Google no longer publishes the numbers. | B: yes (on 3.5 or 3.1 Flash-Lite). A: no. | **Terms: only paid services may be used for apps available to users in the EEA, Switzerland or the UK** | Yes (human review too) | No |
| **Groq** | gpt-oss-120b / gpt-oss-20b / qwen3.8-27b: **30 RPM, 1K RPD, 8K TPM, 200K TPD** each | No: one model covers ~46 articles a day | Not restricted in the Services Agreement. Free services are allowed ("fee-free"). | No | No |
| **Mistral (Experiment / Free mode)** | Official: shown only in the console. Third party: **1 req/s, 500K TPM, 1B tokens/month per model** | Yes, by far (A and B) | Mistral says free mode is "intended for evaluation and prototyping". I found no prohibition. | Yes by default; opt-out toggle exists | No (phone number) |
| **OpenRouter `:free` models** | **20 RPM, 50 RPD**; **1,000 RPD** once $10 of credits has ever been bought | 50 RPD: no. 1,000 RPD: yes (B). | Terms cover using it in your own product. Reselling API access is barred. | Depends on the provider behind each model | No ($10 once for 1,000 RPD) |
| **Z.ai (GLM-4.7-Flash)** | Official: "Completely Free", price $0. Third party: **1 concurrent request**. No daily cap found. | Probably yes (A ≈ 1.4–2.8 h of calls a day, estimate) | Terms let you integrate the API into apps for end users | API content not used unless you agree (clause in brackets) | No |
| Cerebras | **No ongoing free tier.** $5 one-time credit after adding a card, expires in 30 days | No | "not intended for production use" | n/a | **Yes** |
| GitHub Models | **Retired 30 July 2026** | No | n/a | n/a | n/a |
| Cohere | Trial: **1,000 calls a month**, 20 RPM | No (~33 a day) | **"not permitted to be used for production or commercial purposes"** | n/a | No |
| Hugging Face Inference Providers | **Free users: no monthly credits** (PRO gets $2) | No | n/a | n/a | n/a |
| SambaNova | Free tier: **20 RPM, 20 RPD, 200K TPD** per model | No | Preview models: evaluation only | n/a | No |
| DeepSeek | **No free tier** (paid only; granted balance only if promotional) | n/a | n/a | n/a | Top-up |
| NVIDIA build.nvidia.com | Trial credits (1,000 at signup, reported), ~40 RPM | No (credits run out) | "prototyping, research, development and testing purposes only" | Reported yes | No |

RPM = requests per minute; RPD = requests per day; TPM / TPD = tokens per minute / day.

---

## 3. Per provider: cited findings

### Google Gemini API (AI Studio key)

**Limits**
- The official rate-limits page (updated 2026-10-13) has **no free-tier table**. It says limits "can be viewed in Google AI Studio", that "Specified rate limits are not guaranteed", and that limits are "more restricted for experimental and preview models" — [rate limits](https://ai.google.dev/gemini-api/docs/rate-limits).
- Pricing page (updated 2026-10-15) — [pricing](https://ai.google.dev/gemini-api/docs/pricing):
  - Free of charge: Gemini 3.8 / 3.6 Flash, 3.5 Flash-Lite, 3.1 Flash-Lite, the 2.5 models and **Gemma 4**.
  - "Used to improve our products" is **Yes** on the free tier and No on the paid tier.
  - Gemma 4 has **no paid tier** ("Not available").
- Measured on 2026-09-02 with a new project and no billing. The limits were read from the 429 error body. Third party — [aiplug.work](https://aiplug.work/en/blog/gemini-free-tier-limits):
  - gemini-3.5/3.6/3.7-flash and 3-flash-preview: **5 RPM, 20 RPD**.
  - gemini-3.5-flash-lite and gemini-3.1-flash-lite: **15 RPM, 500 RPD**.
  - Quota is counted per project, not per key, and resets at midnight Pacific.
  - ScriptByAI gives the same RPD (20 for Flash models, 500 for Flash-Lite) as of September 2026 — [scriptbyai](https://www.scriptbyai.com/gemini-api-free-tier-limits/).
- Gemma 4 on the free tier: **15 RPM and 1,500 RPD** per a single third-party guide. **Not confirmed** — [tilnote](https://tilnote.io/pages/6a51b3398d9a59d14c1c174c).
- TPM for Flash-Lite: **not found** in any source.

**Terms** (Gemini API Additional Terms, updated 2026-04-28, effective 23 March 2026) — [terms](https://ai.google.dev/gemini-api/terms):
- "You may use only Paid Services when making API Clients available to users in the European Economic Area, Switzerland, or the United Kingdom."
  - "API Clients" means "a website, application, or other service".
  - Our app targets Spain, Portugal, Czechia and Poland (EEA). **My reading:** the free tier is not allowed for this app, even though the calls come from our server. This is a legal reading, not confirmed with Google.
- Unpaid services: Google "uses the content you submit … to provide, improve, and develop" its products, and "human reviewers may read, annotate, and process your API input and output". Our input is public government text.
- You "must be 18 years of age or older". API Clients must not be "directed towards or … likely to be accessed by individuals under the age of 18".
- "You may only access the Services … within an available region."
- Kenya and Ukraine are on the available-regions list. Russia is not — [available regions](https://ai.google.dev/gemini-api/docs/available-regions) (updated 2026-04-28).

**Calling from a Worker**
- A forum thread from 12 Oct 2026 reports "400 — User location is not supported for the API use" from a Cloudflare Worker. Direct calls from the same developer worked. No fix was confirmed — [Google AI forum](https://discuss.ai.google.dev/t/gemini-api-location-error-400-when-called-from-cloudflare-workers/188368).
- This matters for us because of how our Worker runs. It runs on a cron every minute (`server/wrangler.jsonc`, repo). Cron Triggers "run on underutilized machines" — [Cron Triggers](https://developers.cloudflare.com/workers/configuration/cron-triggers/). Placement "only affects the execution of fetch event handlers" — [Placement](https://developers.cloudflare.com/workers/configuration/placement/) (updated 2026-10-12). So a cron call can leave from any Cloudflare location.

**Stability (2024–2026)**
- Dec 2025: free-tier RPD for Flash was cut from 250 to **20**, reportedly 7 Dec 2025, with no announcement. This is from several third-party reports; I found no official notice — e.g. [DEV Community](https://dev.to/anna001/is-free-gemini-25-pro-api-fried-changes-to-the-free-quota-in-2025-200h).
- 16 Mar 2026: "revamped Usage Tiers" and spend caps.
- 18 Sep 2026: 2.5 models were limited to earlier users, and new projects were pointed to "3.5 Flash-Lite or 3.8 Flash". Both are from the official [changelog](https://ai.google.dev/gemini-api/docs/changelog) and [deprecations](https://ai.google.dev/gemini-api/docs/deprecations) (updated 2026-10-12).
- `gemini-3.1-flash-lite` shuts down **7 May 2027**. The listed replacement is `gemini-3.5-flash-lite` (deprecations page).
- Many preview models were shut down within months during 2026 (changelog).

**Paid price, for context only (not free)**
- 3.1 Flash-Lite costs $0.25 per M input and $1.50 per M output (pricing page).
- Option B: 127,500 input tokens × $0.25/M + 612,000 output tokens × $1.50/M ≈ $0.95 a day ≈ **$28.50 a month** (estimate). Batch prices are half, about $14 a month.

### Groq

**Limits** — [rate limits](https://console.groq.com/docs/rate-limits) (official, no date)
- The page's table has a "Free Plan Limits" tab, selected by default in the served HTML. It lists:
  - `openai/gpt-oss-120b`, `openai/gpt-oss-20b` and `qwen/qwen3.8-27b`: **30 RPM, 1K RPD, 8K TPM, 200K TPD** each.
- The same page also says "the limits shown below are the base limits for the Developer plan". **The page contradicts itself.** The console's Limits page is the authority.
- Limits apply per organization, not per key. "Cached tokens do not count towards your rate limits."
- `llama-3.3-70b-versatile` and `llama-3.1-8b-instant` are production models — [models](https://console.groq.com/docs/models) — but are **not in the limits table**. Their free limits are not confirmed.
- Preview models "should not be used in production environments".
- Moving to the paid Developer tier needs a card, US bank account or SEPA account — [billing FAQ](https://console.groq.com/docs/billing-faqs).

**Math**
- 200,000 TPD ÷ 4,350 tokens (Option B) ≈ **46 articles a day per model**.
- All three text models together give about 138 a day. That is short of 170.

**Terms** — [Services Agreement](https://console.groq.com/docs/legal/services-agreement) (Last Modified June 22, 2026)
- "Groq is not permitted to use Inputs or Outputs for training or fine-tuning any AI Model Services" without the customer's permission.
- "Certain Cloud Services … may be designated as fee-free."
- Services may be offered to End Users through Customer Applications. They are "not for consumer use" (meaning the customer must be a business or developer).
- Groq "may update the Cloud Services … including by adding or removing features".

**Region**
- No country list. Export-control clause only.
- A Groq staff member, on a forum, said 403 "Access denied" can come from Cloudflare rules that block sanctioned-country IP ranges "sometimes … a bit eager". Seen from Fly.io and Azure hosts — [Groq community](https://community.groq.com/t/getting-access-denied/886/2).
- Probe: `api.groq.com` is served by Cloudflare (`server: cloudflare`).

**Stability**
- On 24 Dec 2025 Nvidia took a non-exclusive licence to Groq's technology, and Groq's founder moved to Nvidia. GroqCloud continues as an independent company, which raised about $650M in June 2026 — third party, e.g. [Voiceflow](https://www.voiceflow.com/blog/groq).
- I found no dated official notice of free-limit changes. Third-party tables from earlier in 2026 list Llama 3.3 70B on the free plan, but today's table doesn't.

**Quality**
- In the North Small Translate paper (section 4), GPT-OSS 120B is clearly behind Gemma 4 31B in all six of our languages.

### Mistral (La Plateforme / Studio, "Experiment" plan = Free mode)

**Limits**
- Official docs give no numbers: "Free mode lets you create API keys and use included monthly usage within the limits shown on the Limits page" — [Usage and limits](https://docs.mistral.ai/admin/user-management-finops/tier) (no date).
- Help centre (12 Aug 2026): "Free mode (the default) has the lowest limits, intended for evaluation and prototyping" — [help article](https://help.mistral.ai/en/articles/698531-why-am-i-hitting-api-rate-limits-and-how-do-i-increase-them).
- 27 Jan 2026: "Free API usage remains available on the Experiment plan — ideal for testing and prototyping" — [Mistral Vibe 2.0 post](https://mistral.ai/news/mistral-vibe-2-0/).
- Third party: **1 request/second, 500,000 tokens/minute, 1,000,000,000 tokens/month per model**, phone verification required — [free-llm-api-resources mirror](https://mintlify.wiki/cheahjs/free-llm-api-resources/providers/free/mistral-plateforme) (no date).
- One tracker reports "2 RPM". **The numbers are not confirmed.**
- **Which models are free is not confirmed.** Aggregators say all models are free. Mistral's help page lists "frontier model access" as a paid benefit — summarised from search results.

**Math**
- 1 B tokens/month vs ~22–39 M needed is **2–4%** of the reported allowance.
- 1 request/second allows up to 86,400 requests a day.

**Terms**
- Commercial Terms of Service (effective 25 Sep 2026): Mistral "will not use Customer Data or Outputs to train" except where a product is opt-out by default and the customer has not opted out — [Commercial ToS](https://legal.mistral.ai/terms/commercial-terms-of-service/).
- Help centre, via search snippets: Experiment-plan API requests "may be used to train Mistral's models". There is an opt-out toggle under Admin Console → Privacy → "Anonymous improvement data". Help page 455206 returned 404 when fetched, so this is not read directly.
- I found **no clause that forbids production use** on the free plan. The only signals are the "evaluation and prototyping" wording above.
- Sanctioned countries are excluded (EU comprehensive sanctions, e.g. Cuba, Iran, North Korea, Syria). Kenya is not affected.

**Region and Cloudflare**
- Probe: `api.mistral.ai` is served by Cloudflare (cf-ray from colo NBO).
- Mistral is an EU (French) company.

**Quality**
- WMT25 human evaluation, "Mistral-Medium" (2025 version): en→uk 84.5, en→cs 80.4.
- North Small Translate paper, Mistral Medium 3.5: steady across all six languages, from 80.1 for cs to 87.9 for es.

### OpenRouter (`:free` models)

**Limits** — [limits](https://openrouter.ai/docs/api/reference/limits) (no date)
- 20 RPM.
- **50 RPD** if fewer than 10 credits have ever been bought; **1,000 RPD** once at least 10 have been bought ($10, one-time).
- "Cloudflare's DDoS protection will block requests that dramatically exceed reasonable usage."

**Models**
- Free models seen in OpenRouter's public models API on 2026-10-15 (probe, 17 in total), among them:
  - `google/gemma-4-31b-it:free` and `google/gemma-4-26b-a4b-it:free`.
  - `nvidia/nemotron-3-super-120b-a12b:free`, `nvidia/nemotron-3-ultra-550b-a55b:free` and `nvidia/nemotron-3.5-lightning:free`.
  - `thinkingmachines/inkling:free` and `inkling-small:free`.
  - `openrouter/free`, a router that picks a free model at random.
- The `google/gemma-4-31b-it:free` endpoint is served by provider **"Google AI Studio"** (probe of `/endpoints`). So Google's free-tier data terms probably apply. I could not confirm whether the EEA clause passes through OpenRouter.

**Terms** — [terms](https://openrouter.ai/terms) (Last Updated 31 Aug 2026)
- "OpenRouter may add or remove Models from the Service at any time."
- "Some Models may store or train on your Inputs."
- Reselling API access is barred. Use "for commercial, for-profit purposes" and incorporating the service "into your own products" are covered.
- VPNs and proxies may not be used to reach region-restricted models.
- Free and paid models have **separate** training-opt-in settings — [provider logging](https://openrouter.ai/docs/guides/privacy/provider-logging).

**Probe**
- `openrouter.ai` is served by Cloudflare.

### Z.ai (Zhipu), GLM-4.7-Flash

**Price and limits**
- GLM-4.7-Flash, GLM-4.5-Flash and GLM-4.6V-Flash cost **$0** for input, cached input and output — [pricing](https://docs.z.ai/guides/overview/pricing) (no date).
- GLM-4.7 page: "Lightweight, Completely Free". It lists "translation" as a use case — [GLM-4.7](https://docs.z.ai/guides/llm/glm-4.7).
- Concurrency: **1 concurrent request** on the free tier. This comes from third-party reports, e.g. [ToolNavs](https://toolnavs.com/en/article/1100-zai-released-glm-47-flash-weights-and-api-free-tier-1-concurrency-and-launched-f). The official rate-limit URL redirects to a console page I could not read. **Not confirmed.** I found no published daily cap.
- It is the **same model** our summarizer uses on Workers AI (`@cf/zai-org/glm-4.7-flash`). Summaries and translations could swap between the two providers with one prompt.

**Math (estimate)**
- 1,020 sequential requests at ~5–10 s each ≈ 1.4–2.8 hours of calls a day. That fits in 24 hours.

**Terms** — [Terms of Use](https://docs.z.ai/legal-agreement/terms-of-use) (Last Update 14 April 2026)
- The contracting entity is JINGSHENG HENGXING TECHNOLOGY PTE. LTD., under Singapore law.
- API terms grant a right to integrate the API into your applications and offer them to End Users.
- Z.ai "will not use End User Content to develop or improve Services" unless you agree. That clause is in square brackets, so it may be template text.
- Excluded regions: Iran, North Korea, Cuba, Crimea, Donetsk, Zaporizhzhia.

**Stability**
- The model was released around 19–20 Jan 2026 (third party). There is no SLA, and I found no history of the free tier.

**Quality**
- GLM-4.7-Flash itself is **not in any translation benchmark I found**.

### Cerebras
- Rate limits page: "Free Trial" with 5 RPM, 1M TPH and 1M TPD per model. Models are `gpt-oss-120b` and `qwen-3.8-27b` — [rate limits](https://inference-docs.cerebras.ai/support/rate-limits).
- New accounts get $5 in credits "after adding a verified payment method". The credits expire after 30 days, and without a payment method API access stays inactive.
- Pricing page: "Add a valid payment method to receive a one-time $5 promotional credit … expires 30 days after activation". It also says "For development, evaluation, and experimentation; not intended for production use" — [pricing](https://www.cerebras.ai/pricing).
- History: an open free tier (about 1M tokens a day) existed until mid-2026. The "Free Trial" wording was logged in Jul–Aug 2026, and the trial reportedly merged into a "Developer" tier on 5 Oct 2026 — third party, [UsagePricing](https://usagepricing.com/blueprint/activity/cerebras-2026-07-21-packaging).

### GitHub Models
- "As of July 30, 2026, GitHub Models has been fully retired." The playground, catalog, inference API and BYOK "are no longer available to any customer" — [GitHub Docs](https://docs.github.com/en/github-models/use-github-models/prototyping-with-ai-models).
- Changelog: retirement announced 1 July 2026, completed 30 July 2026 — [changelog](https://github.blog/changelog/2026-07-30-github-models-is-now-retired/).

### Cohere
- Trial keys: "limited to 1,000 API calls a month", and chat models get 20 requests a minute — [rate limits](https://docs.cohere.com/docs/rate-limits).
- "trial keys are rate limited and are not permitted to be used for production or commercial purposes" — [pricing](https://cohere.com/pricing).
- Command A Translate and the newer North Small Translate are strong translators (section 4). North Small Translate's open weights are for non-commercial use only — [Cohere docs](https://docs.cohere.com/docs/north-small-translate-1.0) (from search results).

### Hugging Face Inference Providers
- Monthly credits: Free users "None", PRO users $2.00. Free users can use Inference Providers only by buying credits — [pricing](https://huggingface.co/docs/inference-providers/pricing).
- Earlier, free users received a small monthly credit. I did not confirm when that changed.

### SambaNova
- The Free tier applies "when there is no payment method linked". Production and preview models (DeepSeek-V3.1, Llama-3.3-70B, gpt-oss-120b, DeepSeek-V3.2, gemma-4-31B-it) get **20 RPM, 20 RPD and 200,000 TPD** each.
- Preview models are "intended for evaluation purposes … should not be used in production" — [rate limits](https://docs.sambanova.ai/docs/en/models/rate-limits.md).

### DeepSeek
- The official pricing page lists no free tier. Fees come out of a "topped-up or granted balance" — [pricing](https://api-docs.deepseek.com/quick_start/pricing) (no date).
- deepseek-flash (V4.1-Flash) prices:
  - Off-peak: $0.15 per M input tokens (cache miss) and $0.60 per M output.
  - Peak: double. Peak hours are 01:00–04:00 and 06:00–10:00 UTC, Monday to Friday.
- Context, not free: Option B off-peak ≈ 0.1275 × 0.15 + 0.612 × 0.60 ≈ $0.39 a day ≈ $12 a month (estimate).

### NVIDIA (build.nvidia.com API catalog)
- Reported terms: about 1,000 credits at signup (up to 5,000 on request) and about 40 RPM. Use is "for prototyping, research, development and testing purposes only", and production needs NVIDIA AI Enterprise. Sources are an NVIDIA forum FAQ and staff replies, found through search. **I could not read the API Trial Terms text itself** — [NVIDIA NIM FAQ](https://forums.developer.nvidia.com/t/nvidia-nim-faq/300317).

### Other options I checked
- **OpenAI "complimentary tokens" for data sharing.** It gives 250K tokens a day on usage tiers 1–2 and 1M on higher tiers, on listed models, if you share inputs and outputs with OpenAI. It needs a **positive account balance**, and only some organizations are eligible. OpenAI promises 30 days' notice before ending it — [OpenAI help](https://help.openai.com/en/articles/10306912-sharing-feedback-evals-and-api-data-with-openai). That is from search snippets; the page returned 403 when fetched. It is not free in practice, because it needs a paid account.
- **Alibaba Cloud Model Studio (Qwen).** 1M tokens free per eligible model for **90 days** after activation, international (Singapore) deployment only. It is one-time, not ongoing — [billing](https://www.alibabacloud.com/help/en/model-studio/billing-for-model-studio).
- **Cloudflare AI Gateway** (not a model provider).
  - It is free on all plans and supports Google AI Studio, Groq, Mistral, OpenRouter, Cerebras, DeepSeek, Cohere, Hugging Face and Workers AI — [providers](https://developers.cloudflare.com/ai-gateway/usage/providers/) and [pricing](https://developers.cloudflare.com/ai-gateway/reference/pricing/) (updated 24 Sep 2026).
  - Workers Free accounts that created a gateway before 24 Sep 2026 get 100,000 logs in total.
  - It is useful for swapping providers and adding fallbacks without code changes.

---

## 4. Translation quality evidence

### WMT25 General MT, human evaluation
- Source: [Findings of WMT25](https://aclanthology.org/2025.wmt-1.22), section 7.4. It used professional annotators with the ESA protocol on a 0–100 scale. The test sets were deliberately hard (difficulty sampling). These are 2025 models.

| System | en→uk | en→cs | en→ru |
|---|---|---|---|
| Gemini-2.5-Pro | **90.3** (rank 1–3) | **88.7** (1st) | **83.4** (1st) |
| GPT-4.1 | 87.9 | 80.8 | 76.2 |
| DeepSeek-V3 | 85.8 | 85.1 | 73.6 |
| Claude-4 | 85.6 | 79.6 | 75.9 |
| Mistral-Medium | 84.5 | 80.4 | not in the table |
| Llama-4-Maverick | 86.2 | not in the table | not in the table |
| Gemma-3-27B | not in the table | 75.6 | 61.7 |
| Human reference | 87.3 | 84.5 | 70.5 |

- What it shows: Gemini's big model led, and small models fell well behind in Czech and Russian. **No Flash-Lite, gpt-oss, GLM-4.7-Flash or Gemma 4 was evaluated.**

### North Small Translate paper (Cohere, arXiv 2609.13916, 12 Sep 2026)
- Source: [arXiv](https://arxiv.org/abs/2609.13916), Table 6.
- Setup: the WMT26 test set, scored by an LLM judge (GEMBA-ESA, 0–100), in the same zero-shot setup for every system.
- Caveats: **this is a vendor paper**, and the metric is automatic, not human. Its "Portuguese" is **European** Portuguese; Brazilian Portuguese is not in the set.

| System | es | pt-PT | pl | cs | uk | ru |
|---|---|---|---|---|---|---|
| Gemma 4 31B (free via OpenRouter; free tier on the Gemini API) | **90.6** | **87.0** | **88.9** | 75.5 | **87.7** | **89.9** |
| Mistral Medium 3.5 | 87.9 | 84.3 | 81.0 | 80.1 | 81.8 | 82.8 |
| GPT-OSS 120B (Groq, Cerebras) | 82.3 | 78.8 | 74.9 | 71.6 | 72.5 | 74.6 |
| Nemotron 3 Ultra 550B (free via OpenRouter) | 88.1 | 85.4 | 67.9 | 65.1 | 65.7 | 77.5 |
| Qwen 3.6 27B | 81.6 | 83.2 | 77.8 | 70.0 | 69.7 | 85.3 |
| GLM 5.2 (the large model, not GLM-4.7-Flash) | 81.7 | 69.5 | 73.4 | 86.3 | 83.8 | 88.4 |
| DeepL NextGen | 88.4 | 87.2 | 82.1 | 85.3 | 84.1 | 84.3 |
| Google Translate | 76.5 | 51.6 | 68.4 | 65.4 | 65.5 | 69.6 |

- Note: Gemma 4 31B is strong in five of our six languages but **weaker in Czech** (75.5).

### WMT24++ (Google and Unbabel, Feb 2025)
- Frontier LLMs (o1, Gemini-1.5 Pro, Claude 3.5) were "ranked the highest for every language" across 55 languages, ahead of standard MT providers. This is by automatic metrics, and the authors say a human evaluation is still needed — [arXiv 2502.12404](https://arxiv.org/abs/2502.12404).

### Gaps
- I found **no published translation benchmark for Gemini 3.1 or 3.5 Flash-Lite**, nor for GLM-4.7-Flash. Their quality in uk, cs, pl, es, pt and ru is unmeasured.
- WMT26 official human results are not out yet. The conference is late Oct / early Nov 2026 — [WMT26](https://www2.statmt.org/wmt26/translation-task.html).

---

## 5. Non-LLM translation APIs, and how far their free quotas go

Full load = 1,530,000 characters a day (all six languages), or 45.9 M a month. One language = 255,000 a day, or 7.65 M a month.

| API | Free quota (source, date) | Days of full load (6 languages) | Articles a day in all 6 for a month | Notes |
|---|---|---|---|---|
| **DeepL API**, new accounts | "Developer" plan: **1,000,000 characters one-time, not reset**. DeepL's support page says the API Free plan "can no longer be purchased" (search snippet; the page returned 403 to me). Third party, updated 23 Sep 2026: API Free/Pro were replaced by Developer and Growth — [flexprice](https://flexprice.io/pricing-index/deepl-translator) | 1,000,000 ÷ 1,530,000 = **0.65 days**, once | 1,000,000 ÷ (9,000 × 30) = 3.7, for one month only | Growth plan: €29.75 a month, €22 per extra M characters (third party) |
| DeepL API Free (legacy accounts only) | 500,000 characters a month (DeepL support, via search) | 500,000 ÷ 1,530,000 = **0.33 days** a month | 500,000 ÷ 270,000 = **1.85** | A card was needed even for Free (third party). Kenya support not confirmed |
| **Google Cloud Translation** (NMT) | "First 500,000 characters per month Free (applied as $10 credit every month)", then $20 per M — [pricing](https://cloud.google.com/translate/pricing) (probe of page) | **0.33 days** a month | **1.85** | Needs a billing account. Full load after the credit ≈ 45.4 M × $20 ≈ $908 a month. Translation LLM: $10 per M input + $10 per M output |
| **Azure Translator F0** | "2 million characters … free per month" — [pricing](https://azure.microsoft.com/en-us/pricing/details/translator/). Rate limit 2 M characters an hour — [service limits](https://learn.microsoft.com/en-us/azure/ai-services/translator/service-limits) (2026-08-11) | 2,000,000 ÷ 1,530,000 = **1.3 days** a month | 2,000,000 ÷ 270,000 = **7.4** | S1 price did not render on the page today, so not confirmed. An Azure account (card) is needed |
| Amazon Translate | 2 M characters a month **for 12 months** — [pricing](https://aws.amazon.com/translate/pricing/) | 1.3 days a month | 7.4 | $15 per M after. Not ongoing |
| **LibreTranslate** | Hosted API: **no free plan** (Pro $29 a month, Business $58 a month) — [portal](https://portal.libretranslate.com/). Self-hosting is open source but needs a server; it cannot run inside a Worker | n/a | n/a | No benchmark found for our languages |
| MyMemory | 5,000 characters a day anonymous; **50,000 a day** with an email (`de=`) — [usage limits](https://mymemory.translated.net/doc/usagelimits.php) | 50,000 ÷ 1,530,000 = 3% of a day, daily | 50,000 ÷ 9,000 = **5.5** | Mix of translation memory and machine translation. Commercial terms not checked |

What one language covers (same quotas): DeepL legacy 500,000 ÷ (1,500 × 30) = 11 articles a day. Azure F0: 2,000,000 ÷ 45,000 = 44 articles a day. Neither comes close to 170.

What if we translate only the headline and the short summary (290 characters)? One language for a month is 170 × 290 × 30 = 1,479,000 characters. That fits Azure F0 (2 M) for **one** language only.

---

## 6. Calling from our Worker: facts that apply to every provider

- Our Worker runs from a cron every minute (`"crons": ["* * * * *"]`, `server/wrangler.jsonc`, repo).
  - Cron Triggers "run on underutilized machines" — [docs](https://developers.cloudflare.com/workers/configuration/cron-triggers/).
  - Placement (Smart Placement or a region hint such as `"placement": { "region": "aws:us-east-1" }`) "only affects the execution of fetch event handlers" — [docs](https://developers.cloudflare.com/workers/configuration/placement/).
  - **Not confirmed:** whether a cron job that calls a placed Worker through a service binding gets that placement.
- Region checks are the risk. Gemini rejects unsupported locations (above). Groq's Cloudflare rules sometimes block hosting IPs (above). OpenAI flagged a Worker for traffic from China, Hong Kong and Macau, per a third-party forum thread.
- Probe from the Kenyan IP: `api.groq.com`, `api.mistral.ai`, `openrouter.ai` and `api.cerebras.ai` are behind Cloudflare. `generativelanguage.googleapis.com` is Google's own front end.
- The one check that settles reachability: deploy one test request per provider from the Worker's scheduled handler, and log the status code and `cf-placement` / colo.

---

## 7. Could not confirm

- Gemini free TPM for Flash-Lite. The Gemma 4 free RPD (1,500 is from a single source).
- Whether Gemini's EEA "Paid Services only" clause covers an app whose server calls the API and stores the result. This is my reading of the definition of "API Clients"; it needs a legal read or Google's confirmation.
- Groq: whether the published table is the Free or the Developer plan (the page contradicts itself), and the free limits for the Llama models.
- Mistral: the free-mode numbers (official docs show them only in the console), which models the free plan includes, and whether a Kenyan phone number works for verification.
- Z.ai: the 1-concurrency limit, any daily cap, and the quality of GLM-4.7-Flash in our languages.
- OpenRouter: whether Google's EEA clause and data terms flow through to us on `gemma-4-31b-it:free`.
- DeepL: the exact date the API Free plan closed, and whether Kenya is a supported country for API signup.
- Azure Translator S1 price (did not render).
- Quality of Gemini 3.x Flash-Lite in any benchmark.

---

## 8. Ranked recommendation (top 3)

Facts above, my judgement here. These are free options for a free public app with EEA users, at ~170–1,020 requests a day.

1. **Mistral, Experiment (Free) plan**
   - It is the only free option whose published volume (third party: 1 B tokens a month per model, 1 request a second) covers even Option A with a wide margin.
   - It is an EU company, its API sits behind Cloudflare, and no card is needed.
   - Mistral Medium was steady across all six languages, including Czech: WMT25 human en→uk 84.5 and en→cs 80.4; Cohere's WMT26 table 80–88.
   - Caveats:
     - Mistral describes free mode as "intended for evaluation and prototyping". That is not a ban, but it is a signal.
     - Training on our data is on by default (opt-out toggle exists; our data is public text).
     - The free plan's models and numbers must be checked in the console after signup.
2. **Z.ai GLM-4.7-Flash (free API)**
   - It is completely free, with no daily cap found, and the terms allow apps for end users.
   - It is the **same model** as our Workers AI summarizer. That makes "swap which provider does summaries vs translations" a one-line change, and it could take the summaries off Workers AI's 10,000-Neuron limit, which 170 articles already reach.
   - Caveats:
     - The free tier reportedly allows 1 request at a time. That is fine for a cron that runs every minute.
     - Its quality in uk, cs, pl, es, pt and ru is unmeasured.
     - It is a small MoE model (30B total, 3B active).
     - Smaller provider, no SLA.
3. **OpenRouter free models (`google/gemma-4-31b-it:free`, with Nemotron or Inkling as automatic fallbacks)**
   - It has the best measured quality of any free option: Gemma 4 31B scored 87–91 in es, pt-PT, pl, uk and ru in Cohere's WMT26 table. Czech is weaker (75.5).
   - The terms allow use inside our own product, and the `models` array gives fallback.
   - Caveats:
     - It needs a **one-time $10 credit purchase** to get 1,000 requests a day. 50 a day is not enough.
     - The free model list changes without notice.
     - The Gemma endpoint is served by Google AI Studio, so Google's free-tier data use, and possibly its EEA clause, probably apply.

**Not recommended:**
- **Gemini API free tier.** It has strong quality pedigree, but its terms require paid services for apps available to EEA, Swiss or UK users. Google also cut the Flash free limit (250 to 20 requests a day, Dec 2025, third-party reports), closed the 2.5 models to new projects (Sep 2026), and no longer publishes the free numbers.
- **Groq free.** 200K tokens a day per model is about 46 articles in all six languages. It is useful only as overflow or fallback.
- **Cerebras, GitHub Models, Cohere, Hugging Face, SambaNova, NVIDIA.** These are retired, card-gated, too small, or explicitly non-production.
- **Non-LLM APIs.** The biggest ongoing free quota, Azure's 2 M characters a month, covers about 1.3 days of the full load.

**The one action that settles quality:** translate the same 20 real summaries with each of the top three, and have native speakers score the Ukrainian, Czech and Polish. Those are the languages where the published scores differ most.
