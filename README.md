# claude-skills

A small, community-maintained marketplace of [Claude Code](https://docs.claude.com/en/docs/claude-code) skills.

## Skills

### `mobile-web-correctness`
A maintained checklist of mobile **web** frontend gotchas that desktop and headless testing never surface — and that any good frontend should handle up front:

- iOS input **auto-zoom** (inputs must be ≥16px)
- On-screen **keyboard** handling via `visualViewport` (not `100vh`)
- `position:fixed` overlays that let the page **bleed through** on mobile → portal to `document.body`
- iOS **scroll-lock** (`position:fixed` on body, not `overflow:hidden`)
- `dvh` vs `vh`, **safe-area** insets, touch targets, input hints

The skill auto-surfaces when you build/edit web UI, overlays, or forms, or fix iOS/Safari/Android keyboard/viewport bugs.

### `browser-modes`
Stops the single most common Playwright-with-an-agent failure: the agent runs a **headless** browser and then narrates it as if you're looking over its shoulder ("as you can see on the page…") — but there's no window, so you can't. The skill makes the agent pick a mode on purpose:

- **Headless** (default) — invisible, fast, throwaway. The agent must share **screenshots** instead of implying you can see it.
- **Visible window** — opened **up front** when the task needs a login/auth (not after faceplanting into a login wall), on a persistent profile so sessions survive.
- **Handover** — attaches to your **real, already-open Chrome** over the DevTools port, only when you explicitly ask ("take over my browser", "the tab I have open"), with guest etiquette (work in a new tab, confirm destructive actions, leave your other tabs alone).

It auto-surfaces before any browser-automation / web-testing / screenshot task. The handover mode needs a small one-time local setup (a dedicated debug Chrome profile + helper script) documented inside the skill.

### `app-review-scraper`
Download **every public review** for one or more mobile apps from the **iOS App Store** and **Google Play**, store it locally as normalized JSON/CSV, and get a first-pass analysis — without any store credentials.

- Climbs an **efficiency ladder**: Apple's public RSS JSON (iOS) → `google-play-scraper` (Android, full history) → App Store Connect API (only if you have creds) → browser scraping as a genuine last resort.
- Ships three runnable scripts (`scrape-ios.mjs`, `scrape-android.mjs`, `combine-and-analyze.mjs`) that take app identifiers via env vars, dedup across country/locale storefronts, and emit a combined CSV.
- First-pass analysis out of the box: **rating distribution**, **trend by year**, and **complaint-theme buckets** over the negative reviews.

Great for competitive research, ASO, and turning a competitor's top complaints into your own differentiation.

### `meeting-recorder`
A **local, bot-free meeting recorder** for Linux plus the skill that turns recordings into meeting notes:

- `record [-es|-ca] [-p profile] title` captures your mic (left channel) and what you hear (right channel) from PipeWire/PulseAudio into a tiny Opus file. Works with any call app; nobody is notified, no bot joins.
- `transcribe` runs **whisper.cpp on-device** (Vulkan GPU build with CPU fallback, `large-v3-turbo`), labels who said what from the stereo split, skips silence (silero VAD). ~15–20 min per meeting hour on an integrated GPU.
- The skill ("process my recordings") transcribes what is pending, writes a summary **in the language spoken**, finds the calendar event (Gmail invitations or a Calendar connector), then **asks** before creating either a CRM entry (Airtable) or a Google Doc in the right Drive folder, and again before sharing it read-only with the attendees. Work vs personal **profiles** decide where things go.
- Audio and transcripts never leave the machine. Drive access borrows your `rclone` token; no other credential is stored.

Linux only (PipeWire or PulseAudio). `scripts/install.sh` installs everything; `config.example.json` shows the private config.

## Install

In Claude Code:

```
/plugin marketplace add daniel-lopez-puig/claude-skills
/plugin install mobile-web-correctness@claude-skills
/plugin install browser-modes@claude-skills
/plugin install app-review-scraper@claude-skills
/plugin install meeting-recorder@claude-skills
```

That's it — the skills are now available and Claude will pull them in when relevant.

## Contributing

PRs very welcome — new skills, and especially **new entries** for recurring mobile bugs you've hit in `mobile-web-correctness`. See [CONTRIBUTING.md](./CONTRIBUTING.md). The whole point is for the checklist to get better as more people add the traps they've stepped on.

## License

[MIT](./LICENSE)
