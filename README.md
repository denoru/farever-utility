# farever-mods

Personal mods and tools for [Farever](https://store.steampowered.com/app/3672400/).

## Contents

### [`infernal-plunge-highlight/`](infernal-plunge-highlight/)
HLX mod (Haxe → HashLink) that shows an on-screen overlay when your target has
**Chaos Mark**, signalling that **Infernal Plunge** (Rogue) is about to reset.
Per-target countdown timers, ImGui overlay, zero logging.

- Built on [HLX Core](https://github.com/hlx-framework/hlx-core) (hooks + reflection into game types)
- See its [README](infernal-plunge-highlight/README.md) for install/build details

### [`boss-drop-tracker/`](boss-drop-tracker/)
Static web tracker for Farever boss drops (mounts, gliders, legendary-capable
weapons). Per-item/per-boss try counters with drop-rate math, ownership tick
boxes (localStorage), boss-first browsing. Data scraped from
[fareverdb.com](https://fareverdb.com) and cross-checked against metaforge.

- `index.html` — the whole app (no build step, no framework)
- `scrape.js` — regenerates `data/bosses.{json,js}` from fareverdb
- `build-site.js` — assembles the deployable `site/` folder (Netlify Drop)
- `smoke.js` — jsdom end-to-end check (`node smoke.js`)

## Development prerequisites (mods)

- Haxe 4.3.x (`haxe.exe` on PATH)
- [HLX Core](https://github.com/hlx-framework/hlx-core) checked out (for `hlx-runtime` sources)
- `hl-imgui` sources (from the farever-mods ecosystem)
- `compile.hxml` uses absolute `-cp` paths — adjust them to your checkout locations
- Deploy: copy the compiled `.hl` to `<Farever>/hlx/mods/<mod-name>/`

## License

MIT (see individual project files).
