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

## Install

In Claude Code:

```
/plugin marketplace add daniel-lopez-puig/claude-skills
/plugin install mobile-web-correctness@claude-skills
```

That's it — the skill is now available and Claude will pull it in when relevant.

## Contributing

PRs very welcome — especially **new entries** for recurring mobile bugs you've hit. See [CONTRIBUTING.md](./CONTRIBUTING.md). The whole point is for the checklist to get better as more people add the traps they've stepped on.

## License

[MIT](./LICENSE)
