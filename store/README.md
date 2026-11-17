# App Store page

What the App Store shows for Outer News, kept in the repo so both of us can review it in a pull request before it goes to Apple (#338).

- `listing/`: the store texts per language (name, subtitle, keywords, promotional text, description). `python3 -I store/listing/check.py` checks Apple's limits and that the keywords repeat no word of the name or subtitle. Why these words: `docs/research/2026-11-16 App Store search (ASO).md`.

Nothing here reaches Apple by itself: each change is entered in App Store Connect with Yurii's yes, and the name and subtitle change only with a new version.
