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

## Market (community notice board)

**Scope decision (user-confirmed):** no trades happen *on* the platform — it is a
notice board where players announce what they **have** / what they **want**, then
contact each other on Steam. Copy must stay announcement-flavored ("announcement",
"closed", "Contact on Steam"); never imply on-site trading, escrow or payments.

### Files

| File | Purpose |
|---|---|
| `supabase/market.sql` | Schema + RLS. Idempotent, run in the Supabase SQL editor (safe to re-run on schema updates — v2 migrated `listings` → `announcements` and added `profiles.region`). |
| `supabase/functions/steam-auth/index.ts` | Edge function: Steam OpenID verification → Supabase session. Pure fetch, no npm imports (paste-safe in dashboard). |
| `supabase/SETUP.md` | Step-by-step dashboard walkthrough (account → SQL → function → secret → keys). |
| `data/market-config.js` | `{url, anon}` — public Supabase values, loaded before the main script, copied into `site/` by `build-site.js`. Empty = market shows "not configured" state. |

### Architecture

- Site stays **static** (Netlify Drop unchanged). Browser talks to Supabase REST
  directly with a hand-rolled supabase-lite wrapper (`sbQuery`, `mkEnsureAuth`) —
  no supabase-js dependency, so no CDN and `file://` still boots.
- **Login:** browser → steamcommunity.com OpenID → back to `index.html?openid.*`
  (+ `mkt_state` in return_to for CSRF check) → POST all `openid.*` params to
  `steam-auth` → function validates signature (`check_authentication`), pulls
  name/avatar from `profiles/<id>?xml=1` (no API key needed), derives
  `email = steam_<id64>@steam.farever.market` + password =
  `HMAC-SHA256(STEAM_AUTH_SECRET, id64)` → GoTrue create/sign-in → upserts
  `profiles` (service role) → returns tokens. Session persisted in
  `fareverMarket.session.v1`, auto-refreshed 60 s before expiry.
  **Changing STEAM_AUTH_SECRET locks all existing users out** (documented in SETUP).
- **Tables:** `profiles` (steam_id PK, user_id unique → auth.users, `region`
  NA/SA/EU/AS/CN chosen right after sign-in, check-constrained), `announcements`
  (multi-item: `items jsonb[1..20]` of `{kind have|want, item_id?, item_name,
  rarity?}` — kind is per item so one post can mix have/want; `status`
  active/closed; v2 SQL migrates+drops legacy single-item `listings`), `feedback`
  (±1, `unique(from,to)` = one vote per pair,
  `from <> to` check). Rep is **never stored** — summed from feedback at render
  time, so there is no column to tamper with. Region lives on the profile only
  (no per-announcement snapshot).
- **RLS:** all reads public; writes only own rows via `auth_steam_id()`
  (security-definer helper → no policy recursion). No report/admin features
  (user chose only trade feedback ±1).
- **UI:** third tab `Market` — hero + "Sign in with Steam" when signed out,
  feed always visible (public read). Compose panel (v2): region chips
  NA/SA/EU/AS/CN (required before posting, PATCHes `profiles.region`), the
  **two-column compose** (Have/Want side by side as colored panels `.mkt-col`,
  each with its own picker row: category select **All/Weapons/Equipment/
  Mounts/Gliders** — no Legendary/Custom/Other categories; item select with
  optgroups for tracker categories, free-text name input for Equipment since
  the tracker has no armor/necklace/ring drops; rarity select capped per game
  rules: Mounts/Gliders locked to Epic, Equipment limited to Common..Rare,
  Weapons (and All) offer the full ladder with auto-filled tracker rarity),
  then a **shared pool** (1..20 items per
  announcement, remove per row), note, "Post announcement". Announcement cards
  show every item row (kind badge + icon + name + rarity), have/want counts,
  poster's region badge, filters (All/Have/Want = contains an item of that
  kind, Show closed), per-announcement "Contact on Steam"; own posts get
  Mark done/Relist/Delete; rep badge = 4-point star ✦ (filled when rep > 0,
  hollow ✧ otherwise) + number, opens profile modal with feedback list +
  ±1 form (upsert on `on_conflict=from,to`). Toolbar switches to `.mkt` mode:
  chips/hide-owned/reset hidden, main search reused for announcements
  (`Search announcements…`, matches item names/note/seller).
- Integration points in `index.html`: `render()` market branch, view
  click listener routes to `marketClick`, shared `viewInput` on `input`+`change`
  events (market compose branch matches `pick-(cat|item|custom|rarity)-(have|want)`
  per column), tab click calls `marketInit()`, boot ends with
  `handleOpenIdReturn()`. `window.__fareverMarket` is a debug hook used by
  smoke.js to inject synthetic feeds.

### Gotchas

- Steam login needs http(s): `file://` shows an explanatory error — serve
  (`npx serve .`) or use deployed URL. localhost works as return_to.
- Dashboard API page may show `sb_publishable_…` first — use the **legacy
  `anon` `eyJ…` key** (it's a JWT; publishable keys fail JWT verification).
  Function "Verify JWTs" ON or OFF both work (site always sends the anon key).
- smoke.js covers the market tab in its *signed-out* state, then injects a fake
  session (`fareverMarket.session.v1`) to exercise the compose panel (region
  chips, two Have/Want columns with category-capped pool add+remove and
  rarity-rule assertions per column) and a synthetic feed via
  `window.__fareverMarket` to exercise announcement cards, region badges,
  rep star badge, closed filter and have/want/search filtering — all offline
  (jsdom has no
  usable `fetch`; failed loads only set the error box).
- Feedback limit of one row per pair caps farming at +1 per distinct counterparty.

## Open ideas

- Export / import buttons for the three localStorage blobs (backup across browsers).
- Optional gear (armor) category — maxes at Epic, currently filtered out on purpose.
- Re-check whether fareverDB starts listing real `Legendary` drop rows after a game patch
  (the `legendary` category and chip already handle it).
