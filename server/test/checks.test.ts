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
    ok("「5ㆍ18민주화운동 관련자 보상 등에 관한 법률」", "the 5.18 Democratization Movement");
  });

  it("reads era years, Arabic-Indic digits and amounts with zero cents (#99)", () => {
    const ok = (source: string, text: string) => expect(checkSummary(summary(text), source, 2026).invented, source).toEqual([]);
    ok("令和10年4月1日から施行", "It takes effect on 1 April 2028.");
    ok("令和元年法律第16号", "the 2019 law");
    ok("平成25年法律第27号", "the 2013 law");
    ok("مبلغ ١٣٥٠٠ ريال", "an amount of 13,500 riyals");
    ok("valor de R$ 1.500.000,00", "worth R$1,500,000");
    ok("valor de R$ 1.500.000,00", "worth R$1.5 million");
    ok("$2,000.00 per household", "$2,000 per household");
    ok("103万円", "1.03 million yen");
    expect(checkSummary(summary("worth R$1.6 million"), "valor de R$ 1.500.000,00", 2026).invented).toEqual(["16"]);
    expect(checkSummary(summary("It takes effect in 2029."), "令和10年4月1日から施行", 2026).invented).toEqual(["2029"]);
    expect(checkSummary(summary("worth R$1,500,050"), "valor de R$ 1.500.000,50", 2026).invented).toEqual(["1500050"]);
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

  it("does not count a ruled-out word inside quotes or in a name the source gives (#99)", () => {
    const banned = (text: string, source: string) => checkSummary(summary(text), source, 2026).banned;
    expect(banned('Wawel joins the "Historic Monument" list.', "Wawel uznany za Pomnik Historii")).toEqual([]);
    expect(banned("The Historic Buildings Act is amended.", "Amendments to the Historic Buildings Act 1990")).toEqual([]);
    expect(banned("A historic decision on the Historic Buildings Act.", "Amendments to the Historic Buildings Act 1990")).toEqual(["historic"]);
    expect(banned("Historic vote in the Sejm.", "Sejm przyjął ustawę")).toEqual(["historic"]);
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

  it("accepts an English summary that is mostly a list of names", () => {
    const names = (headline: string, shortSummary: string, text: string) =>
      checkSummary({ ...summary(text), headline, shortSummary }, "", 2026).notEnglish;
    expect(
      names(
        "Lee Jae-myung names eight vice ministers",
        "Kim Min-seok, Park Ji-won, Choi Sung-hoon, Jung Eun-kyung, Kang Hye-jin, Cho Yong-ho, Han Seung-woo and Yoo Jae-hoon become vice ministers.",
        "President Lee Jae-myung appointed eight vice ministers: Kim Min-seok (Economy and Finance), Park Ji-won (Foreign Affairs), Choi Sung-hoon (National Defense), Jung Eun-kyung (Health and Welfare), Kang Hye-jin (Employment and Labor), Cho Yong-ho (Land, Infrastructure and Transport), Han Seung-woo (Science and ICT) and Yoo Jae-hoon (Trade, Industry and Energy).",
      ),
    ).toBe(false);
    expect(
      names(
        "Cabinet names nine ambassadors, Suzuki Kenji to Brazil",
        "Suzuki Kenji (Brazil), Tanaka Ichiro (Peru), Sato Yuko (Kenya), Ito Shota (Chile), Kato Ren (Ghana), Yoshida Sakura (Laos), Yamada Taro (Nepal), Sasaki Mei (Oman), Inoue Kaito (Fiji) become ambassadors.",
        "The cabinet appointed nine ambassadors extraordinary and plenipotentiary: Suzuki Kenji (Brazil), Tanaka Ichiro (Peru), Sato Yuko (Kenya), Ito Shota (Chile), Kato Ren (Ghana), Yoshida Sakura (Laos), Yamada Taro (Nepal), Sasaki Mei (Oman) and Inoue Kaito (Fiji).",
      ),
    ).toBe(false);
  });

  it("finds a summary written in Japanese or Chinese, which has too few spaces to count its words", () => {
    const ja = "内閣は令和8年10月14日の閣議で、特定船舶の保険契約の履行を確保するための法律案を決定した。法律案は国会に提出され、成立後は公布の日から施行される。";
    const zh = "国务院常务会议审议通过《关于进一步优化营商环境的若干措施》，明确减少行政审批事项，降低企业制度性交易成本。措施自发布之日起施行。";
    expect(checkSummary(summary(ja), ja, 2026).notEnglish).toBe(true);
    expect(checkSummary(summary(zh), zh, 2026).notEnglish).toBe(true);
  });

  it("accepts a short English text that quotes a long name in its own script (#99)", () => {
    const headline = 'Korea amends "5·18민주화운동 관련자 보상 등에 관한 법률 시행령 일부개정령안"';
    expect(checkSummary(summary(headline), "", 2026).notEnglish).toBe(false);
    expect(checkSummary(summary("Japan adopts 「特定船舶の保険契約の履行を確保するための法律の一部を改正する法律案」"), "", 2026).notEnglish).toBe(false);
  });

  it("accepts an English summary that names things in their own language, and a text too short to tell", () => {
    const english =
      "The Bundesregierung approved a state subsidy for private pensions (Altersvorsorge). " +
      "Savers with low incomes get a yearly allowance, paid by the Deutsche Rentenversicherung from 2027.";
    expect(checkSummary(summary(english), english, 2026).notEnglish).toBe(false);
    expect(checkSummary(summary("Kabinett beschließt Haushalt."), "", 2026).notEnglish).toBe(false);
  });
});
