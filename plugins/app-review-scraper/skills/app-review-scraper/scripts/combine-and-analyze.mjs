// Merge iOS + Android review JSON into a combined dataset (JSON + CSV) and print a
// first-pass analysis: rating distribution, trend by year, complaint themes.
//
// Usage:  [OUT=./data] node combine-and-analyze.mjs   (reads ios-reviews.json + android-reviews.json from OUT)
import { readFile, writeFile } from "node:fs/promises";

const OUT = process.env.OUT || "./data";
const read = async (f) => { try { return JSON.parse(await readFile(`${OUT}/${f}`)); } catch { return []; } };
const ios = await read("ios-reviews.json");
const android = await read("android-reviews.json");

const all = [...ios, ...android].map((r) => ({
  store: r.store, country: r.country ?? "", lang: r.lang ?? "",
  review_id: r.review_id, rating: r.rating ?? "",
  title: (r.title ?? "").replace(/\s+/g, " ").trim(),
  body: (r.body ?? "").replace(/\s+/g, " ").trim(),
  author: (r.author ?? "").replace(/\s+/g, " ").trim(),
  date: r.date ?? "", app_version: r.app_version ?? "", helpful_count: r.helpful_count ?? 0,
}));

await writeFile(`${OUT}/reviews-combined.json`, JSON.stringify(all, null, 2));

const cols = ["store","country","lang","review_id","rating","title","body","author","date","app_version","helpful_count"];
const esc = (v) => { const s = String(v ?? ""); return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s; };
await writeFile(`${OUT}/reviews-combined.csv`,
  [cols.join(","), ...all.map((r) => cols.map((c) => esc(r[c])).join(","))].join("\n"));

// ---------- Analysis ----------
const pct = (n, d) => `${n} (${d ? ((n / d) * 100).toFixed(1) : 0}%)`;
console.log(`\n=== TOTALS ===\nTotal: ${all.length}  (iOS ${ios.length}, Android ${android.length})`);

console.log(`\n=== RATING DISTRIBUTION ===`);
const dist = {}; let sum = 0, rated = 0;
for (const r of all) { const s = Number(r.rating); if (s) { dist[s] = (dist[s]||0)+1; sum += s; rated++; } }
for (let s = 5; s >= 1; s--) console.log(`  ${s}: ${pct(dist[s]||0, rated)}`);
console.log(`  avg: ${rated ? (sum/rated).toFixed(2) : "n/a"} (n=${rated})`);

console.log(`\n=== TREND BY YEAR (avg, count) ===`);
const byYear = {};
for (const r of all) { const y = (r.date||"").slice(0,4); const s = Number(r.rating); if (y && s){ (byYear[y] ??= {sum:0,n:0}); byYear[y].sum+=s; byYear[y].n++; } }
for (const y of Object.keys(byYear).sort()) console.log(`  ${y}: ${(byYear[y].sum/byYear[y].n).toFixed(2)} (n=${byYear[y].n})`);

// Tune these regexes to the app's review language(s). Defaults cover ES/CA/EN.
const THEMES = {
  "performance/slow": /\b(lent|lenta|lento|slow|tarda|carrega|carga|peta|crash|cuelga|penj|se cierra|se cae|bloque)/i,
  "login/auth": /\b(login|log in|inicia|contrasenya|contraseña|password|acced|no entra|no puedo entrar|sesi[oó]n|caduca)/i,
  "notifications": /\b(notific|avis|no me llega|no llega|no arriben|push)/i,
  "UX/confusing": /\b(complic|confus|lia|dif[ií]cil|intuitiv|engorros)/i,
  "bugs/errors": /\b(error|fallo|falla|fall[ae]|bug|no funciona|no va|deja de|mal funcion)/i,
  "broke-after-update": /\b(actualiz|actualitz|update|nova versi|tras actualizar)/i,
  "support": /\b(soporte|suport|atenci[oó]n|no responden|servei|servicio)/i,
};
const neg = all.filter((r) => Number(r.rating) >= 1 && Number(r.rating) <= 3);
console.log(`\n=== COMPLAINT THEMES (1-3 star, n=${neg.length}) ===`);
Object.entries(THEMES)
  .map(([k, re]) => [k, neg.filter((r) => re.test(`${r.title} ${r.body}`)).length])
  .sort((a, b) => b[1] - a[1])
  .forEach(([k, n]) => console.log(`  ${k.padEnd(20)} ${pct(n, neg.length)}`));

console.log(`\nWrote: ${OUT}/reviews-combined.json + .csv`);
