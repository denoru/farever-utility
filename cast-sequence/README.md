# Cast Sequence Mod (Farever)

WoW-style **GSE (Gnome Sequencer Enhanced)** inspired mod: one key walks through an
editable ordered list of skills, so a rotation becomes a single button.

Reference: https://www.curseforge.com/wow/addons/gse-gnome-sequencer-enhanced-advanced-macros

## Goal

- Editable sequence of skills (ordered list, add/remove/reorder), saved between sessions
- Press the bound key → next castable skill in the sequence fires
- Sequence semantics (Q3 below): **Strict order (default ON)** — each press casts only
  the current step and holds if it's not ready/rejected, so fast mashing never breaks
  the combo order. Toggle "Strict order" off to restore the old priority walk
  (skip ahead / wrap to the first ready step).
- Sequence state: advance on successful cast, handle cooldowns, reset rules
- Editor UI + on-screen "next skill" indicator (ImGui)

## Known facts (from repo research)

- Two mod stacks exist:
  - **HLX (Haxe → .hl)** — root project style (`src/Main.hx`, `@:hlx.postfix(...)` hooks,
    `HlxRuntime.resolveType/resolveMember` reflection into game types like `ent.Hero`).
    Deploy to `<game>/hlx/mods/<name>/`.
  - **Lua plugins** — `data/plugins/*.lua`, hot reload ~1s, documented API in `docs/API.md`
    (`farever.player.skills()` with cooldown/charges, `farever.player.statuses()`,
    events like `cast_start`/`cast_end`, ImGui widgets, `farever.store` persistence).
- **No cast/trigger API is documented or present anywhere in the repo yet** (searched
  `cast_skill`, `use_skill`, `try_cast`, `keybind`, `SendInput`, ...). Existing API only
  *reads* cast state (`farever.target.cast_skill()`, events).
- Game keybinds are named actions in `<game>/bindings.sav`
  (`Skill3`, `Skill4`, `SignatureSkill`, `Mount`, `SeeDetails`, ...) — the game has an
  action system that may be callable via reflection.
- ImGui has `imgui.isKeyDown(key)` (hl-imgui) — usable for detecting a trigger key.
- Game path: `C:\Program Files (x86)\Steam\steamapps\common\Farever\`
  (installed mods: dps-meter, fix-target-lock, item-utilities, better-mod-settings, ...).

## Open questions (blocking)

1. Firing mode: guide (UI tells you which key to press) vs auto-cast (mod triggers the
   skill itself — needs in-game discovery of the cast/action function)
2. Which stack: Lua plugin (fast iteration) vs HLX Haxe (deeper hooks, matches IP mod)
3. Sequence semantics when next skill is on cooldown: skip ahead / wait / stop
4. Reset rules: out of combat? manual? after full loop?

## Layout (planned)

```
cast-sequence/
  README.md        # this file
  src/             # mod source (TBD by stack choice)
  build / notes    # TBD
```
