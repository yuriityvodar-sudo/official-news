import { describe, expect, it } from "vitest";
import { missingNumbers } from "../src/translator/numbers";

describe("missingNumbers", () => {
  it.each([
    ["Law 5575/2026", "Закон 5575/2026"],
    ["3.5% of GDP", "3,5 % ВВП"],
    ["$1,250,000", "1 250 000 доларів"],
    ["$1,250,000", "1 250 000 доларів"],
    ["$1,250,000", "1,250,000 доларів"],
    ["1.2 billion euros", "1,2 млрд євро"],
    ["$1,234.5 million", "1 234,5 млн доларів"],
    ["R$ 1.234,56", "1 234,56 реала"],
    ["Law 14.133/2021", "Закон 14 133/2021"],
    ["Law 14.133/2021", "Закон 14.133/2021"],
    ["on 19 November 2026", "19 листопада 2026 року"],
    ["on September 14, 2026", "14 вересня 2026 року"],
    ["Decision 129 on September 14, 2026", "Рішення 129 14 вересня 2026 року"],
    ["dated 15.10.2026", "від 15.10.2026"],
    ["the 2026-2027 electoral process", "виборчого процесу 2026–2027 років"],
    ["closes at 11:59pm", "закінчується о 23:59"],
    ["closes at 11:59pm", "закінчується об 11:59 вечора"],
    ["at 5 p.m.", "о 17:00"],
    ["at 9:30 AM", "о 9:30"],
    ["3.50 percent", "3,5 відсотка"],
    ["the 21st article", "21-ша стаття"],
    ["COVID-19 rules of the G7", "правила G7 щодо COVID-19"],
    ["in 2026.", "у 2026 році."],
    ["no numbers at all", "жодних чисел"],
  ])("finds every number of %j in %j", (english, translation) => {
    expect(missingNumbers(english, translation)).toEqual([]);
  });

  it.each([
    ["a dropped year of a bill number", "Law 5575/2026 takes effect", "Закон 5575 набирає чинності", ["2026"]],
    ["a changed date", "closes on 19 November 2026", "закінчується 30 листопада 2026 р.", ["19"]],
    ["a dropped amount", "1.2 billion euros for 300 schools", "1,2 млрд євро для шкіл", ["300"]],
    ["a decimal mark lost", "3.5% of GDP", "35 % ВВП", ["3.5"]],
    ["thousands lost", "500,000 people", "500 людей", ["500,000"]],
    ["thousands in words", "500,000 people", "500 тисяч людей", ["500,000"]],
    ["a wrong time", "at 5 p.m.", "о 15:00", ["5 p.m."]],
    ["part of a date", "dated 15.10.2026", "від 15 жовтня 2026", ["15.10.2026"]],
  ])("reports %s", (_, english, translation, missing) => {
    expect(missingNumbers(english, translation)).toEqual(missing);
  });
});
