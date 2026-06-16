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

## Install

In Claude Code:

```
/plugin marketplace add daniel-lopez-puig/claude-skills
/plugin install mobile-web-correctness@claude-skills
/plugin install browser-modes@claude-skills
```

That's it — the skills are now available and Claude will pull them in when relevant.

## Contributing

PRs very welcome — especially **new entries** for recurring mobile bugs you've hit. See [CONTRIBUTING.md](./CONTRIBUTING.md). The whole point is for the checklist to get better as more people add the traps they've stepped on.

## License

[MIT](./LICENSE)
