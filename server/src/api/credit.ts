import { CREDITS } from "../site/credits.generated";

/**
 * What a source's licence asks to be shown with its articles (#230), from
 * docs/source-credits.csv, so the app shows it as the site does: Global
 * Voices' CC BY, RFE/RL's "Used with the permission of…".
 */
export interface ArticleCredit {
  /** The licence's name, a link when there is a URL. */
  licence: string | null;
  licenceUrl: string | null;
  /** Exact wording the source asks for, in `wordingLang`. */
  wording: string | null;
  wordingLang: string | null;
}

/** The credit of an article of `sourceId` published at `publishedAt` (a wording's `{year}` is that year); null for a source with neither licence nor wording. */
export function creditOf(sourceId: string, publishedAt: string): ArticleCredit | null {
  const row = CREDITS[sourceId];
  if (!row?.licence && !row?.wording) return null;
  return {
    licence: row.licence ?? null,
    licenceUrl: row.licenceUrl ?? null,
    wording: row.wording ? row.wording.replace(/\{year\}/g, publishedAt.slice(0, 4)) : null,
    wordingLang: row.wordingLang ?? null,
  };
}
