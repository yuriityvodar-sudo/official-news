// The admin page's Worker (admin.outernews.app): its bindings.

export interface AdminEnv {
  /** The Google Analytics property of the app and the website (docs/setup.md). Not a secret. */
  GA_PROPERTY: string;
  /** Cloudflare Access's team: its sign-in tokens are checked against this team's keys. */
  ACCESS_TEAM: string;
  /** The Access app's Application Audience (AUD) tag: a token must be for this app. Not a secret. */
  ACCESS_AUD: string;
  /**
   * Who may open the page, comma-separated; Cloudflare Access lets in the same
   * two. A Worker secret, so our addresses stay out of the public repo; when
   * it is missing nobody gets in.
   */
  ADMIN_EMAILS: string;
  /** The analytics-reader service account (read only on the property), whose key this Worker makes itself (selfkey.ts). */
  GA_CLIENT_EMAIL: string;
  /** This Worker's own storage: its Google key (selfkey.ts). Only this Worker binds it. */
  ADMIN_KV: KVNamespace;
  /** The API's D1 database (#220): this Worker reads and writes only its support tables, readers' messages. */
  DB: D1Database;
  /**
   * Optional: a service account's whole JSON key as a Worker secret, used
   * instead of the self-made key when set. Not needed (#60, 29 Oct).
   */
  GA_SERVICE_ACCOUNT?: string;
}
