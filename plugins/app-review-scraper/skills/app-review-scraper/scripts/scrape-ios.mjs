// iOS App Store review scraper via Apple's public RSS JSON. No deps, no auth.
// Reviews are per-country; loops a broad country list × pages 1..10 (Apple's RSS cap)
// and dedups by review_id.
//
// Usage:  IOS_APP_ID=691984809 [OUT=./data] [COUNTRIES=es,us,fr] node scrape-ios.mjs
import { writeFile, mkdir } from "node:fs/promises";

const APP_ID = process.env.IOS_APP_ID;
if (!APP_ID) { console.error("Set IOS_APP_ID (the numeric id from the store URL)."); process.exit(1); }
const OUT = process.env.OUT || "./data";
const COUNTRIES = (process.env.COUNTRIES
  || "es,ad,mx,ar,cl,co,pe,us,gb,fr,it,de,pt,ie,nl,be,ch,br,ec,uy,py,ve")
  .split(",").map((c) => c.trim()).filter(Boolean);
const MAX_PAGE = 10;

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const reviews = new Map();

async function fetchPage(country, page) {
  const url = `https://itunes.apple.com/${country}/rss/customerreviews/page=${page}/id=${APP_ID}/sortby=mostrecent/json`;
  const res = await fetch(url, { headers: { "User-Agent": "Mozilla/5.0 (review-research)" } });
  if (!res.ok) return null;
  return (await res.json())?.feed?.entry ?? null;
}

for (const country of COUNTRIES) {
  let got = 0;
  for (let page = 1; page <= MAX_PAGE; page++) {
    let entries;
    try { entries = await fetchPage(country, page); }
    catch (e) { console.error(`  ${country} p${page} error: ${e.message}`); break; }
    if (!entries) break;
    const list = Array.isArray(entries) ? entries : [entries];
    const real = list.filter((e) => e?.["im:rating"]); // first page-1 entry is app metadata
    if (real.length === 0) break;
    for (const e of real) {
      const id = e.id?.label;
      if (!id || reviews.has(id)) continue;
      reviews.set(id, {
        store: "ios", country, review_id: id,
        rating: Number(e["im:rating"]?.label) || null,
        title: e.title?.label ?? null,
        body: e.content?.label ?? null,
        author: e.author?.name?.label ?? null,
        date: e.updated?.label ?? null,
        app_version: e["im:version"]?.label ?? null,
        helpful_count: Number(e["im:voteCount"]?.label) || 0,
      });
      got++;
    }
    await sleep(250);
  }
  if (got) console.log(`${country}: +${got} (total ${reviews.size})`);
}

await mkdir(OUT, { recursive: true });
const all = [...reviews.values()];
await writeFile(`${OUT}/ios-reviews.json`, JSON.stringify(all, null, 2));
console.log(`\nDONE iOS: ${all.length} unique reviews -> ${OUT}/ios-reviews.json`);
