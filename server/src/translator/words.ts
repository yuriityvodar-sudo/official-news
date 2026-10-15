// Short function words ("stop words") of English, Spanish and German, for the
// language check of Latin-script translations (#46). A Spanish or German
// translation is written in the same letters as the English it comes from, so
// the check counts these words instead: a sentence with more English (or
// German, in Spanish) function words than Spanish ones is not Spanish.
//
// Each list holds only function words the other two languages do not use as
// function words, so no word counts for two languages: "a" and "no" (English
// and Spanish), "es" (Spanish and German), "in", "an", "so", "also", "was",
// "war" and "will" (English and German), "he" (English and Spanish) are in
// none of them. A few are ordinary words of another language all the same
// (German "los" and "her", Spanish "bis"): that language's check leaves them
// out of its foreign lists (`except`, languages.ts).

const words = (text: string): ReadonlySet<string> => new Set(text.trim().split(/\s+/));

/** A list without some words: the foreign words a language also writes itself. */
export const except = (list: ReadonlySet<string>, ...own: string[]): ReadonlySet<string> =>
  new Set([...list].filter((word) => !own.includes(word)));

export const ENGLISH = words(`
  the and of to is are were for with that this these those from by on at which
  has have had been its it be or not their they who would should could after
  about into than said can may must more other under between over such any each
  only our we there what when where while before during because if but up out
  do does did being his her she them new how most some
`);

export const SPANISH = words(`
  el la los las de del y en que por para con un una unos unas se su sus al lo le les
  ha han fue fueron será serán ser está están hay muy cuando donde porque sin según
  durante otro otra otros otras sobre tras nuevo nueva nuevos nuevas este esta estos
  estas esto también más pero como desde hasta entre ante año años dos tres cada
  sido son ya mediante contra hacia
`);

export const GERMAN = words(`
  der die das und den dem des ein eine einen einem einer eines ist sind wurde wurden
  wird werden mit von für auf nicht sich zu zum zur im bei nach auch aus als wie dass
  über um oder noch nur vor durch bis seit gegen unter sowie soll sollen kann können
  muss müssen hat haben hatte sein seine seiner seinen ihre ihr ihren ihrer diese
  dieser dieses diesem diesen wir sie er am vom beim zwischen ab neue neuen neuer
  mehr wenn weil damit dabei jedoch bereits nun
`);

/**
 * Lower-case words inside names of people, places and institutions, such as
 * Ursula von der Leyen, Sindicatura General de la Nación or Veracruz de
 * Ignacio de la Llave. Between capitalised words they are part of the name.
 */
export const NAME_PARTICLES = words(`
  von der den zu zum zur vom van de del la las los y
`);
