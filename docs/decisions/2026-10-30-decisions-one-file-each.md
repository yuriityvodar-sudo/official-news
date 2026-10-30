# Decisions, one file each

- **Decision:** new decisions go into `docs/decisions/`, one file each (`YYYY-MM-DD-short-name.md`), instead of a row at the top of the table in `docs/decisions.md`. The table stays as the history up to 30 Oct. CLAUDE.md says so.
- **Why:** every pull request added its row at the same place, the top of one table, so any two open pull requests conflicted there. On 30 Oct #255 conflicted three times for that alone, each time costing a fresh approval. Separate files never collide.
- **Status:** Proposed (Yurii, 30 Oct: «propose now»); Roman's approval of this pull request agrees it.
