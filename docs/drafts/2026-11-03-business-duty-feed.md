# Backlog: business-duty feed ("what this decision means for your business")

Draft for a GitHub issue with the label `backlog`. Not posted yet; written locally on 3 Nov 2026. Research and data
are in `~/Documents/independence/research/2026-11-03-business-duty-proof.md` and
`~/Documents/independence/research/data/duty-feed-2026-11-03/` (decisions, labels, script).

## The idea

Some readers run a business. For them, a decision matters only if it changes something for their type of business
in their country. Each such decision should tell them three things: who must act, what they must do or what
changes, and from when. They pick their business type and country, and get only those alerts.

Later, the same data can be served to other companies' software (invoicing, payroll, shop software) through an API
with keys.

## What the database already proves (read-only check of the live D1, 3 Nov 2026)

- 889 decisions with a summary, 7 Oct – 3 Nov (Wikipedia events and "not news" items left out).
- **462 of 889 (52%) change a rule for at least one business type.** That's about 20 a day.
- Top business types by number of decisions (and how many countries each appears in):

| Business type | Decisions | Countries |
|---|---|---|
| Energy and fuel | 71 | 12 + EU |
| Small firms in general (tax, reporting) | 55 | 14 |
| Banks, lenders, insurers | 50 | 13 + EU |
| Transport and logistics | 43 | 14 |
| Importers, exporters, factories | 40 | 12 + EU |
| Farms and food producers | 40 | 13 + EU |
| Tech platforms and software | 33 | 10 + EU |
| Construction, property, landlords | 30 | 13 |
| Every employer | 23 | 7 |
| Healthcare and pharma | 23 | 10 |

- By country: the UK has the most business decisions (106 of 140) but most are plans. Argentina (61 of 62 in force)
  and Mexico (41 of 41 in force) have the most binding ones.
- The ranking follows our sources: France, Spain and Italy have only 3–6 decisions each.

## Two worked examples (demo pages)

- **Petrol station owner, Campeche, Mexico:** 11 decisions in 3 weeks. 6 change the pump price: weekly IEPS fuel-tax
  decrees, plus separate amounts for the Guatemala-border zone. The decree text carries the rates, so the alerts work
  today. **Bug found:** the two decrees of 16 Oct (codigo 5801457 and 5801459) were marked "not news", so readers
  never saw them. https://claude.ai/artifact/HJQZ6F47B5wHzjWon9791w
- **Online clothing shop, Poland (sp. z o.o.):** 8 decisions matched a small company by title. After reading the full
  acts, 4 really matter:
  - consumer and greenwashing rules from 27 Sep 2027 (Dz.U. 2026/1353);
  - cash-paid costs not deductible from 1 Jan 2027 (2026/1371);
  - KSeF fines delayed to end 2027 (bill);
  - shareholder meetings and proxies by e-mail from 3 Dec 2026 (2026/1440).
  https://claude.ai/artifact/7spRpFuAPjwbpBLioSDY6S

## The gap this exposed

**The app doesn't read PDF laws.** For Polish Journal of Laws items, `articles.text` holds only about 200–255
characters: the title, keywords and the entry-into-force date. The summary therefore says "what we do not know: the
specific changes". The act itself (e.g. `https://api.sejm.gov.pl/eli/acts/DU/2026/1371/text.pdf`) is short and
readable: 3–24 thousand characters for these acts. `docs/plan.md` already lists PDF-only texts as a later step. This
feature needs it first.

## Steps (proposed)

1. **Read the full text of PDF acts.** Start with the Polish Journal of Laws, using the Sejm ELI API `text.pdf`.
   Other journals come later.
2. **Pick the core business types.** Start from the 10 above, and check them against our own data for a few more
   weeks.
3. **Add a "business duty" field in the existing summary call.** It holds 0–3 business types, each with who, what
   changes, and from when, quoted from the text. It stays empty when nothing changes for a business. The one-call rule
   stands.
4. **Fix the "not news" filter for recurring rate decrees,** like Mexico's weekly fuel decrees.
5. **Later:** a business-type filter in the app, then an API with keys.

## Open questions

- Would owners (or their software makers) pay for this? Not checked. Talk to a few real owners first.
- Which countries first: the ones where we already read the official journal (PL, MX, AR, BR), or the ones with the
  most readers?

## Related

#126 (audiences) was closed as covered by #133 and #127. That one was about readers in the app; this one is about
businesses, and later a feed for other companies' software.
