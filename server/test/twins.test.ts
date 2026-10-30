import { describe, expect, it } from "vitest";
import { sameEvent } from "../src/summarizer/twins";

// Summaries the model wrote for the first live events (30 Oct), from the English and the Russian page.
const lagardeEn = {
  headline: "Christine Lagarde resigns as European Central Bank president",
  shortSummary: "European Central Bank President Christine Lagarde will resign in February 2027.",
  countries: ["EU"],
};
const lagardeRu = {
  headline: "Christine Lagarde resigns as European Central Bank President",
  shortSummary: "Christine Lagarde will step down as President of the European Central Bank in February 2027.",
  countries: ["EU"],
};
const taiz = {
  headline: "Saudi Arabia airstrikes kill 12 civilians in Taiz, Yemen",
  shortSummary: "Twelve civilians were killed and three wounded during Saudi Arabian airstrikes on residential buildings in Taiz, Yemen.",
  countries: ["SA", "YE"],
};

describe("sameEvent (#230)", () => {
  it("finds the same event told from the two Wikipedias", () => {
    expect(sameEvent(lagardeEn, lagardeRu)).toBe(true);
    expect(sameEvent(lagardeRu, lagardeEn)).toBe(true);
  });

  it("tells apart two strikes on one city with different numbers, and an event in another country", () => {
    const other = {
      ...taiz,
      headline: "Saudi Arabia airstrikes kill 5 civilians in Taiz, Yemen",
      shortSummary: "Five civilians were killed and two wounded during Saudi Arabian airstrikes on residential buildings in Taiz, Yemen.",
    };
    expect(sameEvent(taiz, other)).toBe(false);
    expect(sameEvent(lagardeEn, { ...lagardeRu, countries: ["US"] })).toBe(false);
  });

  it("tells apart different events of one country", () => {
    const toledo = {
      headline: "Train collision in Toledo, Spain, kills 69 people",
      shortSummary: "Sixty-nine people died following a train collision in Toledo, Spain.",
      countries: ["ES"],
    };
    const madrid = {
      headline: "Spain's parliament approves the 2027 budget",
      shortSummary: "The Spanish parliament approved the state budget for 2027.",
      countries: ["ES"],
    };
    expect(sameEvent(toledo, madrid)).toBe(false);
  });
});
