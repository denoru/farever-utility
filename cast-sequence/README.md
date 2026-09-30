# Cast Sequence Mod (Farever)

WoW-style **GSE (Gnome Sequencer Enhanced)** inspired mod: one key walks through an
editable ordered list of skills, so a rotation becomes a single button.

Reference: https://www.curseforge.com/wow/addons/gse-gnome-sequencer-enhanced-advanced-macros

## Features

- **Editable sequence** of skill kinds (add / remove / reorder), saved between sessions
- **Trigger key** (default F1) casts the current step; cursor advances on success
- **Strict order (default ON)** — each press casts only the cursor step and holds if
  it's not ready/rejected, so fast mashing never skips or wraps out of sequence.
  Toggle off for the old priority walk (skip ahead / wrap to first ready step)
- **Combat-end cursor reset** — leaving combat (`hero.isInCombat`, activity fallback
  when the flag can't be read) resets to step 1. Debounced 2s so a one-frame flag
  flicker never resets mid-fight, and it fires once per real transition
- **Infernal Plunge gate** — `Daggers_Demondash_Skill1` only casts while the target
  carries Chaos Mark (`Daggers_Demondash_Mark` / any "chaos" status on the target's
  `statuses`). HUD shows `WAIT: target has no Chaos Mark`, editor shows `gated`.
  Toggle "Plunge needs Chaos Mark" to disable
- **Void Fangs throw window** — while knives are out, throws jump the queue and are
  capped by the game's own charges/window rules (max 3 throws / 8s, reset per summon);
  no blind shots (target required, `checkUse == Ok` only)
- **Hotkey mode** — alternative mode where each trigger press injects the next key /
  mouse button of a sequence (via `injector.exe`), with step delay
- HUD shows next castable step + CD/charge status; editor shows per-step CD, ready,
  gated state

## Build

```
haxe compile.hxml        # -> bin/cast-sequence.hl
```

- Haxe: `C:\HaxeToolkit\haxe_20240807093059_760c0dd\haxe.exe`
- Classpaths come from `compile.hxml` (hlx-core runtime + hl-imgui)

## Deploy / activate

Game dir: `C:\Program Files (x86)\Steam\steamapps\common\Farever\`

```
copy bin\cast-sequence.hl  <game>\hlx\mods\cast-sequence\cast-sequence.hl
```

- The loader picks up any `<name>.hl` + `info.json` in `hlx\mods\<name>\` at launch
- To deactivate without deleting: rename to `cast-sequence.hl.disabled`
- Restart the game after deploying (mods load at boot only)
- Diagnostics: `<game>\hlx\logs\hlx.log` (presses trace `cast` / `strict: hold` /
  `combat end` / `slots` lines; one-shot `status` lines list each step's CD)

## Modes & settings (editor window)

| Setting | Default | Meaning |
|---|---|---|
| Enabled | on | master switch for the trigger |
| Trigger key | F1 | key that advances the sequence |
| Mode | Skills | `Skills` = cast steps; `Hotkeys` = inject key presses |
| Strict order | on | hold cursor step, never skip |
| Plunge needs Chaos Mark | on | gate Infernal Plunge on the mark |
| Step delay ms | 300 | hotkey mode throttle between presses |

## Known facts (from repo research)

- Stack: **HLX (Haxe → .hl)** — `@:hlx.postfix(GameApp.update)` tick hook,
  `HlxRuntime.resolveType/resolveMember` reflection into game types.
- Game keybinds are named actions in `<game>/bindings.sav`; ImGui provides
  `isKeyPressed` for trigger detection.
- Lua plugin alternative exists (`data/plugins/*.lua`, docs/API.md) but has no
  cast API — casting is done through `UnitController.tryUseSkill` / `Hero.doUseSkill`
  reflection, resolved once at startup.
