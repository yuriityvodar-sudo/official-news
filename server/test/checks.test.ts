import { describe, expect, it } from "vitest";
import { checkSummary } from "../src/summarizer/checks";
import type { Summary } from "../src/summarizer/schema";

const summary = (text: string, impact: Summary["impact"] = null): Summary => ({
  isNews: true,
  decisionType: "decision",
  headline: "Headline",
  shortSummary: "Short.",
  summary: text,
  topics: ["economy"],
  tags: [],
  importance: 3,
  impact,
});

describe("checkSummary", () => {
  it("accepts numbers the article gives, also written another way", () => {
    const source = "Die Regierung stellt 2.500 Megawatt bereit, ab 1. Juli 2028; 86 Prozent; 2 000 Anlagen.";
    expect(checkSummary(summary("2,500MW from 1 July 2028; 86% agree; 2000 plants."), source, 2026).invented).toEqual([]);
  });

  it("finds a number the article does not give, also in the impact lines", () => {
    const s = summary("Nothing new.", { general: "Costs rise by 15%.", byTopic: [], residents: null, abroad: null });
    expect(checkSummary(s, "The ministry published a notice.", 2026).invented).toEqual(["15"]);
  });

  it("accepts the year the article was fetched and the years next to it (令和8年 is 2026)", () => {
    const source = "令和8年10月15日 持ち回り閣議案件";
    expect(checkSummary(summary("On 15 October 2026 the cabinet decided."), source, 2026).invented).toEqual([]);
    expect(checkSummary(summary("On 15 October 2036 the cabinet decided."), source, 2026).invented).toEqual(["2036"]);
  });

  it("does not read a date like 'October 19, 2026' as one number", () => {
    expect(checkSummary(summary("Comments are open until October 19, 2026."), "의견 제출 기한 2026. 10. 19.", 2026).invented).toEqual([]);
  });

  it("finds ruled-out words, once each", () => {
    const s = summary("The law aims to help. It may change prices. It aims to be fair.");
    expect(checkSummary(s, "", 2026).banned).toEqual(["aims to", "may"]);
  });
});
