// robots.txt (RFC 9309): which paths a site lets our fetcher read.

export const ROBOTS_TOKEN = "officialnewsbot";

interface Rule {
  allow: boolean;
  pattern: string;
}

export type Robots = { kind: "rules"; rules: Rule[] } | { kind: "allowAll" } | { kind: "disallowAll"; reason: string };

/** Keeps the rules of the group for our token, or the `*` group when there is none. */
export function parseRobots(text: string): Robots {
  const groups: { agents: string[]; rules: Rule[] }[] = [];
  let current: { agents: string[]; rules: Rule[] } | null = null;
  let lastWasAgent = false;

  for (const rawLine of text.split(/\r?\n/)) {
    const line = rawLine.replace(/#.*$/, "").trim();
    const m = line.match(/^([A-Za-z-]+)\s*:\s*(.*)$/);
    if (!m) continue;
    const key = m[1].toLowerCase();
    const value = m[2].trim();
    if (key === "user-agent") {
      if (!current || !lastWasAgent) {
        current = { agents: [], rules: [] };
        groups.push(current);
      }
      current.agents.push(value.toLowerCase());
      lastWasAgent = true;
    } else if ((key === "allow" || key === "disallow") && current) {
      // An empty Disallow allows everything; it adds no rule.
      if (value) current.rules.push({ allow: key === "allow", pattern: value });
      lastWasAgent = false;
    } else {
      lastWasAgent = false;
    }
  }

  const ours = groups.filter((g) => g.agents.some((a) => a !== "*" && ROBOTS_TOKEN.includes(a)));
  const chosen = ours.length ? ours : groups.filter((g) => g.agents.includes("*"));
  return { kind: "rules", rules: chosen.flatMap((g) => g.rules) };
}

function matches(pattern: string, path: string): boolean {
  const anchored = pattern.endsWith("$");
  const body = anchored ? pattern.slice(0, -1) : pattern;
  const regex = body.split("*").map((part) => part.replace(/[.+?^${}()|[\]\\]/g, "\\$&")).join(".*");
  return new RegExp(`^${regex}${anchored ? "$" : ""}`).test(path);
}

/** The longest matching rule wins; on a tie, Allow wins. No matching rule means allowed. */
export function isAllowed(robots: Robots, pathAndQuery: string): boolean {
  if (robots.kind === "allowAll") return true;
  if (robots.kind === "disallowAll") return false;
  let best: Rule | null = null;
  for (const rule of robots.rules) {
    if (!matches(rule.pattern, pathAndQuery)) continue;
    if (!best || rule.pattern.length > best.pattern.length || (rule.pattern.length === best.pattern.length && rule.allow)) {
      best = rule;
    }
  }
  return best ? best.allow : true;
}

/** How a robots.txt response is read: 4xx means no rules; 5xx or no answer means stay away for now. */
export function robotsFromResponse(status: number, body: string): Robots {
  if (status >= 200 && status < 300) return parseRobots(body);
  if (status >= 400 && status < 500) return { kind: "allowAll" };
  return { kind: "disallowAll", reason: `robots.txt answered HTTP ${status}` };
}
