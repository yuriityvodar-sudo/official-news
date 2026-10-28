/** The app, and what it sells in the App Store for the AI chat (#146; docs/setup.md). */
export const BUNDLE_ID = "com.officialnews.app";

/** The subscription that opens the chat: 20 questions a day. */
export const CHAT_PRODUCT_ID = "com.officialnews.app.agent.monthly";

/**
 * The packs of questions bought on top (consumables, Roman 27 Oct), by how
 * many questions each adds: $0.99 and $2.99. They never expire and are spent
 * after the day's questions.
 */
export const PACK_QUESTIONS: Record<string, number> = {
  "com.officialnews.app.agent.questions50": 50,
  "com.officialnews.app.agent.questions200": 200,
};
