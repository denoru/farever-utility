# Cast Sequence (Farever)

Single-key skill sequencer inspired by WoW's **GSE**: one trigger key walks an
editable ordered list of skills — each press casts the next castable step and
skips whatever is on cooldown, so a rotation becomes one button.

## Features

- Editable ordered sequence (add/remove/reorder), persisted between sessions
- ImGui HUD: next skill with cooldown/charges and ready state (default trigger **F1**)
- Priority pass: charge-window skills jump the queue while their window is open
- **Void Fangs rules** enforced client-side (raw `tryUse` bypasses the game's
  input validation): summon once, at most **3 throws inside the 8 s window**,
  target is the locked/auto-target foe (`Target(unit)` → homing like the game's
  own keypress), never re-summons, never throws with no knives out
- Two modes (`mode` in config):
  - `skill` (default) — casts through the game's own skill API
  - `hotkey` — injects real keystrokes/mouse buttons through a small SendInput
    helper (`tools/injector.cs`), sequence tokens like `R`, `2`, `T` (back),
    `MB1`/`MB2` (mouse), paced by `stepDelayMs`

## Install

Copy `cast-sequence.hl` into `<Farever>/hlx/mods/cast-sequence/`.
Config lives at `<Farever>/hlx/config/cast-sequence/config.json`
(`steps`, `triggerKey` — ImGui key id, `572` = F1 — `mode`, `hotkeys`,
`stepDelayMs`).

## Build

`haxe compile.hxml` (Haxe → HL bytecode). Classpaths:

- `src`
- hlx-runtime (`HlxRuntime` reflection helpers for game types)
- hl-imgui (ImGui binding)

Hotkey mode helper: `csc /target:winexe tools/injector.cs` → place
`injector.exe` next to the mod (only needed for `mode: "hotkey"`).

## Notes

- Tested against Farever (Steam app 3672400) with the HLX mod loader.
- `bin/cast-sequence.hl` is a build artifact and is not committed.
