// The answer check for Spanish and German (#46): they use the English letters,
// so the check counts function words (src/translator/words.ts) instead.
import { describe, expect, it } from "vitest";
import { LANGUAGES } from "../src/translator";
import { OWN_WORDS_FROM, systemPrompt, toTranslation } from "../src/translator/prompt";
import { ENGLISH as ENGLISH_WORDS, GERMAN, SPANISH } from "../src/translator/words";
import { ENGLISH, TRANSLATED } from "./helpers";

type Latin = "es" | "de";

const check = (reply: Record<string, unknown>, lang: Latin, english = ENGLISH) => toTranslation(reply, english, LANGUAGES[lang]);

describe("Spanish and German answers", () => {
  it.each([["es"], ["de"]] as [Latin][])("accepts a good %s answer", (lang) => {
    expect(check(TRANSLATED[lang], lang)).toEqual({ translation: { ...TRANSLATED[lang], summary: TRANSLATED[lang].summary.replace("\n\n", "\n") } });
  });

  it("asks for the language's number format", () => {
    expect(systemPrompt(LANGUAGES.es)).toContain("from English into Spanish");
    expect(systemPrompt(LANGUAGES.de)).toContain("written the German way (1.250.000; 3,5 %)");
    expect(systemPrompt(LANGUAGES.uk)).toContain("(1 250 000; 3,5 %)");
  });

  it("accepts English names, quoted titles and links kept in a translation", () => {
    const english = {
      headline: "The Bank of England and the Department for Education agree on 2027 plan",
      shortSummary: "The Bank of England and the Department for Education agreed on a plan for 2027 with Die Linke.",
      summary: "The plan is in the 'Every child achieving and thriving' white paper.\nDetails: www.gov.uk/government/consultations/school-reforms.",
    };
    const es = {
      headline: "El Bank of England y el Department for Education acuerdan un plan para 2027",
      shortSummary: "El Bank of England y el Department for Education acordaron con Die Linke un plan para 2027.",
      summary: "El plan figura en el libro blanco «Every child achieving and thriving».\nDetalles: www.gov.uk/government/consultations/school-reforms.",
    };
    const de = {
      headline: "Bank of England und Department for Education einigen sich auf Plan für 2027",
      shortSummary: "Die Bank of England und das Department for Education haben sich mit dem Ministerio de Educación auf einen Plan für 2027 geeinigt.",
      summary: "Der Plan steht im Weißbuch „Every child achieving and thriving“.\nDetails: www.gov.uk/government/consultations/school-reforms.",
    };
    expect(check(es, "es", english)).toEqual({ translation: es });
    expect(check(de, "de", { ...english, shortSummary: english.shortSummary.replace("Die Linke", "Spain's education ministry") })).toEqual({ translation: de });
  });

  it("does not count English function words inside a name, which would outnumber the German ones", () => {
    const english = { ...ENGLISH, shortSummary: "According to the Department of Health and Social Care, costs rise in 2027." };
    const de = { ...TRANSLATED.de, shortSummary: "Laut Department of Health and Social Care steigen die Kosten 2027." };
    expect(check(de, "de", english)).toHaveProperty("translation");
    // The same words outside a name are English.
    const mixed = { ...de, shortSummary: "Laut Department steigen die Kosten 2027, of health and social care." };
    expect(check(mixed, "de", english)).toMatchObject({ problems: ["shortSummary is not in German"] });
  });

  it.each([
    ["the English unchanged", "es", { headline: ENGLISH.headline }, "headline is not in Spanish"],
    ["the English unchanged in title case", "de", { headline: "Germany's Cabinet Approves The 2027 Draft Budget" }, "headline is not in German"],
    // No function word of any of the three, and under 8 words: only the comparison with the English finds it.
    [
      "a short English field without function words, unchanged",
      "es",
      { headline: "Germany's Cabinet Approves Draft Budget 2027" },
      "headline is not in Spanish",
      { ...ENGLISH, headline: "Germany's cabinet approves draft budget 2027" },
    ],
    ["an English sentence in a field", "es", { shortSummary: "El Consejo de Ministros aprobó el presupuesto para 2027. The Bundestag now debates it and will vote on it." }, "shortSummary is not in Spanish"],
    ["an English paragraph", "de", { summary: "Das Bundeskabinett hat den Haushaltsentwurf für 2027 gebilligt.\n\nThe Bundestag now debates it in the coming weeks." }, "summary is not in German"],
    ["a German answer for Spanish", "es", TRANSLATED.de, "headline is not in Spanish"],
    ["a Spanish answer for German", "de", TRANSLATED.es, "headline is not in German"],
    ["a Spanish sentence that starts with its article", "de", { headline: "Los ministros aprueban el presupuesto" }, "headline is not in German"],
    ["an English sentence that starts with The before a name", "es", { headline: "The Commission backs the plan" }, "headline is not in Spanish"],
    ["one German field in a Spanish answer", "es", { shortSummary: TRANSLATED.de.shortSummary }, "shortSummary is not in Spanish"],
    [
      "a long field without one of its own function words",
      "es",
      { shortSummary: "Federal Cabinet Approved Budget Draft 2027 Today, Parliament Debates Next Week" },
      "shortSummary is not in Spanish",
    ],
  ] as [string, Latin, Record<string, string>, string, typeof ENGLISH?][])("rejects %s", (_, lang, overrides, problem, english) => {
    const result = check({ ...TRANSLATED[lang], ...overrides }, lang, english);
    expect(result).toMatchObject({ problems: expect.arrayContaining([expect.stringContaining(problem)]) });
  });

  it.each([
    // Name particles of the other language, also at the start of the sentence.
    ["es", "Ursula von der Leyen celebró el acuerdo"],
    ["es", "Ursula von der Leyen visitó Kiev el lunes"],
    ["es", "Von der Leyen visita Kiev"],
    ["de", "Die Sindicatura General de la Nación billigte Leitlinien"],
    ["de", "Der Consejo de la Judicatura Federal tagte"],
    ["de", "Los Angeles: Präsident entsendet Nationalgarde"],
    ["de", "El Salvador senkt Steuern"],
    ["de", "Las Palmas erweitert Hafen"],
    // Acronyms that spell an English or Spanish function word.
    ["de", "IT-Sicherheitsgesetz verabschiedet"],
    ["de", "WHO erklärt Mpox-Notstand"],
    ["de", "UN warnt: Hungersnot droht"],
    // Words of its own that the other lists have: German "los", "her" and the noun "Not", Spanish "bis".
    ["de", "Impfkampagne geht los"],
    ["de", "Mauerfall: 35 Jahre her"],
    ["de", "In Not geratene Firmen erhalten Hilfe"],
    ["es", "Artículo bis reformado"],
  ] as [Latin, string][])("accepts the %s headline %j: names, acronyms and its own words do not count as foreign", (lang, headline) => {
    const english = { ...ENGLISH, headline: `${headline.replace(/\d/g, "")} (in English)` };
    const reply = { ...TRANSLATED[lang], headline: headline.replace(/\d/g, "") };
    expect(check(reply, lang, english)).toHaveProperty("translation");
  });

  it("accepts an English time with a full stop written with a colon", () => {
    const english = { ...ENGLISH, shortSummary: "The offices are open from 9 to 16.30 hours." };
    expect(check({ ...TRANSLATED.es, shortSummary: "Las oficinas abren de 9 a 16:30 horas." }, "es", english)).toHaveProperty("translation");
    expect(check({ ...TRANSLATED.de, shortSummary: "Die Büros sind von 9 bis 16:30 Uhr geöffnet." }, "de", english)).toHaveProperty("translation");
  });

  it("accepts a short field it cannot tell, such as a headline of names", () => {
    const english = { ...ENGLISH, headline: "Macron meets Sánchez in 2027" };
    expect(check({ ...TRANSLATED.es, headline: "Macron recibe a Sánchez en 2027" }, "es", english)).toHaveProperty("translation");
    expect(check({ ...TRANSLATED.de, headline: "Macron trifft Sánchez 2027" }, "de", english)).toHaveProperty("translation");
    expect(OWN_WORDS_FROM).toBe(8);
  });

  it("rejects numbers in the English format", () => {
    const english = { ...ENGLISH, shortSummary: "The cabinet approved 3.5% more for 2027, or $1,500 per family." };
    const result = check({ ...TRANSLATED.de, shortSummary: "Das Kabinett hat für 2027 3.5 % mehr gebilligt, also 1,500 Dollar pro Familie." }, "de", english);
    expect(result).toEqual({ problems: ["shortSummary is missing numbers of the English: 3.5, 1,500"] });
    const right = { ...TRANSLATED.de, shortSummary: "Das Kabinett hat für 2027 3,5 % mehr gebilligt, also 1.500 Dollar pro Familie." };
    expect(check(right, "de", english)).toHaveProperty("translation");
  });
});

describe("the function word lists", () => {
  it("share no word, so none counts for two languages", () => {
    const lists = { ENGLISH: ENGLISH_WORDS, SPANISH, GERMAN };
    for (const [a, first] of Object.entries(lists)) {
      for (const [b, second] of Object.entries(lists)) {
        if (a < b) expect([...first].filter((w) => second.has(w)), `${a} and ${b}`).toEqual([]);
      }
    }
    for (const word of ["a", "no", "es", "in", "an", "so", "also", "was", "war", "will", "he"]) {
      expect([ENGLISH_WORDS, SPANISH, GERMAN].some((list) => list.has(word)), word).toBe(false);
    }
  });
});
