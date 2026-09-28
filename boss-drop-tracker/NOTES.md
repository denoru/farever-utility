# Boss Drop Tracker — session notes

Goal: a personal web tracker for Farever boss drops (mounts, gliders, legendary-capable
weapons) with owned-ticks, per-item/per-boss try counters and drop-rate math.
References used: https://fareverdb.com (primary data), https://metaforge.app/farever (cross-check).

## Files

| File | Purpose |
|---|---|
| `index.html` | The whole app (single self-contained page, inline CSS/JS). Open directly in a browser. |
| `scrape.js` | Data pipeline → `data/bosses.json` + `data/bosses.js`. |
| `data/bosses.js` | `window.FAREVER_BOSS_DATA = {...}` — loaded with `<script src>` so `file://` works (fetch() on file:// is blocked). |
| `data/bosses.json` | Same payload as JSON (fallback if served over http). |
| `data/item-types.json` | Cached CastleDB `itemType → inherit` map (reused across runs). |
| `smoke.js` | jsdom end-to-end test: boots the page over a tiny http server, clicks things, asserts counts + localStorage. Run `node smoke.js`. |

Workflow: `node scrape.js` (refresh data) → `node smoke.js` (verify) → open `index.html`.

## FareverDB facts (data source)

- Boss pages are Next.js RSC: drops live inside `self.__next_f.push([1,"..."])` JS strings,
  so every quote is `\"` and every backslash is `\\`.
  `extractDropsArrays()` in `scrape.js` scans from `\"drops\":[` with this rule:
  - `\` + `"` → toggles "inside decoded JSON string" (this is what fixed the original bug:
    the old scanner entered a string on the `"` of `\"` and never got out, ran to end of
    HTML, and produced `totalDrops: 0` for every boss).
  - any other `\X` → skip 2 chars, no structural meaning.
  - brackets only counted while outside a string.
  Then `JSON.parse('"' + raw + '"')` unescapes and `JSON.parse` gives the array.
- Useful endpoints (all work with plain `fetch` + a user-agent):
  - `/units?category=boss|world-boss&page=N` — boss list (18 units, 6 are world bosses).
  - `/units/<id>` — page with drops arrays; `/api/raw/unit/<id>` — name/lvl/portrait (`gfx.file`).
  - `/api/raw/item/<id>` — `type`, `rarity`, `gfx.file` for one item.
  - `/sheet/itemType` — all 100 item types; `/sheet/itemType/<T>` — its `inherit` (CastleDB).
  - `/items?type=<T>` — items of that exact type (exact match, no inheritance, 60/page).
    `/items?class=`, `/items?rarity=`, `/items?page=` also exist.
  - Images: `https://cdn.fareverdb.com/<path>` (e.g. `UI/Portraits/Items/Mount/Mount_X.png`).
- Page size is 60; class lists came back as exactly 60 for all 4 classes (site cap/quirk —
  not verified as complete).
- `metaforge.app` blocks plain node fetch with a Cloudflare challenge — use it only as a
  visual/reference check (its weapon list, 37 weapons, matched our scrape exactly).

## Game knowledge baked into the tool

- Config on any fareverDB page: `rarityRules = { gearMaxRarity: "Epic", weaponMaxRarity: "Legendary" }`
  and `data_version "0.2.0"`.
- **No boss drops anything with `itemRarity: "Legendary"`.** Boss weapons drop as **Rare** and
  upgrade to Legendary (that's the "legendary weapon"). fareverDB's only Legendary item is
  `Essence_Z2` = Glittering Spark (enchanter crafting component).
- Weapon detection: follow `itemType` `inherit` chain until you hit the node `Weapon`
  (`Daggers → DualWeapon → MainhandWeapon → Weapon → Gear`; `Chest → Armor → Gear`).
  Implemented in `fetchTypeInherits()` + `fetchWeaponItems()`; 37 weapons in game, 27 drop
  from bosses.
- Drop `kind` values seen: `boss`, `dungeon`, `mount`, `glider`, `loot` — `kind` is the source
  table, **not** the item type (a weapon can have `kind: "dungeon"`). Never classify by `kind`
  or by icon folder (`GS_Nova` lives in folder `GS` but `type` is `GreatSword`).
- `proba` is a per-run chance (mounts/gliders 0.001 = 0.1%, boss weapons ~0.01 = 1%).

## Scraper behaviour

- Filter (in `isTracked`): legendary rarity **or** mount/glider **or** weapon type.
- Dedupes drops per boss by `itemId`, then merges boss clones by **name**
  (Nightqueen has 3 clone units → 1 entry, `ids` array holds the variants).
- Output: 16 bosses, 50 unique items = 11 mounts + 12 gliders + 27 weapons, 80 drop entries.
- `data/item-types.json` is cached — delete it to re-fetch the type sheet.
- A full run is ~160 requests with `DELAY = 200` ms (≈40 s).

## Web app architecture (`index.html`)

- `boot(data)` builds: `items` (unique by `itemId`, with `sources[]`, `maxRarity`, `itemType`),
  `itemsById`, `bossesByName`, `CATS` (categories actually present → chips are generated, so a
  new category appears automatically).
- Two tabs — **By boss** is first and active by default, **Items** second — plus category
  chips, search, hide-owned toggle; all read `state` (`state.tab = 'bosses'` at boot).
- Rendering is full innerHTML replacement; listeners are delegated on `#view`
  (`click` ignores `INPUT` targets so ticking still works, `input` handles counters).
- Rate math:
  - item: `drops / tries` vs that item's `proba`.
  - boss: auto-summed from its items' drop counters vs `sum(proba of all its drops)`.
  - `fmtChance()` only strips trailing zeros **when a decimal point exists** (a previous
    version turned "10%" into "1%").
- Stats cards = per-category owned/total; label for weapons is "Legendary-ready".

## Persistence (localStorage, origin = file path of index.html)

| Key | Content |
|---|---|
| `fareverBossTracker.v1` | owned ticks `{itemId: 1}` |
| `fareverBossTracker.runs.v1` | boss tries `{bossName: {tries, legs}}` (`legs` legacy, unused now) |
| `fareverBossTracker.itemruns.v1` | item counters `{itemId: {tries, drops}}` |

Keys by boss **name** (not id) so merges/renames of unit ids don't lose data.
Wipe = "Reset" button or clearing browser site data. Opening via a local server (`npx serve`)
is a different origin → empty storage.

## Environment gotchas

- **PowerShell quoting**: `node -e "..."` breaks on `$`, `"` and `[]`. Write a temp `.js`
  file and run that instead.
- `rg` is not installed — use the Grep tool or `Select-String`.
- `jsdom` was installed with `npm i --no-save jsdom` (dev-only, not in package.json).
- Scratch probes (`probe.js`, `diag.js`, `debug.js`, `rarity-check.js`) were deleted; recreate
  the same way if needed.

## Open ideas

- Export / import buttons for the three localStorage blobs (backup across browsers).
- Optional gear (armor) category — maxes at Epic, currently filtered out on purpose.
- Re-check whether fareverDB starts listing real `Legendary` drop rows after a game patch
  (the `legendary` category and chip already handle it).
