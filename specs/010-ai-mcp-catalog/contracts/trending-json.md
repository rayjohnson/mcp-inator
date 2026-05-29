# Contract: trending.json — SUPERSEDED

**Status**: This file is no longer a separate app-facing catalog file.

Trending/sentiment data (trendingScore, sentimentSummary, mentionCount) has been merged into `stats.json` as the `sentimentComputedAt`, `trendingScore`, `sentimentSummary`, `mentionCount`, and `periodDays` fields on each server entry.

**See**: [contracts/stats-json.md](stats-json.md) — "Sentiment / Trending" section.

**Why merged**: The app only needs two HTTP requests to render the full catalog view. Trending signals are computed per-server metrics no different in nature from GitHub star counts — separating them into their own file was unnecessary complexity.
