---
name: browser-modes
description: Use BEFORE any browser automation / Playwright / web-testing / web-scraping task to pick the right browser mode — headless (default, invisible to the user), visible window (when the task needs login/auth, opened up front), or handover (attach to the user's real, already-open Chrome, ONLY when they explicitly ask). Also use whenever you're about to take a browser screenshot or describe what's "on screen" so you never narrate a headless browser as if the user can see it.
---

# Browser Modes

## The one rule that prevents the recurring confusion

**The default browser is headless — there is NO window, and the user CANNOT see it.**

When you run the default browser tools, nothing appears on the user's screen. Do not say "as you can see in the browser", "look at the page", or anything implying the user is watching. If you want them to see something, **take a screenshot and share it explicitly** ("Here's what the page looks like: …"). Treat the headless browser as a thing only *you* can observe.

The user can only see the browser in **visible** mode (you opened a window) or **handover** mode (their own Chrome). Know which mode you're in before you narrate.

## Pick the mode

```
Did the user explicitly ask you to use/see/take over THEIR browser?
  ("hand over", "the tab I have open", "use my Chrome", "I'm logged in here, continue")
        │ yes ──────────────► HANDOVER  (server: browser-handover)
        │ no
        ▼
Will the task need authentication or a logged-in session?
  Either the user said so, OR you can tell from the prompt:
   • "log into…", "my account / my dashboard / my orders"
   • posting / publishing / buying / sending AS the user
   • a site that gates behind login (Gmail, bank, social, internal tools, paywalls)
   • it will hit a captcha / cookie / consent wall you must clear interactively
        │ yes ──────────────► VISIBLE   (server: browser-auth)  ← open it UP FRONT
        │ no
        ▼
                              HEADLESS  (server: browser)  ← default
```

**Predict, don't faceplant.** If you can tell from the prompt you'll need a login, start in VISIBLE mode immediately. Don't run headless, hit a login wall, and only then switch — that wastes a round trip and loses context.

When you're genuinely unsure whether auth is needed, **ask the user one quick question** rather than guessing.

## HEADLESS — the default (`browser` server, `mcp__browser__*`)

Fast, invisible, throwaway profile. Use for: reading public pages, scraping, checking your own deploy/preview URLs, rendering checks, anything with no login. Remember the one rule above — share screenshots, never imply the user sees it.

## VISIBLE — auth / login needed (`browser-auth` server, `mcp__browser_auth__*`)

Opens a **real Chrome window** on a persistent profile, so logins survive between runs. Use when the task needs the user's session.

- Tell the user up front: *"A Chrome window will open — please log in / complete the captcha when it appears, then tell me to continue."*
- The profile persists, so once they've logged into a site there, future runs are already authenticated.
- This is a **separate** window from their everyday Chrome — it is NOT their main browsing session (that's handover).

## HANDOVER — drive the user's real Chrome (`browser-handover` server) — only when asked

Attaches over the DevTools port to the user's **actual, visible, everyday Chrome**, so you can read and drive the exact tab they're looking at. Only enter this mode when the user explicitly asks for it.

**Before attaching:** ensure the debug Chrome is up — run `chrome-agent` (it's idempotent; starts the synced debug profile with the port if it isn't already running). Then use the `browser-handover` tools.

**First time ever** (the debug profile / port / server don't exist yet): run the one-time setup in *Setup → Handover* below. Warn the user it relaunches their Chrome into a Sync'd profile (their tabs reopen); after that, every future handover is instant.

### Etiquette when driving the user's real browser (non-negotiable)

You are inside their logged-in session. Be a careful guest:

- **Work in a NEW tab** you open. Do not navigate the user's current tab away — unless they explicitly pointed you *at* that tab.
- **Never touch unrelated logged-in tabs** (their email, bank, work apps) beyond what the task requires.
- **Confirm before anything destructive or irreversible** — sending, deleting, purchasing, posting, changing settings. State exactly what you're about to do and wait for a yes.
- **Don't exfiltrate** cookies, tokens, or session data.
- **Say which tab you're acting in** as you go, so they can follow along.

---

## Setup (one-time, for reproducing this on a machine)

This skill assumes three MCP servers and one helper script. On the author's machine they already exist; to set them up elsewhere (Linux shown; adapt paths for your OS / home dir):

### Servers + plugin

```bash
# Default headless workhorse
claude mcp add -s user browser      -- npx @playwright/mcp@latest --headless --isolated
# Visible window for auth/login (real Chrome channel, persistent profile)
claude mcp add -s user browser-auth -- npx @playwright/mcp@latest --browser chrome \
  --user-data-dir "$HOME/.config/cwp-playwright-auth"

# Optional but recommended: disable the stock Playwright plugin so there isn't a
# second, ambiguously-named browser server. Our `browser` server replaces it and
# is pinned headless, immune to plugin-default drift.
claude plugin disable playwright@claude-plugins-official
```

### Helper script `chrome-agent`

Put an executable `chrome-agent` on your PATH (e.g. `~/.local/bin/chrome-agent`) that
idempotently ensures a debug-enabled Chrome is running. Key points it must encode:

- Use a **dedicated `--user-data-dir`** (e.g. `~/.config/google-chrome-agent`). Since
  Chrome 136 the `--remote-debugging-port` flag is **silently ignored on the default
  profile** — the port only works on a non-default profile dir.
- Launch with `--remote-debugging-port=9222 --remote-debugging-address=127.0.0.1`
  (localhost-only — no network exposure) and `--restore-last-session`.
- Check `http://127.0.0.1:9222/json/version` first; if it answers, do nothing.

### Handover (deferred until the user first asks)

The `browser-handover` server and the debug profile are created the first time the
user wants handover, so nothing changes about their daily Chrome until they opt in:

1. **Launch the debug profile:** `chrome-agent` (creates `~/.config/google-chrome-agent`).
2. **Sync it once:** have the user sign into Chrome Sync in that window, so their
   bookmarks / passwords / extensions appear and it feels like their normal Chrome.
3. **Make it the daily driver** so any tab they later open is handover-ready. Create a
   user-level launcher override at `~/.local/share/applications/google-chrome.desktop`
   (takes precedence over the system one, survives Chrome updates, keep the same Name/Icon)
   whose `Exec` lines point at the debug profile + port, e.g.:
   `Exec=/usr/bin/google-chrome-stable --user-data-dir=/home/<user>/.config/google-chrome-agent --remote-debugging-port=9222 --remote-debugging-address=127.0.0.1 %U`
   (`.desktop` `Exec` does not expand `$HOME` — hardcode the absolute path.)
4. **Add the attach server:**
   `claude mcp add -s user browser-handover -- npx @playwright/mcp@latest --cdp-endpoint http://127.0.0.1:9222`

After this one-time setup, handover is: run `chrome-agent` → use `browser-handover` tools.

**Security note:** in handover mode the DevTools port is open on `127.0.0.1` whenever that
Chrome runs. Any local process can connect to it. On a single-user dev machine this is
standard and low-risk, but it's a real surface — don't enable it on shared machines.
