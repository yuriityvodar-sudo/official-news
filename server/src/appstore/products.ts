/** The app, and what it sells in the App Store for the AI chat (#146; docs/setup.md). */
export const BUNDLE_ID = "com.officialnews.app";

/** The subscription that opens the chat: a week's usage (`WEEKLY_MICROS` in chat/usage.ts), back every Monday. */
export const CHAT_PRODUCT_ID = "com.officialnews.app.agent.monthly";

/**
 * The packs of extra usage bought on top (consumables, Roman 27 Oct), by how
 * many weeks' usage each adds (Roman, 4 Nov): +1 week for $0.99, +3 weeks for
 * $2.99. The product ids keep the names they had as packs of 50 and 200
 * questions. They never expire and are spent after the week's usage.
 */
export const PACK_WEEKS: Record<string, number> = {
  "com.officialnews.app.agent.questions50": 1,
  "com.officialnews.app.agent.questions200": 3,
};
