# Infernal Plunge Highlight

HLX mod for Farever that shows an overlay when **Chaos Mark** is active on your target, indicating **Infernal Plunge** cooldown will reset on hit.

## Features

- Detects `Daggers_Demondash_Mark` (Chaos Mark) on current target
- Per-target timer tracking - switch targets, each maintains its own countdown
- Fixed 6s countdown from mark application
- Auto-refreshes timer when mark is reapplied (detects <1s remaining)
- Clean ImGui overlay: dark semi-transparent background, white text, red cooldown number
- Zero logging, minimal CPU (33Hz detection)

## Installation

1. Install [HLX Core](https://github.com/hlx-framework/hlx-core) (0.0.8+)
2. Download `farever-infernal-plunge-highlight.zip`
3. Extract to Farever game directory (creates `hlx/mods/infernal-plunge-highlight/`)
4. Launch game

## How it Works

**Mark Sources** (from Nibsham's Liberators or Void Fangs):
- **Demonic Bite** (combo finisher) - applies Chaos Mark for 6s
- **Void Fangs** (skill 2 recast) - applies Chaos Mark for 6s

**Overlay appears when:**
- Target has Chaos Mark active
- Shows remaining time (6s → 0s)
- "Infernal Plunge READY!" indicator

**Target switching:** Each enemy tracks independently. Switch back to a marked target and its timer continues counting down.

## Technical

- **Hook**: `@:hlx.postfix(GameApp.update)` with 3-param signature (instance, dt, result) - avoids DPS Meter conflict
- **Detection**: Scans `target.statuses` via ArrayProxyData fallback iteration
- **Timer**: Per-target map keyed by target object string, 6s fixed duration, refreshes on reapplication
- **ImGui**: Registers draw callback even if DPS Meter claims present hook
- **Colors**: Default ImGui theme + red timer (0xFF0000FF RGBA)

## Files

```
src/
  Main.hx          # Main mod logic
  SkillRemain.hx   # SolarFlare status time reader (unused currently)
build.js           # Node build script
package.json       # Mod metadata
dist/farever-infernal-plunge-highlight.zip  # Vortex-compatible release
```

## Build

Requires Haxe 4.3.x. Set the `HLX_RUNTIME_SRC` environment variable to your
`hlx-core/hlx-runtime/src` checkout (or place `hlx-core` next to this project),
and adjust the `-cp` paths in `compile.hxml`.

```bash
node build.js
```

Outputs to `<Farever>/hlx/mods/infernal-plunge-highlight/infernal-plunge-highlight.hl`

## Known Limitations

- Timer assumes 6s base duration; actual mark duration may vary slightly
- No configuration UI (position, colors, size hardcoded)
- Relies on `target.statuses` iteration; may miss marks if status system changes
- No sound/visual alert on mark application

## Changelog

**v1.3.0** - Current
- Per-target timer tracking with auto-refresh on mark reapplication
- Clean overlay with default ImGui theme
- Removed all debug logging
- 33Hz detection with precise expiry

**v1.2.0**
- Fixed target differentiation (only current target's marks)
- Added per-target timer map

**v1.1.0**
- Chaos Mark detection via `target.statuses`
- SkillRemain integration (later removed)

**v1.0.0**
- Initial detection via `hero.instigatedStatuses`
- Basic overlay