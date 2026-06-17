// Android (Google Play) review scraper via google-play-scraper. No auth.
// Paginates the FULL review history across lang/country combos, dedups by review id.
//
// Setup:  npm install google-play-scraper
// Usage:  ANDROID_PKG=org.clickedu.Clickedu [OUT=./data] [LOCALES=ca-es,es-es,en-us] node scrape-android.mjs
import gplay from "google-play-scraper";
import { writeFile, mkdir } from "node:fs/promises";

const APP_ID = process.env.ANDROID_PKG;
if (!APP_ID) { console.error("Set ANDROID_PKG (the id= package from the store URL)."); process.exit(1); }
const OUT = process.env.OUT || "./data";
const LOCALES = (process.env.LOCALES || "ca-es,es-es,en-es,es-mx,es-ar,en-us")
  .split(",").map((s) => s.trim()).filter(Boolean)
  .map((s) => { const [lang, country] = s.split("-"); return { lang, country }; });

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const reviews = new Map();

for (const { lang, country } of LOCALES) {
  let token = null, page = 0, got = 0;
  do {
    let res;
    try {
      res = await gplay.reviews({
        appId: APP_ID, lang, country,
        sort: gplay.sort.NEWEST, num: 200,
        paginate: true, nextPaginationToken: token,
      });
    } catch (e) { console.error(`  ${lang}-${country} p${page} error: ${e.message}`); break; }
    const data = res?.data ?? [];
    if (data.length === 0) break;
    for (const r of data) {
      if (!r.id || reviews.has(r.id)) continue;
      reviews.set(r.id, {
        store: "android", country, lang, review_id: r.id,
        rating: r.score ?? null,
        title: r.title ?? null,
        body: r.text ?? null,
        author: r.userName ?? null,
        date: r.date ?? null,
        app_version: r.version ?? null,
        helpful_count: r.thumbsUp ?? 0,
        reply: r.replyText ?? null,
      });
      got++;
    }
    token = res?.nextPaginationToken ?? null;
    page++;
    await sleep(300);
  } while (token && page < 200);
  console.log(`${lang}-${country}: +${got} (total ${reviews.size})`);
}

await mkdir(OUT, { recursive: true });
const all = [...reviews.values()];
await writeFile(`${OUT}/android-reviews.json`, JSON.stringify(all, null, 2));
console.log(`\nDONE Android: ${all.length} unique reviews -> ${OUT}/android-reviews.json`);
