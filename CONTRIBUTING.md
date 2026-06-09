# Contributing

Thanks for helping! This repo is most useful when people add the real mobile traps they've hit.

## Add a checklist entry (the common case)

Edit `plugins/mobile-web-correctness/skills/mobile-web-correctness/SKILL.md`:

1. Add a numbered item under **The checklist** in the existing shape:
   **Symptom** (what the user sees) → **Rule** (the principle) → **Fix** (a short, copy-pasteable snippet).
2. Add a one-line row to the **Common mistakes** table.
3. Keep it concrete and tied to a real failure — no hypotheticals. Prefer the smallest correct fix.
4. Keep it framework-agnostic where possible (note the framework only if the fix is specific to it).

## Quality bar

- One excellent example beats many. Snippets should be runnable/adaptable, not pseudo-code.
- Don't duplicate an existing item — extend it instead.
- Cite a source (MDN, CSS-Tricks, a browser bug) when the behavior is non-obvious.

## Test it locally

```
/plugin marketplace add /absolute/path/to/your/clone
/plugin install mobile-web-correctness@claude-skills
```

Then start a task that should trigger it (e.g. "build a mobile bottom-sheet with an input") and confirm Claude pulls the skill in and applies your new entry.

## Adding a brand-new skill

Open an issue first to discuss scope. New skills go under `plugins/<name>/` with a `.claude-plugin/plugin.json` and `skills/<name>/SKILL.md`, and a new entry in `.claude-plugin/marketplace.json`.
