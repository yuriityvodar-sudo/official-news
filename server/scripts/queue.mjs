// Manages the translation queue (#46, docs/queue.md). From server/:
//   node scripts/queue.mjs status --remote
//   node scripts/queue.mjs list --state failed --lang es --remote
//   node scripts/queue.mjs history <article-id> [lang] --remote
//   node scripts/queue.mjs requeue <article-id> <lang> --remote
//   node scripts/queue.mjs requeue-lang <lang> [--failed] --remote
//   node scripts/queue.mjs backlog <lang> --remote
//   node scripts/queue.mjs pause|resume|enable|disable <lang> --remote
// --local works on the database of `npm run dev`; --db <name> picks another D1
// database from wrangler.jsonc (default official-news). Every command runs
// `npx wrangler d1 execute`, which needs a wrangler login for --remote. Nothing
// here reads or prints a secret.
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import * as sql from "./queue-sql.mjs";

const USAGE = `usage: node scripts/queue.mjs <command> (--local | --remote) [--db <name>]
commands:
  status                              each language's switch and its count per state
  list [--state S] [--lang L] [--limit N]
                                      translations, the latest change first (states: ${sql.STATES.join(", ")})
  history <article-id> [lang]         every state change of one article, with its time
  requeue <article-id> <lang>         that translation again, with fresh tries
  requeue-lang <lang> [--failed]      the whole feed of a language again (after a prompt change), or its failed ones
  backlog <lang>                      queue the feed's 7 days for a language (enable does this too)
  pause <lang> | resume <lang>        a paused language is queued but not translated
  enable <lang> | disable <lang>      only an enabled language is queued
languages: ${sql.LANGS.join(", ")}`;

/** Which commands only read. */
const READS = new Set(["status", "list", "history"]);

/**
 * Reads the command line: the statements to run and where. Throws with the
 * usage on a mistake, before anything runs.
 */
export function parse(argv) {
  const flags = {};
  const args = [];
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === "--local" || arg === "--remote" || arg === "--failed") flags[arg.slice(2)] = true;
    else if (["--db", "--state", "--lang", "--limit"].includes(arg)) {
      if (argv[i + 1] === undefined || argv[i + 1].startsWith("--")) throw new Error(`${arg} needs a value\n${USAGE}`);
      flags[arg.slice(2)] = argv[++i];
    } else if (arg.startsWith("--")) throw new Error(`unknown option ${arg}\n${USAGE}`);
    else args.push(arg);
  }
  if (!!flags.local === !!flags.remote) throw new Error(`choose --local or --remote\n${USAGE}`);
  const [command, ...rest] = args;
  const need = (n) => {
    if (rest.length !== n) throw new Error(`${command} takes ${n} argument${n === 1 ? "" : "s"}\n${USAGE}`);
  };
  let statements;
  switch (command) {
    case "status":
      need(0);
      statements = sql.status();
      break;
    case "list":
      need(0);
      statements = sql.list({ state: flags.state, lang: flags.lang, limit: flags.limit });
      break;
    case "history":
      if (rest.length < 1 || rest.length > 2) throw new Error(`history takes an article id and a language or none\n${USAGE}`);
      statements = sql.history(rest[0], rest[1]);
      break;
    case "requeue":
      need(2);
      statements = sql.requeue(rest[0], rest[1]);
      break;
    case "requeue-lang":
      need(1);
      statements = sql.requeueLang(rest[0], { failed: !!flags.failed });
      break;
    case "backlog":
    case "pause":
    case "resume":
    case "enable":
    case "disable":
      need(1);
      statements = { backlog: sql.backlog, pause: sql.pause, resume: sql.resume, enable: sql.enable, disable: sql.disable }[command](rest[0]);
      break;
    default:
      throw new Error(`${command ? `unknown command ${command}` : "no command"}\n${USAGE}`);
  }
  return {
    command,
    reads: READS.has(command),
    statements,
    wrangler: ["wrangler", "d1", "execute", flags.db ?? "official-news", flags.remote ? "--remote" : "--local", "--json", "--yes", "--command", statements.join(";\n")],
  };
}

/**
 * Prints what wrangler returned: the rows of a read, or the rows a write
 * changed (each write returns them). An empty write is a success too: nothing
 * matched (no news article in the 7-day feed with that id, or already queued).
 */
function report(plan, output) {
  const results = JSON.parse(output);
  for (const result of results) {
    const rows = result.results ?? [];
    if (rows.length) console.table(rows);
    else console.log(plan.reads ? "no rows" : `${plan.command}: nothing changed (only news of the 7-day feed with an English summary is queued)`);
  }
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  let plan;
  try {
    plan = parse(process.argv.slice(2));
  } catch (error) {
    console.error(error.message);
    process.exit(2);
  }
  const serverDir = fileURLToPath(new URL("..", import.meta.url));
  const run = spawnSync("npx", plan.wrangler, { cwd: serverDir, encoding: "utf8", stdio: ["inherit", "pipe", "inherit"] });
  if (run.status !== 0) {
    process.stdout.write(run.stdout ?? "");
    process.exit(run.status ?? 1);
  }
  report(plan, run.stdout);
}
