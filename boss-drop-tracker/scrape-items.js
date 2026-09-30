/* Builds the full item database + translations for the tracker.
 *   node scrape-items.js <cdbDir>
 * <cdbDir> must contain the extracted CastleDB XMLs (see extract-cdb.js):
 *   one EN export + translated exports (lang="pt-BR", lang="es", ...).
 * Sources: fareverdb.com (/items pages + /api/raw/item/<id>) and the game's cdb text exports.
 * Writes: data/items.json(+.js) and data/i18n.json(+.js).
 */
const fs = require('fs');
const path = require('path');

const CDB_DIR = process.argv[2];
if (!CDB_DIR) {
  console.error('Usage: node scrape-items.js <cdbDir>');
  process.exit(1);
}

const ROOT = __dirname;
const OUT_ITEMS = path.join(ROOT, 'data', 'items.json');
const OUT_I18N = path.join(ROOT, 'data', 'i18n.json');
const CACHE = path.join(require('os').tmpdir(), 'farever-items-raw-cache.json');
const UA = { 'User-Agent': 'Mozilla/5.0 (compatible; FareverTracker/1.0)' };
const DELAY = 160;
const EN_FP_KEY = 'inventory_confirm_drop';
const EN_FP = 'Are you sure you want to drop this [::item::]?';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function get(url) {
  let lastErr;
  for (let i = 0; i < 3; i++) {
    try {
      const res = await fetch(url, { headers: UA });
      if (res.status === 404) return null;
      if (!res.ok) throw new Error('HTTP ' + res.status);
      return await res.text();
    } catch (e) {
      lastErr = e;
      await sleep(500 * (i + 1));
    }
  }
  throw new Error(url + ' -> ' + lastErr.message);
}

// ---------------------------------------------------------------- phase 1: list
function parseCards(html) {
  const out = [];
  const re = /<a ([^>]*?)href="\/items\/([A-Za-z0-9_]+)"[^>]*?>([\s\S]*?)<\/a>/g;
  let m;
  while ((m = re.exec(html))) {
    const attrs = m[1];
    const id = m[2];
    const body = m[3];
    const rarAttr = (attrs.match(/data-rarity="([a-z]+)"/) || [])[1] ||
      (body.match(/data-rarity="([a-z]+)"/) || [])[1] || null;
    const name = (body.match(/<span[^>]*data-rarity[^>]*>([^<]*)<\/span>/) || [])[1] ||
      (body.match(/<span[^>]*>([^<]*)<\/span>/) || [])[1] || null;
    const icon = (body.match(/background-image:url\(&quot;(https:\/\/cdn\.fareverdb\.com\/[^&]+)&quot;\)/) || [])[1] || null;
    if (name) out.push({ id, name, rarity: rarAttr, icon });
  }
  return out;
}

async function listAllItems() {
  const byId = {};
  for (let p = 1; p <= 40; p++) {
    const url = p === 1 ? 'https://fareverdb.com/items' : 'https://fareverdb.com/items?page=' + p;
    const html = await get(url);
    if (html == null) break;
    const cards = parseCards(html);
    if (!cards.length) break;
    for (const c of cards) if (!byId[c.id]) byId[c.id] = c;
    process.stdout.write('list page ' + p + ': ' + cards.length + ' (total ' + Object.keys(byId).length + ')\n');
    await sleep(DELAY);
  }
  return byId;
}

// ---------------------------------------------------------------- phase 2: raw
async function loadRawCache() {
  try { return JSON.parse(fs.readFileSync(CACHE, 'utf8')); } catch (e) { return {}; }
}
function saveRawCache(cache) {
  fs.writeFileSync(CACHE, JSON.stringify(cache));
}

async function fetchRaw(ids) {
  const cache = await loadRawCache();
  let done = 0;
  for (const id of ids) {
    if (cache[id] !== undefined) { done++; continue; }
    const t = await get('https://fareverdb.com/api/raw/item/' + encodeURIComponent(id));
    cache[id] = t == null ? null : JSON.parse(t);
    done++;
    if (done % 100 === 0) {
      process.stdout.write('raw ' + done + '/' + ids.length + '\n');
      saveRawCache(cache);
    }
    await sleep(DELAY);
  }
  saveRawCache(cache);
  return cache;
}

// ---------------------------------------------------------------- phase 3: cdb
function decodeXml(s) {
  return s
    .replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"')
    .replace(/&apos;/g, "'").replace(/&#39;/g, "'").replace(/&#x27;/g, "'")
    .replace(/&amp;/g, '&');
}

function parseSheet(xml, sheet) {
  const a = xml.indexOf('<sheet name="' + sheet + '">');
  if (a === -1) return null;
  const b = xml.indexOf('</sheet>', a);
  const seg = xml.slice(a, b);
  const starts = [...seg.matchAll(/^ {8}<([A-Za-z0-9_]+)>[ \t]*$/gm)];
  const rows = {};
  for (let i = 0; i < starts.length; i++) {
    const id = starts[i][1];
    const from = starts[i].index;
    const to = i + 1 < starts.length ? starts[i + 1].index : seg.length;
    rows[id] = seg.slice(from, to);
  }
  return rows;
}

function field(rowXml, tag) {
  if (!rowXml) return null;
  const m = rowXml.match(new RegExp('<' + tag + '>([\\s\\S]*?)</' + tag + '>'));
  return m ? decodeXml(m[1].trim()) : null;
}

function loadCdbDir(dir) {
  const files = fs.readdirSync(dir).filter((f) => f.endsWith('.xml'));
  const entries = [];
  for (const f of files) {
    const xml = fs.readFileSync(path.join(dir, f), 'utf8');
    const lang = (xml.slice(0, 300).match(/lang="([^"]*)"/) || [])[1] || '?';
    const fp = field(parseSheet(xml, 'text') && parseSheet(xml, 'text')[EN_FP_KEY], 'value.text');
    entries.push({ file: f, lang, xml, isEn: fp === EN_FP });
  }
  const en = entries.find((e) => e.isEn) || null;
  if (!en) throw new Error('No English cdb found in ' + dir + ' (inventory_confirm_drop fingerprint mismatch)');
  const pick = (lang) => {
    const c = entries.filter((e) => e.lang === lang && !e.isEn);
    return c.length ? c[0] : null;
  };
  return {
    en,
    pt: pick('pt-BR'),
    es: pick('es'),
    entries,
  };
}

function cdbTexts(cdbFile, sheet, tags) {
  const rows = parseSheet(cdbFile.xml, sheet);
  const out = {};
  if (!rows) return out;
  for (const id of Object.keys(rows)) {
    const vals = tags.map((t) => field(rows[id], t));
    if (vals.some((v) => v != null)) out[id] = vals;
  }
  return out;
}

// ---------------------------------------------------------------- phase 4: category
function loadTypeChains() {
  const d = JSON.parse(fs.readFileSync(path.join(ROOT, 'data', 'item-types.json'), 'utf8'));
  const memo = {};
  function chain(t) {
    if (memo[t] !== undefined) return memo[t];
    const seen = [];
    let cur = t;
    while (cur != null && d[cur] !== undefined && !seen.includes(cur)) {
      seen.push(cur);
      cur = d[cur];
    }
    if (cur != null && !seen.includes(cur)) seen.push(cur); // terminal root token
    memo[t] = seen;
    return seen;
  }
  return { d, chain };
}

function categoryOf(type, chain) {
  if (type === 'Mount') return 'mount';
  if (type === 'GearGlider') return 'glider';
  const ch = chain(type);
  if (ch.includes('Weapon')) return 'weapon';
  if (ch.includes('Armor')) return 'armor';
  if (type === 'GearNeck' || type === 'GearFinger' || type === 'GearTrinket') return 'accessory';
  if (ch.includes('Gear')) {
    if (/^Tool/.test(type) || type === 'GearPickaxe' || type === 'GearSickle') return 'tool';
    return 'gear';
  }
  if (ch.includes('CraftingComponent')) return 'material';
  if (ch.includes('Currency')) return 'currency';
  if (ch.includes('LoreBook')) return 'book';
  if (ch.includes('Usable')) return 'consumable';
  return 'misc';
}

// ---------------------------------------------------------------- main
async function main() {
  const cdb = loadCdbDir(CDB_DIR);
  console.log('cdb files: en=' + cdb.en.file, 'pt=' + (cdb.pt && cdb.pt.file), 'es=' + (cdb.es && cdb.es.file));

  const listed = await listAllItems();
  const ids = Object.keys(listed).sort();
  console.log('listed items:', ids.length);

  const raw = await fetchRaw(ids);

  const { chain } = loadTypeChains();
  const itemPt = cdb.pt ? cdbTexts(cdb.pt, 'item', ['texts.name', 'texts.flavorDesc']) : {};
  const itemEs = cdb.es ? cdbTexts(cdb.es, 'item', ['texts.name', 'texts.flavorDesc']) : {};
  const itemEn = cdbTexts(cdb.en, 'item', ['texts.name', 'texts.flavorDesc']);

  const items = [];
  const catCounts = {};
  let ptN = 0, esN = 0, flavor = 0, atlas = 0, noRaw = 0;
  for (const id of ids) {
    const card = listed[id];
    const r = raw[id];
    if (!r) noRaw++;
    const type = (r && r.type) || null;
    const cat = type ? categoryOf(type, chain) : 'misc';
    catCounts[cat] = (catCounts[cat] || 0) + 1;
    const gfx = (r && r.gfx) || {};
    const icon = card.icon || (gfx.file ? 'https://cdn.fareverdb.com/' + gfx.file : null);
    const e = {};
    e.id = id;
    if (type) e.type = type;
    e.cat = cat;
    const rarity = (r && r.rarity) || (card.rarity ? card.rarity[0].toUpperCase() + card.rarity.slice(1) : null);
    if (rarity) e.rarity = rarity;
    if (r && r.level != null) e.level = r.level;
    if (icon) e.icon = icon;
    if (gfx.x || gfx.y) { e.ix = gfx.x || 0; e.iy = gfx.y || 0; e.isz = gfx.size || 54; atlas++; }
    if (r && r.faction) e.faction = r.faction;
    if (r && r.affinity != null) e.affinity = r.affinity;
    if (r && r.aptitudes && Object.keys(r.aptitudes).length) e.apt = r.aptitudes;
    if (r && r.skills && Object.keys(r.skills).length) e.skills = r.skills;
    if (r && r.props && Object.keys(r.props).length) e.props = r.props;
    if (r && r.flags != null) e.flags = r.flags;
    if (r && r.sellPrice != null) e.sell = r.sellPrice;

    const enName = (r && r.texts && r.texts.name) || card.name;
    const enFlavor = (r && r.texts && r.texts.flavorDesc) || (itemEn[id] && itemEn[id][1]) || null;
    e.en = { n: enName, f: enFlavor };
    const pt = itemPt[id];
    const es = itemEs[id];
    e.pt = { n: (pt && pt[0]) || enName, f: (pt && pt[1]) || null };
    e.es = { n: (es && es[0]) || enName, f: (es && es[1]) || null };
    if (pt && pt[0]) ptN++;
    if (es && es[0]) esN++;
    if (enFlavor) flavor++;
    items.push(e);
  }

  const units = {};
  for (const [cdbFile, lang] of [[cdb.en, 'en'], [cdb.pt, 'pt'], [cdb.es, 'es']]) {
    if (!cdbFile) continue;
    const rows = cdbTexts(cdbFile, 'unit', ['texts.name']);
    for (const id of Object.keys(rows)) {
      units[id] = units[id] || {};
      if (rows[id][0]) units[id][lang] = rows[id][0];
    }
  }
  const rarities = {};
  for (const [cdbFile, lang] of [[cdb.en, 'en'], [cdb.pt, 'pt'], [cdb.es, 'es']]) {
    if (!cdbFile) continue;
    const rows = cdbTexts(cdbFile, 'rarity', ['name']);
    for (const id of Object.keys(rows)) {
      rarities[id] = rarities[id] || {};
      if (rows[id][0]) rarities[id][lang] = rows[id][0];
    }
  }
  const types = {};
  for (const [cdbFile, lang] of [[cdb.en, 'en'], [cdb.pt, 'pt'], [cdb.es, 'es']]) {
    if (!cdbFile) continue;
    const rows = cdbTexts(cdbFile, 'itemType', ['texts.name.v', 'texts.name.plural']);
    for (const id of Object.keys(rows)) {
      types[id] = types[id] || {};
      if (rows[id][0]) types[id][lang] = rows[id][0];
      if (rows[id][1]) types[id][lang + 'p'] = rows[id][1];
    }
  }

  const generated = new Date().toISOString();
  const itemsDoc = {
    generated,
    source: 'fareverdb.com (game data) + game cdb text exports',
    count: items.length,
    items,
  };
  const i18nDoc = {
    generated,
    langs: ['en', 'pt', 'es'],
    units,
    rarities,
    types,
  };
  fs.writeFileSync(OUT_ITEMS, JSON.stringify(itemsDoc));
  fs.writeFileSync(path.join(ROOT, 'data', 'items.js'), 'window.FAREVER_ITEMS = ' + JSON.stringify(itemsDoc) + ';\n');
  fs.writeFileSync(OUT_I18N, JSON.stringify(i18nDoc));
  fs.writeFileSync(path.join(ROOT, 'data', 'i18n.js'), 'window.FAREVER_I18N = ' + JSON.stringify(i18nDoc) + ';\n');

  console.log('\n--- summary ---');
  console.log('items:', items.length, '| no-raw:', noRaw, '| atlas icons:', atlas);
  console.log('categories:', JSON.stringify(catCounts));
  console.log('pt names:', ptN, '| es names:', esN, '| flavors(en):', flavor);
  console.log('units:', Object.keys(units).length, '| rarities:', Object.keys(rarities).length, '| types:', Object.keys(types).length);
  console.log('wrote', OUT_ITEMS, 'and', OUT_I18N);
}

main().catch((e) => { console.error(e); process.exit(1); });
