# Website pull requests merge without the other person's approval

**Decision (26 Nov 2026, Yurii as the repo owner: "We don't need his permissions for the website… Just keep him informed").** A pull request that changes only the website merges once CI is green, without Roman's approval. Roman is informed through a message issue (#352) and can comment at any time. Everything else still needs the other person's approval, as before.

**How.** GitHub's branch protection cannot require approvals per folder, so the required approving reviews on `main` went from 1 to 0 (changed by Yurii's Claude on his word; pull requests, the two CI checks, no force pushes and "applies to admins" stay). The approval for non-website changes is now kept by the rule in `CLAUDE.md`, not by GitHub.

**Why.** The website is Yurii's item (#88). Google stopped crawling the site on 11–12 Nov (#350), and each fix waited days for a review.

**Status.** In force. First merges under it: #351 and #353.
