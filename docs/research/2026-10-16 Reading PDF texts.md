# Reading PDF texts on the server (#82)

Researched 16 Oct 2026; nothing deployed or called live. Labels: **measured** (locally, Apple M4 Pro), **doc**, **estimate**.

## Recommendation

**In short (Yurii):** use Cloudflare's built-in PDF converter, Workers AI `toMarkdown`. For PDFs it should cost nothing, and it fits the free plan if we skip files over 1 MB. Our own PDF-reading code would be too slow for the 10 ms limit. Start with South Africa: about 2 notices a day, and 17 of 19 samples are under 400 KB (measured). One test run will confirm it is free before we build. Brazil stays as is, because its site asks bots not to download PDFs.

**Technical (Roman):**
- `env.AI.toMarkdown` with `conversionOptions: { pdf: { metadata: false, images: { convert: false } }, output: { format: "text" } }`. `images` is undocumented (workers-types 5.20261014.1, workerd source); without it, embedded images might go to image models that cost Neurons.
- 0 Neurons expected for PDFs, untested: the doc says "free for most format conversions" and names image conversion as one that uses models. It doesn't mention PDFs. No size, page or rate limit is published.
- The binding base64-encodes the file and builds one JSON string in our isolate: ~1.15 ms per MB (measured, Node). So ~0.3 ms for the median 131 KB ZA PDF and 6–9 ms for the 3.7 MB one (estimate; production 1.5–2× slower). Hence the 1 MB cap.
- Text comes back as-is (tagged PDFs, 5 of 19 ZA samples, as Markdown); no OCR (estimate).

## Options compared

| Option | Cost a day | Free-plan limits | CPU in our Worker | Quality |
|---|---|---|---|---|
| **`toMarkdown`** | 0 Neurons expected (untested) | none published; 1 subrequest | ~1.15 ms per MB (measured) | text layer, no OCR |
| PDFium WASM | 0 | 4.9 MB bundle, under 64 MiB | 1–5 ms a page warm, up to 13 ms; +30 ms per new isolate (measured) | 0.99–1.00 word recall vs poppler |
| pdf.js / unpdf | 0 | none | 4–43 ms for 2 pages, +56 ms cold (measured) | 0.92–1.00; does not fit |
| Browser Run | 0 within 10 browser-min | 1 request per 10 s; PDF reading undocumented | none | unknown; ≤ ~40–120 PDFs a day (estimate) |
| GitHub Actions + poppler/tesseract | 0 (public repo) | schedule ≥ 5 min, can lag, off after 60 idle days | none | best; only tested route with OCR |

Ruled out: Containers (paid only), tesseract.js (0.5–0.7 s CPU a page), mupdf (AGPL, fails to start in workerd), pdf-lib (no text extraction).

## How it fits the fetcher

- **Step:** `readItemPage`. When a ZA notice page links one PDF (19 of 19 did) or the item URL is a PDF (India): check robots.txt, download with our user agent, convert, and keep the longer text. A per-source config field turns it on. No new cron is needed (`api` has 4 of the account's 5).
- **Before downloading:** the ZA page names the size ("55543gon8021.pdf 112.77 KB"). Skip files over 1 MB, and check `Content-Length` too.
- **Text kept:** first 8,000 characters, gazette footer removed. The decision is on pages 1–2 (median 1,899 characters, measured); long files are annexes.
- **Budget per run:** one of `pagesPerRun: 2`; 2–3 of the 40 requests; ~2 ms CPU at the 1 MB cap (estimate); memory ~5× the file.
- **Order:** the text is stored before summarizing, so the one-AI-call rule still holds.
- **AI cost:** +4–11 Neurons per PDF article (estimate). At 2–5 a day that is under 1% of the free 10,000.
- **Tests:** mock `env.AI.toMarkdown`; local calls use the real service (doc).

## What it needs from us

- No new account, key or resource: the `AI` binding is in `server/wrangler.jsonc`.
- **One test** on a preview Worker: convert the 19 ZA samples, read CPU (Workers Logs) and Neurons (`aiInferenceAdaptiveGroups`, 15 Oct usage note), and compare the text with `pdftotext`.
- `docs/decisions.md`: the PDF step, its caps, and that a conversion without a model is not an "AI call".

## Open questions

1. **Brazil (human decision):** camara.leg.br robots.txt has `Disallow: /*.pdf` for all user agents. Our full-text URL (`prop_mostrarintegra?codteor=…`) has no ".pdf" in it but serves the PDF, and it answered our user agent with 429 three times. Keep ementa summaries, or ask the Chamber's open-data team.
2. **Scanned PDFs:** 2 of 19 ZA notices are image-only, and both are in the feed (`is_news = 1`). Title-only for now. OCR on GitHub Actions would mean a second runtime (decision needed).
3. Does the binding call count toward the 50 subrequests or the 1,000 internal? We assume 50.
4. Does `toMarkdown` mark page breaks, so we could cut by pages?
5. India: the "Statement of Objects and Reasons" comes after the clauses (pages 3/6, 8/18, 16/24). It starts past character 8,000 in 2 of 3 samples, so a first-8,000 cut usually misses it.

**Disclosure:** while measuring, a few Brazil PDFs were downloaded despite that rule, one check after the 429 used curl's default user agent, and one dof.gob.mx page that robots.txt disallows was fetched (copy deleted). None is in the repo.

## Sources

- https://developers.cloudflare.com/workers-ai/features/markdown-conversion/ (and its subpages)
- https://github.com/cloudflare/workerd/blob/main/src/cloudflare/internal/to-markdown-api.ts
- https://developers.cloudflare.com/workers-ai/platform/pricing/ https://developers.cloudflare.com/workers-ai/platform/limits/ https://developers.cloudflare.com/workers/local-development/bindings-per-env/
- https://developers.cloudflare.com/workers/platform/limits/ https://developers.cloudflare.com/changelog/post/2026-09-04-increased-worker-size-limit/
- https://developers.cloudflare.com/browser-run/limits/ https://developers.cloudflare.com/containers/platform/pricing/
- https://docs.github.com/en/billing/concepts/product-billing/github-actions https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows
- https://github.com/Hopding/pdf-lib#limitations https://www.camara.leg.br/robots.txt https://www.gov.za/robots.txt
- `docs/research/2026-10-15 Cloudflare usage and free limits.md`

Fact-check: 7 corrections: (1) the doc says "most formats" are free, not "only images use models"; (2) PDFium is 1–5 ms a page (max 13, re-run on 19 ZA files), not 1–2; (3) unpdf recall starts at 0.92, not 0.98; (4) India's SOR is mid-document, and within 8,000 characters in 1 of 3; (5) PDFium is 4.9 MB, not 4.8; (6) the 3.7 MB file is 6–9 ms, not 7–9; (7) the cron limit is per account.