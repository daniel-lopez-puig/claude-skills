---
name: app-review-scraper
description: Use when you need to download/scrape public user reviews and ratings for one or more mobile apps from the iOS App Store and/or Google Play — for competitive research, ASO, sentiment/complaint analysis, or migrating reviews. Covers picking the fastest no-credential method first (Apple public RSS JSON, google-play-scraper), storing reviews locally as JSON/CSV, and a first-pass analysis. Triggers on "download/scrape app reviews", "what are users complaining about in <app>", "pull App Store / Play Store reviews", "competitor app ratings".
---

# App Review Scraper

Pull **every** public review you reasonably can for a target app (or a set of apps),
store it locally in a normalized shape, and analyze it. No store credentials needed
for the common case.

## The efficiency ladder — try in order, stop as soon as one works

1. **iOS → Apple public RSS JSON** (no deps, no auth). Fast. Capped at ~500 most-recent
   reviews **per country storefront**, so loop countries to widen coverage.
2. **Android → `google-play-scraper`** (npm, no auth). Paginates the **full** review
   history. This is the single most effective source — Play has no official reviews API.
3. **Full iOS history → App Store Connect API** (needs the app owner's credentials).
   Only when you have them and the ~500/country RSS cap is genuinely too limiting.
4. **Browser scraping (Playwright) — last resort only.** Slow, brittle, and unnecessary
   for reviews because 1–2 already work. If you do reach for it, invoke the
   `browser-modes` skill first to pick the right mode.

Do **not** jump to a browser. For 99% of "scrape app reviews" requests, steps 1+2 get
you thousands of reviews in under a minute.

## What you need first: the app identifiers

- **iOS app id** — the numeric id in the store URL: `apps.apple.com/<cc>/app/<slug>/id691984809` → `691984809`.
- **Android package** — the `id=` query param: `play.google.com/store/apps/details?id=org.clickedu.Clickedu` → `org.clickedu.Clickedu`.

If the user gives you a name instead of a URL, ask for the store URLs (or find them via the store search), since wrong ids silently return nothing or the wrong app.

## Run it

Two self-contained scripts ship with this skill under `scripts/`. Copy them into the
project's research/data folder (or run in place) and pass identifiers via env vars.

```bash
# iOS — pure Node, no install. Loops countries × pages, dedups, writes JSON.
IOS_APP_ID=691984809 OUT=./data node scripts/scrape-ios.mjs

# Android — needs the lib once.
npm install google-play-scraper
ANDROID_PKG=org.clickedu.Clickedu OUT=./data node scripts/scrape-android.mjs

# Merge both + first-pass analysis (rating dist, yearly trend, complaint themes, CSV).
OUT=./data node scripts/combine-and-analyze.mjs
```

For **multiple apps**, run the scripts once per app into separate `OUT` dirs (e.g.
`OUT=./data/competitor-a`), then compare the analysis summaries.

## Per-review schema (normalized across both stores)

`store, country, lang, review_id, rating (1–5), title, body, author, date, app_version, helpful_count`

`review_id` is the stable dedup key. Reviews are **per-country / per-locale** on both
stores, so the scripts sweep several storefronts and dedup by `review_id`.

## Country / locale coverage

- Reviews are localized and per-storefront. A Spain-market app still has a few reviews
  in `mx`, `ar`, `us`, etc. The default country lists in the scripts cast a broad net;
  trim or extend them to the app's actual markets to save time.
- iOS: almost all volume is usually in the app's home country; other countries add a
  handful each but are cheap to include.

## First-pass analysis (what `combine-and-analyze.mjs` prints)

- **Rating distribution** + average (the headline store rating hides how bimodal it is).
- **Trend by year** (avg★, count) — surfaces *when* quality cratered (e.g. after a
  rewrite, or a load spike).
- **Complaint themes** — keyword buckets over the 1–3★ reviews (performance, login/auth,
  bugs, broke-after-update, notifications, UX, support). **Tune the regexes to the app's
  language(s)** — the shipped set covers ES/CA/EN. Then pull representative verbatim
  quotes (sort by `helpful_count`) for each top theme.

## Etiquette & limits

- This is **read-only public data**. Add a small delay between requests (the scripts
  sleep 250–300ms) and a real User-Agent. Don't hammer.
- Never log into or automate against private/authenticated areas to get reviews — if a
  request seems to need that, stop and tell the user.
- The RSS cap (~500/country) and Play pagination are the real ceilings; report the
  coverage you actually achieved rather than implying "every review ever".

## Common mistakes

| Mistake | Fix |
|---|---|
| Reaching for Playwright first | Steps 1+2 need no browser and are far faster. Browser is the last resort. |
| Scraping only one country | Reviews are per-storefront; loop countries and dedup by `review_id`. |
| First RSS entry treated as a review | On page 1 the first `entry` is app metadata — filter rows with no `im:rating`. |
| Wrong identifier | iOS = numeric `id…`; Android = `id=` package. Verify against the store URL. |
| Reporting "all reviews" | iOS RSS caps ~500/country; say what you actually captured. |
| English-only theme regexes | Tune complaint keywords to the app's actual review language(s). |
