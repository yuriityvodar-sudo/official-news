// Which language `/` opens (Yurii, 28 Oct: "auto understand the country and
// language", no page to choose one): the first of the browser's languages
// (Accept-Language) the site has, else the one of the country Cloudflare
// sees, else English. Every page keeps the language switcher.
import type { SiteLang } from "./texts";

/**
 * The languages `/` may open. German stays out while the server does not
 * translate into it (its lists are empty); /de still works from the switcher.
 */
const AUTO: readonly SiteLang[] = ["en", "uk", "ru", "es"];

/** A country's language when the browser names none of ours. */
const BY_COUNTRY: Record<string, SiteLang> = {
  UA: "uk",
  RU: "ru", BY: "ru", KZ: "ru", KG: "ru",
  ES: "es", MX: "es", AR: "es", CO: "es", CL: "es", PE: "es", VE: "es", EC: "es", GT: "es", CU: "es",
  BO: "es", DO: "es", HN: "es", PY: "es", SV: "es", NI: "es", CR: "es", PA: "es", UY: "es", PR: "es",
};

/** `uk-UA,uk;q=0.9,en;q=0.8` → the site's languages in the browser's order of preference. */
function browserLangs(header: string | null): SiteLang[] {
  if (!header) return [];
  return header
    .split(",")
    .map((part, i) => {
      const [tag, ...params] = part.trim().split(";");
      const q = Number(params.find((p) => p.trim().startsWith("q="))?.trim().slice(2) ?? "1");
      return { lang: tag.trim().toLowerCase().split("-")[0], q: Number.isFinite(q) ? q : 0, i };
    })
    .filter((x) => x.q > 0)
    .sort((a, b) => b.q - a.q || a.i - b.i)
    .map((x) => x.lang)
    .filter((l): l is SiteLang => (AUTO as readonly string[]).includes(l));
}

/** The language `/` sends a visitor to. */
export function visitorLang(acceptLanguage: string | null, country: string | null): SiteLang {
  return browserLangs(acceptLanguage)[0] ?? (country ? BY_COUNTRY[country] : undefined) ?? "en";
}
