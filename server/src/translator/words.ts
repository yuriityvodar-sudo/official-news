// Short function words ("stop words") of English, Spanish and German, for the
// language check of Latin-script translations (#46). A Spanish or German
// translation is written in the same letters as the English it comes from, so
// the check counts these words instead: a sentence with more English (or
// German, in Spanish) function words than Spanish ones is not Spanish.
//
// Each list holds only words the other two languages do not use, so no word
// counts for two languages: "a" and "no" (English and Spanish), "es"
// (Spanish and German), "in", "an", "so", "also", "was", "war" and "will"
// (English and German), "he" (English and Spanish) are in none of them.

const words = (text: string): ReadonlySet<string> => new Set(text.trim().split(/\s+/));

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
