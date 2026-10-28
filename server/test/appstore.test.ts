import { env, exports } from "cloudflare:workers";
import { beforeAll, describe, expect, it } from "vitest";
import {
  BUNDLE_ID,
  CHAT_PRODUCT_ID,
  isActive,
  receiveNotification,
  recordTransaction,
  verifyTransaction,
  type Subscription,
} from "../src/appstore";
import { testAppStore, type TestAppStore } from "./apple-pki";

const DAY = 86_400_000;
const NOW = new Date("2026-10-27T12:00:00Z");

/** A month of the chat's subscription, bought yesterday, as the App Store signs it. */
const transaction = (changes: object = {}) => ({
  originalTransactionId: "1000000001",
  transactionId: "1000000001",
  bundleId: BUNDLE_ID,
  productId: CHAT_PRODUCT_ID,
  environment: "Production",
  purchaseDate: NOW.getTime() - DAY,
  expiresDate: NOW.getTime() + 29 * DAY,
  signedDate: NOW.getTime() - DAY,
  appAccountToken: "6f1d2c0e-4b9a-4a8e-9a49-0b3c2d1e5f60",
  type: "Auto-Renewable Subscription",
  ...changes,
});

const base64url = (text: string) => btoa(text).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");

let store: TestAppStore;
beforeAll(async () => {
  store = await testAppStore();
});
const trusted = () => ({ rootSha256: store.rootSha256, now: NOW });

describe("App Store signed data (#146)", () => {
  it("takes a transaction signed through the trusted root", async () => {
    const t = await verifyTransaction(await store.sign(transaction()), trusted());
    expect(t).toMatchObject({ originalTransactionId: "1000000001", environment: "Production", expiresDate: NOW.getTime() + 29 * DAY });
  });

  it("refuses anything else", async () => {
    const jws = await store.sign(transaction());
    // Apple's root unless told otherwise: the test App Store is not trusted.
    await expect(verifyTransaction(jws)).rejects.toThrow("not Apple's root");
    // A leaf without Apple's mark, such as a developer's own certificate.
    const developer = await testAppStore([]);
    await expect(verifyTransaction(await developer.sign(transaction()), { rootSha256: developer.rootSha256 })).rejects.toThrow(
      "not an App Store certificate",
    );
    // A payload changed after it was signed.
    const [header, , signature] = jws.split(".");
    const longer = base64url(JSON.stringify(transaction({ expiresDate: NOW.getTime() + 365 * DAY })));
    await expect(verifyTransaction(`${header}.${longer}.${signature}`, trusted())).rejects.toThrow("bad signature");
    // Another app, another product.
    await expect(verifyTransaction(await store.sign(transaction({ bundleId: "com.example.other" })), trusted())).rejects.toThrow("another app or product");
    await expect(verifyTransaction(await store.sign(transaction({ productId: "com.officialnews.app.other" })), trusted())).rejects.toThrow(
      "another app or product",
    );
    await expect(verifyTransaction("not.a.jws", trusted())).rejects.toThrow();
  });
});

describe("the subscription's status (#146)", () => {
  const notify = async (type: string, t: object) =>
    receiveNotification(
      {
        signedPayload: await store.sign({
          notificationType: type,
          data: { bundleId: BUNDLE_ID, environment: "Production", signedTransactionInfo: await store.sign(t) },
          signedDate: NOW.getTime(),
          version: "2.0",
        }),
      },
      env,
      trusted(),
    );
  const fromApp = async (t: object) => recordTransaction(env, await verifyTransaction(await store.sign(t), trusted()), { now: NOW });
  const row = async () =>
    (await env.DB.prepare("SELECT * FROM subscriptions WHERE original_transaction_id = '1000000001'").first<Subscription>())!;

  it("is open once bought, closes at once on a refund, and the app's older transaction cannot reopen it; Apple's reversal does", async () => {
    expect((await notify("SUBSCRIBED", transaction())).status).toBe(200);
    expect(await row()).toMatchObject({ transaction_id: "1000000001", expires_at: "2026-11-25T12:00:00Z", revoked_at: null, last_notification: "SUBSCRIBED" });
    expect(isActive(await row(), NOW)).toBe(true);

    await notify("REFUND", transaction({ revocationDate: NOW.getTime() - 1000 }));
    expect((await row()).revoked_at).toBe("2026-10-27T11:59:59Z");
    expect(isActive(await row(), NOW)).toBe(false);

    // The app still holds the transaction signed before the refund.
    await fromApp(transaction());
    expect(isActive(await row(), NOW)).toBe(false);

    await notify("REFUND_REVERSED", transaction());
    expect(isActive(await row(), NOW)).toBe(true);
  });

  it("follows the latest period: a paid renewal opens it again, an older transaction changes nothing, and it closes when it expires", async () => {
    await fromApp(transaction());
    await notify("REFUND", transaction({ revocationDate: NOW.getTime() - 1000 }));
    await notify("DID_RENEW", transaction({ transactionId: "1000000002", expiresDate: NOW.getTime() + 59 * DAY }));
    expect(await row()).toMatchObject({ transaction_id: "1000000002", revoked_at: null, app_account_token: "6f1d2c0e-4b9a-4a8e-9a49-0b3c2d1e5f60" });
    expect(isActive(await row(), NOW)).toBe(true);

    await fromApp(transaction());
    expect((await row()).transaction_id).toBe("1000000002");
    expect(isActive(await row(), new Date(NOW.getTime() + 60 * DAY))).toBe(false);
  });

  it("answers 200 to what it does not keep, 400 to what is not Apple's, 405 to other methods", async () => {
    const test = await receiveNotification({ signedPayload: await store.sign({ notificationType: "TEST", signedDate: NOW.getTime() }) }, env, trusted());
    expect(test.status).toBe(200);
    const otherApp = await receiveNotification(
      {
        signedPayload: await store.sign({
          notificationType: "SUBSCRIBED",
          data: { bundleId: "com.example.other", signedTransactionInfo: await store.sign(transaction({ bundleId: "com.example.other" })) },
          signedDate: NOW.getTime(),
        }),
      },
      env,
      trusted(),
    );
    expect(otherApp.status).toBe(200);

    // Through the Worker, which trusts only Apple's root.
    const post = (body: string) => exports.default.fetch("https://api.test/v1/appstore/notifications", { method: "POST", body });
    expect((await post(JSON.stringify({ signedPayload: await store.sign({ notificationType: "TEST" }) }))).status).toBe(400);
    expect((await post("{")).status).toBe(400);
    const get = await exports.default.fetch("https://api.test/v1/appstore/notifications");
    expect(get.status).toBe(405);
    expect(get.headers.get("allow")).toBe("POST");
    expect(await env.DB.prepare("SELECT COUNT(*) AS n FROM subscriptions").first("n")).toBe(0);
  });
});
