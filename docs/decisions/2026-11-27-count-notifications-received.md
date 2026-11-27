# Count the notifications phones receive, anonymously

**Decision (27 Nov 2026, Yurii).** Each phone tells the server when a notification arrives, with only its language and the platform (`POST /v1/push/delivered`), and the server keeps one count per day, language and platform (`push_delivered`). No id, token or article is sent, so nobody can be told apart. Android reports from the app's message handlers; iPhone from a notification service extension, in a following pull request. The privacy policy says so in one sentence (`privacyNotificationsCount`, five languages, app and website), dated 27 Nov 2026.

**Why.** The server sends to FCM topics, so it never knew how many phones a notification reached; Analytics counts only readers who allow it (30 people in 28 days). A count with no id is not personal data, so it needs no consent, unlike per-reader tracking.

**Status.** Android and the server in this pull request; iPhone next. Apple's App Privacy and Google Play's Data safety: anonymous counts that are not linked to anyone are not "collected" data in their sense; to be checked when the forms are next updated.
