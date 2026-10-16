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

  it("accepts numbers copied from another way of writing them (dates, full-width digits, scale words)", () => {
    const ok = (source: string, text: string) => expect(checkSummary(summary(text), source, 2026).invented, source).toEqual([]);
    ok("Rada Ministrów przyjęła 14.10.2026 r.", "On 14 October 2026 the council adopted it.");
    ok("의견 제출 기한 2026.10.19.", "Comments are open until 19 October 2026.");
    ok("山岸秀彬外７５名を判事兼簡易裁判所判事に任命", "Yamagishi and 75 others are appointed judges.");
    ok("いわゆる１０３万円の壁", "the 1.03 million yen threshold");
    ok("z 5 tys. zł do 7 tys. zł", "from PLN 5,000 to PLN 7,000");
    ok("1천제곱미터", "1,000 square metres");
    ok("ciclo escolar 2026-2027", "the 2026-27 school year");
    ok("5·18민주화운동 관련자 보상 등에 관한 법률", "the law on the victims of the 5.18 democratization movement");
  });

  it("still finds a number made from parts of another one", () => {
    expect(checkSummary(summary("500 MW"), "2.500 MW", 2026).invented).toEqual(["500"]);
    expect(checkSummary(summary("US$521 for each"), "US$ 13.521.937", 2026).invented).toEqual(["521"]);
    expect(checkSummary(summary("147 people"), "外１４６名", 2026).invented).toEqual(["147"]);
  });

  it("finds ruled-out words, once each, and lets 'may' for a permission pass", () => {
    const s = summary("The law aims to help. It could change prices. It aims to be fair. Providers may now sell devices.");
    expect(checkSummary(s, "", 2026).banned).toEqual(["aims to", "could"]);
  });

  it("finds a summary written in the article's language instead of English", () => {
    const german =
      "Die Bundesregierung will einen staatlichen Zuschuss für die private Altersvorsorge einführen. " +
      "Sparer mit kleinen Einkommen erhalten eine Zulage, die jedes Jahr von der Rentenversicherung ausgezahlt wird.";
    const portuguese =
      "A deputada propõe ampliar as compras da agricultura familiar no Programa Nacional de Alimentação Escolar. " +
      "O projeto obriga os municípios a comprar ao menos metade dos alimentos de produtores locais.";
    expect(checkSummary(summary(german), german, 2026).notEnglish).toBe(true);
    expect(checkSummary(summary(portuguese), portuguese, 2026).notEnglish).toBe(true);
  });

  it("accepts an English summary that names things in their own language, and a text too short to tell", () => {
    const english =
      "The Bundesregierung approved a state subsidy for private pensions (Altersvorsorge). " +
      "Savers with low incomes get a yearly allowance, paid by the Deutsche Rentenversicherung from 2027.";
    expect(checkSummary(summary(english), english, 2026).notEnglish).toBe(false);
    expect(checkSummary(summary("Kabinett beschließt Haushalt."), "", 2026).notEnglish).toBe(false);
  });
});
