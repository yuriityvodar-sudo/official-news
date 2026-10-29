// The Messages tab (#220): readers' messages from the app, our replies and
// Close. Everything a reader wrote is escaped. The admin Worker reads and
// writes only the support tables of the shared D1 database.
import { toStoredTime } from "../fetcher/text";
import { MAX_TEXT, readText } from "../support";
import type { AdminEnv } from "./env";
import { esc } from "./page";

/** The conversations the tab shows: waiting ones first, then by their latest message. */
export const SHOWN_THREADS = 50;

const LANG_NAMES: Record<string, string> = { en: "English", uk: "Ukrainian", ru: "Russian", es: "Spanish", de: "German" };
const STATUS: Record<string, string> = { waiting: "Waiting for us", answered: "Answered", closed: "Closed" };

const ORDER = `ORDER BY status = 'waiting' DESC, updated_at DESC LIMIT ${SHOWN_THREADS}`;

interface ThreadRow {
  id: string;
  status: string;
  lang: string;
  app: string;
  created_at: string;
  updated_at: string;
  closed_at: string | null;
  reply_push_pending: number;
}

const when = (at: string) => `${at.slice(0, 16).replace("T", " ")} UTC`;

function threadHtml(t: ThreadRow, messages: { sender: string; text: string; created_at: string }[]): string {
  const facts = [
    LANG_NAMES[t.lang] ?? t.lang,
    t.app ? `app ${t.app}` : "",
    `started ${when(t.created_at)}`,
    `last message ${when(t.updated_at)}`,
    t.closed_at ? `closed ${when(t.closed_at)}` : "",
    t.reply_push_pending ? "push to send" : "",
  ].filter(Boolean);
  const list = messages
    .map((m) => `<div class="msg ${m.sender === "team" ? "team" : "reader"}"><small>${m.sender === "team" ? "Us" : "Reader"} · ${esc(when(m.created_at))}</small><p>${esc(m.text)}</p></div>`)
    .join("");
  const id = esc(t.id);
  const forms =
    t.status === "closed"
      ? ""
      : `<form class="reply" method="post" action="/messages/reply"><input type="hidden" name="thread" value="${id}"><textarea name="text" rows="4" maxlength="${MAX_TEXT}" required aria-label="Reply"></textarea><button type="submit">Send</button></form>
<form method="post" action="/messages/close"><input type="hidden" name="thread" value="${id}"><button type="submit" class="plain">Close</button></form>`;
  return `<section class="thread"><h2>${esc(STATUS[t.status] ?? t.status)}</h2><p class="muted">${esc(facts.join(" · "))}</p>${list}${forms}</section>`;
}

/** The tab's sections: every shown conversation with its messages (two statements in one batch). */
export async function messagesTab(env: AdminEnv): Promise<string> {
  const [threads, messages] = await env.DB.batch([
    env.DB.prepare(`SELECT id, status, lang, app, created_at, updated_at, closed_at, reply_push_pending FROM support_threads ${ORDER}`),
    env.DB.prepare(
      `SELECT thread_id, sender, text, created_at FROM support_messages
       WHERE thread_id IN (SELECT id FROM support_threads ${ORDER}) ORDER BY created_at, rowid`,
    ),
  ]);
  const rows = threads.results as unknown as ThreadRow[];
  if (!rows.length) return `<section style="margin-top:20px"><h2>Messages</h2><p class="muted">No messages yet.</p></section>`;
  const byThread = new Map<string, { sender: string; text: string; created_at: string }[]>();
  for (const m of messages.results as unknown as { thread_id: string; sender: string; text: string; created_at: string }[]) {
    byThread.set(m.thread_id, [...(byThread.get(m.thread_id) ?? []), m]);
  }
  return rows.map((t) => threadHtml(t, byThread.get(t.id) ?? [])).join("\n");
}

/**
 * POST /messages/reply {thread, text}: our message, the conversation answered
 * and its push to send (the API Worker's cron). Not into a closed one.
 * POST /messages/close {thread}. Returns an error for the page, or null.
 */
export async function messagePost(path: string, form: FormData, env: AdminEnv, now = new Date()): Promise<string | null> {
  const thread = form.get("thread");
  if (typeof thread !== "string" || !thread) return "No conversation given.";
  const at = toStoredTime(now);
  if (path === "/messages/close") {
    await env.DB.prepare("UPDATE support_threads SET status = 'closed', closed_at = ?2 WHERE id = ?1 AND status <> 'closed'").bind(thread, at).run();
    return null;
  }
  const text = readText(form.get("text"));
  if (text === null) return `A reply is 1 to ${MAX_TEXT.toLocaleString("en-US")} characters.`;
  const id = crypto.randomUUID();
  await env.DB.batch([
    env.DB.prepare(
      `INSERT INTO support_messages (id, thread_id, sender, text, created_at)
       SELECT ?1, ?2, 'team', ?3, ?4 WHERE EXISTS (SELECT 1 FROM support_threads WHERE id = ?2 AND status <> 'closed')`,
    ).bind(id, thread, text, at),
    env.DB.prepare(
      "UPDATE support_threads SET status = 'answered', reply_push_pending = 1, updated_at = ?2 WHERE id = ?1 AND EXISTS (SELECT 1 FROM support_messages WHERE id = ?3)",
    ).bind(thread, at, id),
  ]);
  return null;
}
