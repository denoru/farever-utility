/* Farever boss drop tracker - data scraper (fareverdb.com)
 * Scrapes: boss list (+world boss), each boss unit page (full drops array from the
 * RSC payload), boss portraits from /api/raw/unit, and per-class item id sets.
 * Keeps only drops that are Legendary OR Mount/Glider.
 * Output: data/bosses.json
 */
const fs = require('fs');
const path = require('path');

const BASE = 'https://fareverdb.com';
const OUT = path.join(__dirname, 'data', 'bosses.json');
const DELAY = 200;

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function get(url) {
  await sleep(DELAY);
  const res = await fetch(url, { headers: { 'user-agent': 'boss-drop-tracker/1.0 (personal tool)' } });
  if (!res.ok) throw new Error(`${res.status} ${url}`);
  return res.text();
}

async function getJson(url) {
  const t = await get(url);
  return JSON.parse(t);
}

// Pull every "drops":[...] array out of the Next.js RSC payload (JS-string escaped)
function extractDropsArrays(html) {
  const out = [];
  const marker = '\\"drops\\":[';
  let idx = 0;
  while ((idx = html.indexOf(marker, idx)) !== -1) {
    const start = idx + marker.length - 1; // position of '['
    let depth = 0, i = start, inStr = false;
    for (; i < html.length; i++) {
      const ch = html[i];
      // Everything sits inside a Next.js RSC JS string: quotes are \" and
      // backslashes are doubled. \" toggles the decoded JSON string state,
      // any other escape has no structural meaning.
      if (ch === '\\') {
        if (html[i + 1] === '"') inStr = !inStr;
        i++;
        continue;
      }
      if (ch === '"') { inStr = !inStr; continue; }
      if (inStr) continue;
      if (ch === '[' || ch === '{') depth++;
      else if (ch === ']' || ch === '}') {
        depth--;
        if (depth === 0) { i++; break; }
      }
    }
    const raw = html.slice(start, i);
    try {
      const text = JSON.parse('"' + raw + '"'); // unescape the JS string layer
      const arr = JSON.parse(text);
      if (Array.isArray(arr)) out.push(arr);
    } catch (e) {
      console.warn('  ! drops parse failed:', e.message);
    }
    idx = i;
  }
  return out;
}

function itemTypeFromIcon(iconPath) {
  if (!iconPath) return null;
  const parts = iconPath.split('/');
  // UI/Portraits/Items/<Type>/<file>
  if (parts.length >= 4 && parts[0] === 'UI' && parts[2] === 'Items') return parts[3];
  return null;
}

function isTracked(rarity, type, kind, weaponType) {
  if (rarity && rarity.toLowerCase() === 'legendary') return true;
  if (kind === 'mount' || kind === 'glider') return true;
  if (type === 'Mount' || type === 'GearGlider') return true;
  if (weaponType) return true;
  return false;
}

function dropCategory(rarity, type, kind, weaponType) {
  if (kind === 'mount' || type === 'Mount') return 'mount';
  if (kind === 'glider' || type === 'GearGlider') return 'glider';
  if (rarity && rarity.toLowerCase() === 'legendary') return 'legendary';
  if (weaponType) return 'weapon';
  return 'other';
}

// itemType sheet -> inherit chain (CastleDB). Cached in data/item-types.json.
async function fetchTypeInherits() {
  const cachePath = path.join(__dirname, 'data', 'item-types.json');
  const html = await get(`${BASE}/sheet/itemType`);
  const types = [...new Set([...html.matchAll(/href="\/sheet\/itemType\/([A-Za-z0-9_]+)"/g)].map((m) => m[1]))];
  let map = {};
  if (fs.existsSync(cachePath)) {
    try { map = JSON.parse(fs.readFileSync(cachePath, 'utf8')); } catch (e) { map = {}; }
  }
  let fetched = 0;
  for (const t of types) {
    if (Object.prototype.hasOwnProperty.call(map, t)) continue;
    let inherit = null;
    try {
      const row = await get(`${BASE}/sheet/itemType/${t}`);
      const m = row.match(/inherit(?:&quot;|\\+")?\s*:\s*(?:&quot;|\\+")([A-Za-z0-9_]+)/);
      if (m) inherit = m[1];
      fetched++;
    } catch (e) {
      console.warn(`  ! itemType ${t}: ${e.message}`);
      continue;
    }
    map[t] = inherit;
  }
  if (fetched) {
    fs.mkdirSync(path.dirname(cachePath), { recursive: true });
    fs.writeFileSync(cachePath, JSON.stringify(map, null, 2));
  }
  console.log(`  item types: ${Object.keys(map).length} (${fetched} fetched)`);
  return map;
}

function typeChain(inherits, t) {
  const out = [];
  let cur = t;
  while (cur && out.indexOf(cur) === -1) { out.push(cur); cur = inherits[cur]; }
  return out;
}

// Every itemId that is a weapon (type chain passes through "Weapon") -> its itemType.
// Weapons roll up to Legendary (rarityRules.weaponMaxRarity), unlike gear (Epic).
async function fetchWeaponItems(inherits) {
  const weaponTypes = Object.keys(inherits).filter((t) => typeChain(inherits, t).indexOf('Weapon') !== -1);
  const byItem = new Map();
  for (const t of weaponTypes) {
    let page = 1;
    for (;;) {
      const html = await get(`${BASE}/items?type=${t}&page=${page}`);
      const links = [...new Set([...html.matchAll(/href="\/items\/([A-Za-z0-9_]+)"/g)].map((m) => m[1]))];
      let newCount = 0;
      for (const id of links) {
        if (!byItem.has(id)) { byItem.set(id, t); newCount++; }
      }
      const hasNext = html.includes(`type=${t}&page=${page + 1}`);
      if (!hasNext || newCount === 0 || page > 20) break;
      page++;
    }
  }
  console.log(`  weapon items: ${byItem.size} across ${weaponTypes.length} weapon types`);
  return byItem;
}

async function fetchBossIds() {
  const ids = new Map(); // id -> Set(categories)
  for (const cat of ['boss', 'world-boss']) {
    let page = 1;
    for (;;) {
      const url = `${BASE}/units?category=${cat}&page=${page}`;
      const html = await get(url);
      const links = [...html.matchAll(/href="\/units\/([A-Za-z0-9_]+)"/g)].map((m) => m[1]);
      let newCount = 0;
      for (const id of links) {
        if (!ids.has(id)) { ids.set(id, new Set()); newCount++; }
        ids.get(id).add(cat);
      }
      const hasNext = html.includes(`category=${cat}&page=${page + 1}`);
      console.log(`  ${cat} page ${page}: ${links.length} links (${newCount} new)`);
      if (!hasNext || newCount === 0 || page > 20) break;
      page++;
    }
  }
  return ids;
}

async function fetchClassSets() {
  const classes = {};
  for (const cls of ['Warrior', 'Rogue', 'Mage', 'Priest']) {
    const set = new Set();
    let page = 1;
    for (;;) {
      const html = await get(`${BASE}/items?class=${cls}&page=${page}`);
      const links = [...html.matchAll(/href="\/items\/([A-Za-z0-9_]+)"/g)].map((m) => m[1]);
      let newCount = 0;
      for (const id of links) if (!set.has(id)) { set.add(id); newCount++; }
      const hasNext = html.includes(`class=${cls}&page=${page + 1}`);
      if (!hasNext || newCount === 0 || page > 30) break;
      page++;
    }
    classes[cls] = [...set];
    console.log(`  class ${cls}: ${set.size} items`);
  }
  return classes;
}

async function main() {
  console.log('Fetching boss list...');
  const bossIds = await fetchBossIds();
  console.log(`Total unique bosses: ${bossIds.size}`);

  console.log('Fetching class item sets...');
  const classes = await fetchClassSets();

  console.log('Fetching item type sheet...');
  const inherits = await fetchTypeInherits();
  console.log('Fetching weapon items...');
  const weaponItems = await fetchWeaponItems(inherits);

  const bosses = [];
  for (const [id, cats] of bossIds) {
    let raw = null;
    try {
      raw = await getJson(`${BASE}/api/raw/unit/${id}`);
    } catch (e) {
      console.warn(`  ! raw unit failed for ${id}: ${e.message}`);
    }

    let html = '';
    try {
      html = await get(`${BASE}/units/${id}`);
    } catch (e) {
      console.warn(`  ! unit page failed for ${id}: ${e.message}`);
      continue;
    }

    const all = extractDropsArrays(html).flat();
    const seen = new Set();
    const unique = [];
    for (const d of all) {
      if (!d || !d.itemId) continue;
      const key = `${d.itemId}|${d.sourceTable || ''}|${d.kind || ''}|${(d.modes || []).join(',')}`;
      if (seen.has(key)) continue;
      seen.add(key);
      unique.push(d);
    }

    const tracked = [];
    const seenTracked = new Set();
    for (const d of unique) {
      const type = itemTypeFromIcon(d.itemIcon);
      const rarity = d.itemRarity || null;
      const kind = d.kind || null;
      const weaponType = weaponItems.get(d.itemId) || null;
      if (!isTracked(rarity, type, kind, weaponType)) continue;
      if (seenTracked.has(d.itemId)) continue;
      seenTracked.add(d.itemId);
      const category = dropCategory(rarity, type, kind, weaponType);
      tracked.push({
        itemId: d.itemId,
        name: d.itemName || d.itemId,
        icon: d.itemIcon ? `https://cdn.fareverdb.com/${d.itemIcon}` : null,
        rarity,
        type,
        kind,
        itemType: weaponType || type,
        category,
        maxRarity: category === 'weapon' || category === 'legendary' ? 'Legendary' : null,
        proba: typeof d.proba === 'number' ? d.proba : null,
        source: d.sourceTable || null,
        modes: d.modes || null,
      });
    }

    const gfx = raw && raw.gfx && raw.gfx.file;
    const boss = {
      id,
      name: (raw && raw.texts && raw.texts.name) || id,
      level: raw ? raw.lvl : null,
      type: raw ? raw.type : null,
      faction: raw ? raw.faction : null,
      category: cats.has('world-boss') ? 'world-boss' : 'boss',
      image: gfx ? `https://cdn.fareverdb.com/${gfx}` : null,
      totalDrops: unique.length,
      drops: tracked,
    };
    bosses.push(boss);
    console.log(`  ${boss.name} (${id}): ${unique.length} drops -> ${tracked.length} tracked`);
  }

  bosses.sort((a, b) => (a.level || 0) - (b.level || 0) || a.name.localeCompare(b.name));

  // Collapse boss clones (e.g. Nightqueen true/false clones) into one entry.
  const merged = new Map();
  for (const b of bosses) {
    const key = b.name;
    if (!merged.has(key)) { merged.set(key, { ...b, ids: [b.id], drops: [...b.drops] }); continue; }
    const m = merged.get(key);
    m.ids.push(b.id);
    m.level = Math.max(m.level || 0, b.level || 0);
    m.totalDrops = Math.max(m.totalDrops, b.totalDrops);
    const seen = new Set(m.drops.map((d) => d.itemId));
    for (const d of b.drops) {
      if (seen.has(d.itemId)) continue;
      seen.add(d.itemId);
      m.drops.push(d);
    }
  }
  const finalBosses = [...merged.values()];

  const out = {
    generated: new Date().toISOString(),
    source: 'fareverdb.com (game data v0.2.0)',
    filter: 'legendary OR mount/glider OR weapon (upgrade path to Legendary)',
    bosses: finalBosses,
    classes,
  };
  fs.mkdirSync(path.dirname(OUT), { recursive: true });
  fs.writeFileSync(OUT, JSON.stringify(out));
  fs.writeFileSync(path.join(path.dirname(OUT), 'bosses.js'), `window.FAREVER_BOSS_DATA = ${JSON.stringify(out)};\n`);

  const totalDrops = finalBosses.reduce((n, b) => n + b.drops.length, 0);
  const uniqueItems = new Set(finalBosses.flatMap((b) => b.drops.map((d) => d.itemId)));
  const missingImages = finalBosses.filter((b) => !b.image).map((b) => b.id);
  console.log(`\nWrote ${OUT}`);
  console.log(`Bosses: ${finalBosses.length} | tracked drop entries: ${totalDrops} | unique items: ${uniqueItems.size}`);
  if (missingImages.length) console.log('Bosses without portrait:', missingImages.join(', '));
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
