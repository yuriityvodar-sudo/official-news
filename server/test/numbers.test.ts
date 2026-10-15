import { describe, expect, it } from "vitest";
import { LANGUAGES } from "../src/translator";
import { missingNumbers } from "../src/translator/numbers";

const UK = LANGUAGES.uk.numbers;
const RU = LANGUAGES.ru.numbers;

describe("missingNumbers", () => {
  it.each([
    ["Law 5575/2026", "Закон 5575/2026"],
    ["3.5% of GDP", "3,5 % ВВП"],
    ["$1,250,000", "1 250 000 доларів"],
    ["$1,250,000", "1 250 000 доларів"],
    ["$1,500 per family", "1 500 доларів на родину"],
    ["1.2 billion euros", "1,2 млрд євро"],
    ["$1,234.5 million", "1 234,5 млн доларів"],
    ["R$ 1.234,56", "1 234,56 реала"],
    ["Law 14.133/2021", "Закон 14 133/2021"],
    ["Law 14.133/2021", "Закон 14.133/2021"],
    // An identifier after "№" may keep the English comma: it is a label, not an amount.
    ["Law No. 9,394", "Закону № 9,394"],
    ["Law No. 9,394", "Закону № 9394"],
    ["Law No. 9,394", "Закону № 9.394"],
    ["on 19 November 2026", "19 листопада 2026 року"],
    ["on September 14, 2026", "14 вересня 2026 року"],
    ["Decision 129 on September 14, 2026", "Рішення 129 14 вересня 2026 року"],
    ["dated 15.10.2026", "від 15.10.2026"],
    // A numeric date may name its month.
    ["dated 15.10.2026", "від 15 жовтня 2026 року"],
    ["presented a bill on 14/10/2026", "представила законопроєкт 14 жовтня 2026 року"],
    ["published 2026-10-14", "опубліковано 14 жовтня 2026 року"],
    // 05/10/2026 is 5 October or 10 May.
    ["on 05/10/2026", "5 жовтня 2026 року"],
    ["on 05/10/2026", "10 травня 2026 року"],
    ["the 2026-2027 electoral process", "виборчого процесу 2026–2027 років"],
    ["closes at 11:59pm", "закінчується о 23:59"],
    ["closes at 11:59pm", "закінчується об 11:59 вечора"],
    ["closes at 11:59pm on 5 November 2026", "завершується о 23.59 5 листопада 2026 року"],
    ["at 5 p.m.", "о 17:00"],
    ["closes at 5pm on 23 December 2026", "закінчується о 17.00 23 грудня 2026 року"],
    ["closes at 5pm on 23 December 2026", "закінчується о 17 годині 23 грудня 2026 року"],
    ["at 9:30 AM", "о 9:30"],
    ["3.50 percent", "3,5 відсотка"],
    ["the 21st article", "21-ша стаття"],
    ["COVID-19 rules of the G7", "правила G7 щодо COVID-19"],
    ["in 2026.", "у 2026 році."],
    ["5 ministers in 5 regions", "5 міністрів у 5 регіонах"],
    ["Inflation was 3.5% in 5 regions", "Інфляція становила 3,5 % у 5 регіонах"],
    // Two numbers that only a space separates in the English.
    ["In 2025 1,400 people applied", "У 2025 році заявки подали 1 400 людей"],
    ["no numbers at all", "жодних чисел"],
  ])("finds every number of %j in %j", (english, translation) => {
    expect(missingNumbers(english, translation, UK)).toEqual([]);
  });

  it.each([
    ["closes at 11:59pm on 5 November 2026", "завершается в 23.59 5 ноября 2026 года"],
    ["presented a bill on 14/10/2026", "представила законопроект 14 октября 2026 года"],
    ["$1,500 per family", "1 500 долларов на семью"],
  ])("finds every number of %j in the Russian %j", (english, translation) => {
    expect(missingNumbers(english, translation, RU)).toEqual([]);
  });

  it.each([
    ["a dropped year of a bill number", "Law 5575/2026 takes effect", "Закон 5575 набирає чинності", ["2026"]],
    ["a changed date", "closes on 19 November 2026", "закінчується 30 листопада 2026 р.", ["19"]],
    ["a dropped amount", "1.2 billion euros for 300 schools", "1,2 млрд євро для шкіл", ["300"]],
    ["a decimal mark lost", "3.5% of GDP", "35 % ВВП", ["3.5"]],
    ["thousands lost", "500,000 people", "500 людей", ["500,000"]],
    ["thousands in words", "500,000 people", "500 тисяч людей", ["500,000"]],
    ["a wrong time", "at 5 p.m.", "о 15:00", ["5 p.m."]],
    ["a wrong time with a dot", "at 5 p.m.", "о 15.00", ["5 p.m."]],
    // Each number of the translation stands for one number of the English.
    ["a number dropped next to a decimal with its digit", "Inflation was 3.5% in 5 regions", "Інфляція становила 3,5 % у регіонах", ["5"]],
    ["a number dropped next to a grouped number with its digits", "1,500 doctors and 500 nurses", "1 500 лікарів і медсестер", ["500"]],
    ["a number dropped next to a date with its digits", "dated 15.10.2026 for 10 regions", "від 15.10.2026 для регіонів", ["10"]],
    ["a repeated number dropped once", "5 ministers in 5 regions", "5 міністрів у регіонах", ["5"]],
    ["a time dropped next to a day with its digit", "closes at 5pm on 5 November 2026", "завершується 5 листопада 2026 року", ["5pm"]],
    // Ukrainian and Russian read 1,500 as 1.5.
    ["English thousands copied", "$1,500 per family", "1,500 доларів на родину", ["1,500"]],
    ["English thousands copied", "capacity of 2,232 places", "місткість 2,232 місця", ["2,232"]],
    ["English millions copied", "$1,250,000", "1,250,000 доларів", ["1,250,000"]],
    ["a changed day of a numeric date", "dated 15.10.2026", "від 16 жовтня 2026 року", ["15.10.2026"]],
    ["a changed month of a numeric date", "dated 15.10.2026", "від 15 листопада 2026 року", ["15.10.2026"]],
    ["a month that is neither reading of the date", "on 05/10/2026", "5 травня 2026 року", ["05/10/2026"]],
  ])("reports %s", (_, english, translation, missing) => {
    expect(missingNumbers(english, translation, UK)).toEqual(missing);
  });

  it("reports English thousands copied into Russian", () => {
    expect(missingNumbers("$1,500 per family", "1,500 долларов на семью", RU)).toEqual(["1,500"]);
  });
});
