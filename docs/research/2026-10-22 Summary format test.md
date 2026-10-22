# Summary format test: useful news with a hook headline (#133)

Roman, 21 and 22 October 2026, with Claude Code. Every run sent real articles from the live database to Gemma 4 26B (`@cf/google/gemma-4-26b-a4b-it`, the production model, temperature 0.2, thinking off, a JSON schema) through a local test Worker that imports the server's own prompt and checks. Nothing was written to the database.

## Why

A summary retold the article: the name of the act, who submitted it, the background, then the facts in order. Roman wants news a reader can use: a headline that makes them want to read, then what changes for them, what to do and what is still unknown, in about a minute of reading, with nothing that merely repeats the article.

## What a summary cost before

Measured on 10 articles fetched on 20 October, with the prompt from #99:

| Per call | Value |
| --- | --- |
| Input tokens | 2,407 on average, about 1,870 of them the instructions (the articles average 1,300 characters) |
| Output tokens | 555 on average; 1 of the 10 ran to the 2,000-token limit (Gemma repeated itself) |
| Neurons | 36.2 |

On 20 October 87 articles took 105 calls (18 answers were unusable and asked again): about 3,900 of the 10,000 free Neurons a day. The largest part of the instructions was "what it means" (`impact`, 31%), which the app does not show.

## The rounds

1. **The shortest prompt** (about 130 tokens: the fields and two rules). On a Polish bill: 707 input tokens instead of 2,361, 12.5 Neurons instead of 35.5, facts and numbers right, but the summary was one block retelling 1,100 of the article's 1,800 characters, and the headline said nothing about who it changes things for. Not good enough.
2. **Formats, written by hand on the same Polish bill** (advice, benefit, risk, who it concerns, a timeline, analysis). Roman chose one: a hook headline, then who it is for and what changes, "What to do:", "What we do not know:", 600 to 900 characters.
3. **Three headline options per article** (question, consequence, deadline) on 3 articles: useful summaries, but on a decision about forest fires the model invented advice for residents, and 2 summaries ran over 900 characters.
4. **The model picks the headline kind** (10 articles): it named `consequence` 8 times. 6 of 10 summaries used a ruled-out word ("aims to" 4 times, "could", "might"), 2 ran over 900 characters, and the status stayed right in 9 of 10 headlines ("would", "plans to"). No invented advice on the fires any more.
5. **Why always `consequence`** (the same 10 articles, three variants):

   | Variant | Kinds named |
   | --- | --- |
   | Headline first, its kind after | consequence 5, plain 3, question 2 |
   | The kinds listed in reverse order | consequence 8, contrast 1, plain 1 |
   | One headline of each kind, then the best | consequence 6, deadline 3, plain 1 |

   A consequence fits every decision; a deadline needs a date and a contrast two numbers, and written without them they came out empty ("No deadline set: EU investigation into Booking.com is now underway", "1,056 responses reviewed to decide the future of CE mark recognition"). The model also named its kind before writing the headline, and its label often did not match what it wrote (a question labelled `consequence`). The order of the list made no difference.
6. **Roman's decision:** the code picks the kind at random, and the deadline kind goes. With the kind picked from the article id among `question` and `consequence`, plus `contrast` when the text gives two amounts, the model wrote the kind it was given in 9 of 9 news articles and switched to a plain headline for the one that was not news. 2 of 10 summaries had a ruled-out word, 2 headlines ran over 80 characters (85 and 81) and 1 summary over 900 (977). 22.8 Neurons.
7. **The server's prompt.** For now it keeps the 14 topics (the IPTC categories come with #127 once #128 is merged) and adds the feed card's `shortSummary`. A first version with the decision types spelled out and the older rules (about 500 tokens more) made Gemma less obedient: 6 of 9 news answers would have been asked again (4 over the length limits, 3 with a ruled-out word, 1 copy; some had two of these). With the decision types back in one line, the length asked for in words (100 to 130 words, which the model keeps better than characters), the hard limits at 90 and 1,000 characters (the prompt still asks for 80 and 600 to 900), and the copy check at 12 words in a row (8 caught names such as "Misconduct in Public Office"), the final run gave:

   | | Result |
   | --- | --- |
   | News recognised | 9 of 9, and the ceremony in Germany marked not news |
   | Headline kind | the one given in 8 of 9; Booking.com got a plain one |
   | Asked again | 2 of 9, both for "aims to"; none over the limits, none copied |
   | Numbers not in the article | none |
   | Cost | 2,109 input and 248 output tokens, 25.4 Neurons on average (36.2 before) |

   Two examples: "Beginning teachers: 3% raise planned instead of 0.68%" (contrast, Poland's Teacher's Charter bill); "Want to skip the annual 800+ application? The government plans to automate renewals" (question, Poland's child benefit bill).

## The articles

| Id | Country | Original title |
| --- | --- | --- |
| 01M5EVFDDZ392PY7MZPFCSN9WN | GB | Restrictions on the performance of high-risk cosmetic and wellbeing procedures |
| 01M5CQ1FXY454K6HJ3012DJA1Z | PL | Projekt ustawy o zmianie ustawy - Karta Nauczyciela |
| 01M5BV089JB11WMHRCJP83JKRV | ID | Presiden Prabowo Instruksikan Penanganan Karhutla Lebih Masif dan Terpadu |
| 01M5FJTG39MA1553X7WDP4FH2K | GB | Hillsborough Law Bill |
| 01M5EZDRCXP91D0Q27WBT90QRQ | EU | Commission to investigate how Booking.com combats scams and fraud |
| 01M5EVY29B7GRHHNARDT9GXNTX | CA | C-40 (45-1) - Strengthening Canada's Defence Sector Act |
| 01M5ERQJ7EXE991T3PJWS3R9VF | GB | Medical devices regulations: targeted consultation on the indefinite recognition of CE marked devices |
| 01M5CRBKRVZ4E74CFYD3BGJSPZ | PL | Projekt ustawy o zmianie ustawy o pomocy państwa w wychowywaniu dzieci |
| 01M5A5AQX9QRPDMJECTBZ8CRR5 | CZ | Výsledky jednání vlády 19. října 2026 |
| 01M5D9R8H0A3800YH3ZCDFFAWG | DE | Eine deutsch-türkische Erfolgsgeschichte |

## Open points

- Gemma still writes "aims to" in about 1 summary in 5, despite the list; it costs a retry, and the last try is stored with a warning.
- A page with several decisions (Czechia's government meeting) gets a summary of one of them: splitting meeting results into decisions is its own task (#115).
- Which headline kind readers open most is for the app's analytics to show (`headlineType`).
