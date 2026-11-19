# Android: Outer News on Yurii's Google Play account

**Decision (19 Nov 2026).** The Android app is published from Yurii's personal Google Play developer account, with Yurii as the seller, under the same package `com.officialnews.app`. The App Store stays with RS Elite Pro s.r.o.

**Why.** Roman agreed on #337 (17 Nov, «Да, согласен») that Yurii's Claude takes the Android part of #146, on Yurii's account with Yurii as the seller; Yurii's account already has a payments profile (6 Nov). Yurii said "yes start it" on 19 Nov (#343).

**What follows.**
- Personal accounts must run a closed test with at least 12 testers for 14 days before production, so the first build goes to closed testing.
- The first Android build has the AI chat off (it is iPhone-only until the Google Play subscription is built, #146) and no advertising ID. Analytics and notifications work as on iPhone, with the same consent (Yurii, 19 Nov: "we need to track user behaviour so please keep things consistent; the moment we change some tracking u will update it in all places"): any change to tracking updates the privacy policy, Play's Data safety and App Store Connect's App Privacy together.
- The privacy policy and the website's publisher line name RS Elite Pro s.r.o.; Google asks that the policy name the developer shown on the Play listing, so they need a line for the Android app before it is sent for review (to agree with Roman).

**Status.** Done for the account and the app (docs/setup.md); the closed test is next.
