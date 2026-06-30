---
name: mobile-web-correctness
description: Use when building or editing any web UI, CSS, or responsive layout — chat, overlays, modals, bottom sheets, drawers, forms — or fixing iOS/Safari/Android bugs around the on-screen keyboard, input auto-zoom, viewport height, safe areas, or position:fixed overlays that let the page show through. Apply BEFORE shipping mobile-facing UI, not after a device report.
---

# Mobile Web Correctness

## Overview

Mobile browsers (especially iOS Safari) have deterministic, well-known quirks that desktop and headless testing never surface. Shipping a web UI without accounting for them reads as carelessness — they are not edge cases. **Apply this checklist up front whenever you build or touch a mobile-facing surface.** Each item is: symptom → rule → fix.

## When to use

- Building/editing a chat, overlay, modal, bottom sheet, drawer, dialog, or any `position:fixed` UI.
- Any `<input>`/`<textarea>`/`<select>`, form, or composer.
- Any full-height/viewport layout (`100vh`, sticky bottom bars).
- Fixing a reported iOS/Android bug: zoom on focus, keyboard covers input, page bleeds through an overlay, layout jumps, content under the notch/home bar.

Skip only for purely desktop/internal tooling with no mobile surface.

## The checklist

### 1. Inputs ≥ 16px font-size (iOS auto-zoom)
**Symptom:** Tapping an input zooms the whole page in. **Rule:** every focusable form control needs `font-size ≥ 16px`. **Watch:** when a component is moved into a portal/different subtree, descendant-scoped overrides (e.g. `.someWrapper .input`) stop applying — the *base* rule must already be safe. Do NOT "fix" it with `maximum-scale=1` on the viewport meta (breaks pinch-zoom / accessibility).
```css
.myInput { font-size: 16px; } /* never < 16px on mobile */
```
**Enforce it ONCE, globally — not per component.** Fixing inputs one-by-one (or in one app's shared `<Input>`) misses native `<select>`/`<textarea>`, third-party widgets, and *entire other apps* in a monorepo — the bug just resurfaces on the next field someone adds. Add a single mobile-only floor on every focusable control so nothing can slip through:
```css
@media (max-width: 639px) {
  input:not([type='checkbox']):not([type='radio']):not([type='range']), textarea, select {
    font-size: max(16px, var(--control-font, 0px)); /* floor, not fixed: large controls opt out via --control-font */
  }
}
```
`max()` makes it a *floor*, so an intentionally-large field (OTP, title) keeps its size by setting `--control-font`. Put the rule **unlayered** so it beats Tailwind's layered `text-*` utilities. **Beware UI-zoom knobs:** if the app scales itself with CSS `zoom`/`transform` (e.g. a readability `--ui-scale`) and *disables* that scaling on phones, the control's literal font-size is what iOS measures — a `text-sm` (14px) field zooms even though it looked ≥16px on desktop. **Verify by reading `getComputedStyle(el).fontSize` on a real rendered field at a <640px viewport** (headless is fine for this measurement), not by eyeballing.

### 2. On-screen keyboard → use `visualViewport`, not `100vh`
**Symptom:** keyboard covers the input, or a docked composer floats behind it. **Rule:** the keyboard shrinks the *visual* viewport but not the *layout* viewport (what `position:fixed` and `100vh` use). For a full-screen overlay with a docked input, pin it to `window.visualViewport` with **top + height (never `bottom`)** and listen to `resize`/`scroll`.
```js
const vv = window.visualViewport;
const apply = () => { el.style.height = `${vv.height}px`; el.style.top = `${vv.offsetTop}px`; };
apply(); vv.addEventListener("resize", apply); vv.addEventListener("scroll", apply);
```

### 3. Fixed overlays → portal to `document.body`
**Symptom:** on mobile the page "bleeds through" behind a full-screen overlay (works on desktop). **Cause:** ANY ancestor with `transform` / `filter` / `will-change` / `perspective` / `contain` turns `position:fixed` into "fixed relative to that ancestor", not the viewport. **Fix:** render the overlay at the document root (e.g. React `createPortal(node, document.body)`) and add a full-viewport backdrop behind it so nothing can show through.

### 4. iOS scroll-lock = `position:fixed` on body
**Symptom:** the page scrolls behind the open overlay / into the keyboard gap. **Rule:** `overflow:hidden` on `body` is ignored by iOS Safari. Pin the body and restore scroll on close.
```js
const y = window.scrollY;
body.style.position = "fixed"; body.style.top = `-${y}px`; body.style.width = "100%";
// on close: clear those, then window.scrollTo(0, y);
```

### 5. Use `dvh`, not `vh`
`100vh` includes the area behind the iOS URL bar and jumps as it shows/hides. Use `100dvh` (dynamic) for static full-height; use `visualViewport` (item 2) when the keyboard is involved. **Exception — installed iOS PWA:** under a black-translucent status bar the document is shifted up, so `dvh`/`svh`/`%` are *also* short and only `100vh` fills the screen; see item 9.

### 6. Safe-area insets
Docked bars/composers need `padding-bottom: max(12px, env(safe-area-inset-bottom))` (and `safe-area-inset-top` under the notch) so content clears the home indicator / notch.

### 7. Touch ergonomics
Tap targets ≥ ~44px. Drag handles (resizable sheets) need `touch-action: none` so the gesture doesn't scroll the page. Native bottom sheets snap to points (e.g. peek / half / full) — don't ship free-drag-only.

### 8. Input hints
Set `inputmode` (e.g. `email`, `tel`, `numeric`), `enterkeyhint`, and `autocomplete` so the right keyboard + Enter label appear.

### 9. Installed iOS PWA: white strip at the bottom + the `display-mode` trap
**Symptom:** in a **Home-Screen-installed** PWA (not a Safari tab), a white strip sits *below* the bottom tab bar / the app shell stops short of the screen bottom. Fine in the browser; only the installed app is wrong. **Cause:** with `viewport-fit=cover` + `apple-mobile-web-app-status-bar-style: black-translucent`, iOS shifts the document up by the top inset, so `height:100%`, `100dvh`, **and** `100svh` all resolve SHORT (e.g. 873 of a 932px screen — they exclude that region); only `100vh`/`100lvh` equal the full screen. **Rule:** fill the shell with `100vh` *in standalone only* (in a browser tab `100vh` is the too-tall large viewport — keep `100%`/`dvh` there).

**The trap that hides this for hours:** the obvious scope `@media (display-mode: standalone)` is **silently dead on iOS** — a home-screen PWA reports `navigator.standalone === true` but does **not** match that media feature, so any CSS gated on it never applies and nothing errors (the shell just stays short). Detect standalone in **JS**, not CSS:
```html
<!-- synchronous, in <head> before first paint → no flash of the short layout -->
<script>try{if(navigator.standalone===true||matchMedia('(display-mode: standalone)').matches)document.documentElement.classList.add('is-standalone')}catch(e){}</script>
```
```css
html.is-standalone, html.is-standalone body, html.is-standalone #root { height: 100vh !important; }
```
Size **every** `height:100%` ancestor (html *and* body *and* #root) — a shorter one with `overflow:hidden` clips the tall child. Keep the bar's own `padding-bottom: env(safe-area-inset-bottom)` (item 6) for home-indicator clearance. **Don't** use `calc(100% + env(safe-area-inset-top))` — it *compounds* across the nested `height:100%` elements and overshoots the bar off-screen. (`matchMedia` is ORed in for Android/desktop installs, where `display-mode` actually works.)

**You cannot reproduce this headless** — `env()` insets are 0 in a Linux/headless browser, so standalone rendering is invisible there. **Instrument the device:** ship a tiny diagnostic page that prints the real values — `navigator.standalone`, `matchMedia('(display-mode: standalone)').matches`, `env(safe-area-inset-*)`, and `100%` / `100dvh` / `100svh` / `100vh` / `100lvh` / `innerHeight` / `screen.height` — and have the user screenshot it from the **installed** PWA. The tells are unmistakable: `matchMedia` is `false` while `navigator.standalone` is `true`, and `100vh` ≠ `100dvh`. Measuring beats guessing: this bug ate **six** CSS-only attempts (clamp the inset, env() padding, `calc(100%+env-top)`, `100dvh`, `@media(display-mode)`-scoped `100vh`) — every one assumed it was *applying*; it wasn't, because the media query never matched.

## How to verify (be honest about it)
Headless browsers (Playwright/Puppeteer) at a phone viewport catch layout, snap handles, and the portal target — but they do **NOT** emulate the soft keyboard, `visualViewport` resize, or iOS input-zoom. Those need a **real device or the iOS Simulator**. When you can't test the keyboard, say so explicitly instead of claiming it's verified.

## Common mistakes
| Mistake | Fix |
|---|---|
| Input at 14–15px "looks fine on desktop" | 16px minimum (item 1) |
| `height: 100vh` on a full-screen layer | `100dvh` + visualViewport when keyboard is up |
| Fixed overlay rendered deep in the tree | portal to body + backdrop (item 3) |
| `overflow:hidden` to lock scroll on iOS | `position:fixed` body lock (item 4) |
| "Verified on mobile" (meaning headless) | headless ≠ keyboard; flag the gap |
| `@media (display-mode: standalone)` to scope an installed-iOS-PWA fix | dead on iOS (matches nothing); detect with `navigator.standalone` in JS → class (item 9) |
| White strip below a bar in the installed iOS PWA | fill the shell with `100vh` (not `%`/`dvh`/`svh`, which are short there), gated by a JS-set class (item 9) |

## Maintenance (keep this skill alive)
When a NEW recurring mobile bug is found, **append a numbered item** to "The checklist" in the same symptom → rule → fix shape (and a row to Common mistakes). Keep entries concrete and tied to a real failure. PRs welcome.

## References
- 16px rule: https://css-tricks.com/16px-or-larger-text-prevents-ios-form-zoom/
- VisualViewport API: https://developer.mozilla.org/en-US/docs/Web/API/VisualViewport
- iOS textbox zoom + viewport: https://weblog.west-wind.com/posts/2023/Apr/17/Preventing-iOS-Textbox-Auto-Zooming-and-ViewPort-Sizing
- 100vh jumps fix (URL bar + keyboard): https://dev.to/__8b11c872ed501135af2/fix-mobile-100vh-jumps-url-bar-keyboard-using-visualviewport-5h0h
- Installed iOS PWA bottom gap (status bar shift): https://dev.to/karmasakshi/make-your-pwas-look-handsome-on-ios-1o08
- `display-mode: standalone` not matching on iOS home-screen PWAs (use `navigator.standalone`): https://developer.mozilla.org/en-US/docs/Web/API/Navigator/standalone
