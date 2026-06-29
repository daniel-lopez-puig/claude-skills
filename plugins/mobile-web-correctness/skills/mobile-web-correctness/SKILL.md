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
`100vh` includes the area behind the iOS URL bar and jumps as it shows/hides. Use `100dvh` (dynamic) for static full-height; use `visualViewport` (item 2) when the keyboard is involved.

### 6. Safe-area insets
Docked bars/composers need `padding-bottom: max(12px, env(safe-area-inset-bottom))` (and `safe-area-inset-top` under the notch) so content clears the home indicator / notch.

### 7. Touch ergonomics
Tap targets ≥ ~44px. Drag handles (resizable sheets) need `touch-action: none` so the gesture doesn't scroll the page. Native bottom sheets snap to points (e.g. peek / half / full) — don't ship free-drag-only.

### 8. Input hints
Set `inputmode` (e.g. `email`, `tel`, `numeric`), `enterkeyhint`, and `autocomplete` so the right keyboard + Enter label appear.

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

## Maintenance (keep this skill alive)
When a NEW recurring mobile bug is found, **append a numbered item** to "The checklist" in the same symptom → rule → fix shape (and a row to Common mistakes). Keep entries concrete and tied to a real failure. PRs welcome.

## References
- 16px rule: https://css-tricks.com/16px-or-larger-text-prevents-ios-form-zoom/
- VisualViewport API: https://developer.mozilla.org/en-US/docs/Web/API/VisualViewport
- iOS textbox zoom + viewport: https://weblog.west-wind.com/posts/2023/Apr/17/Preventing-iOS-Textbox-Auto-Zooming-and-ViewPort-Sizing
- 100vh jumps fix (URL bar + keyboard): https://dev.to/__8b11c872ed501135af2/fix-mobile-100vh-jumps-url-bar-keyboard-using-visualviewport-5h0h
