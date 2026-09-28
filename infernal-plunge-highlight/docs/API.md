# Infernal Plunge Highlighter - API Reference

## Target Detection

### `farever.target`

| Function | Returns | Description |
|----------|---------|-------------|
| `exists()` | `boolean` | True if a target is locked |
| `name()` | `String` | Target kind id (e.g. `"Boar_Z1W_E"`) |
| `level()` | `Number` | Target level |
| `hp()` | `Number` | Current HP |
| `max_hp()` | `Number` | Max HP |
| `is_casting()` | `boolean` | True during a real cast |
| `cast_skill()` | `String` | Skill id being cast |
| `cast_progress()` | `Number` | 0.0-1.0 cast progress |
| `cast_remaining_sec()` | `Number` | Remaining cast time |

### `farever.player`

| Function | Returns | Description |
|----------|---------|-------------|
| `class()` | `String` | `"Rogue"`, `"Mage"`, `"Priest"`, `"Warrior"` |
| `name()` | `String` | Character name |
| `level()` | `Number` | Character level |
| `health()` | `Number` | Current HP |
| `max_health()` | `Number` | Max HP |
| `statuses()` | `Array` | Active statuses, each `{kind, duration, stacks, shield_amount}` |
| `skills()` | `Array` | Skills, each `{kind, cooldown, base_cooldown, charges, icon}` |
| `weapon_skills()` | `Array` | Weapon skills, each `{slot, kind, icon}` |
| `in_combat()` | `boolean` | Combat flag |
| `has_target()` | `boolean` | True if target exists |
| `locked()` | `boolean` | True after hero lock |

### Status Format

Each status from `farever.player.statuses()`:
```lua
{
    kind = "Chaos_Mark",       -- Internal status id
    duration = 5.0,            -- Remaining duration in seconds
    stacks = 1,                -- Stack count
    shield_amount = 0          -- Absorb value (0 for non-shield)
}
```

### Skill Format

Each skill from `farever.player.skills()`:
```lua
{
    kind = "infernal plunge",  -- Internal skill id (lowercase)
    cooldown = 0.0,            -- Current cooldown (0 when ready)
    base_cooldown = 15.0,      -- Base cooldown
    charges = 0,               -- Available charges
    icon = "Rogue_InfPlunge"   -- Icon atlas reference
}
```

## Events

| Event | Data | When |
|-------|------|------|
| `target_changed` | `{kind}` | Target changes |
| `fight_start` | `{fight_id}` | Combat begins |
| `fight_end` | `{fight_id, duration, total_damage, dps}` | Combat ends |
| `cast_start` | `{skill, total_sec}` | Cast begins |
| `cast_end` | `{skill, duration}` | Cast completes |
| `damage_dealt` | `{skill, amount, is_crit, is_kill, target}` | Damage dealt |
| `heal_dealt` | `{skill, amount, is_crit, target}` | Healing done |
| `shield_applied` | `{skill, amount}` | Shield gained |
| `weapon_changed` | `{kind, prev_kind, level, upgrade}` | Weapon swap |

## ImGui Drawing API

### Flow Widgets

| Function | Description |
|----------|-------------|
| `imgui.text(str)` | Display text in the mod's window |
| `imgui.button(str)` | Clickable button |
| `imgui.checkbox(str, bool)` | Toggle checkbox |
| `imgui.slider_float(str, min, max, val)` | Float slider |
| `imgui.slider_int(str, min, max, val)` | Integer slider |
| `imgui.combo(str, idx, items)` | Dropdown combo |
| `imgui.color_edit(str, r, g, b)` | Color picker |
| `imgui.progress(ratio)` | Progress bar (0.0-1.0) |
| `imgui.separator()` | Horizontal line |
| `imgui.spacing()` | Empty space |
| `imgui.same_line()` | Next widget on same line |
| `imgui.icon(name, size)` | Draw game skill icon |
| `imgui.atlas_icon(atlas, x, y, w, h)` | Draw from atlas |
| `imgui.font_scale(n)` | Set text scale |
| `imgui.dummy(w, h)` | Reserve space |
| `imgui.cursor_pos()` | Returns `{x, y}` |

### Absolute Drawing Primitives

| Function | Description |
|----------|-------------|
| `imgui.draw_rect_filled(x1, y1, x2, y2, r, g, b, a)` | Filled rectangle |
| `imgui.draw_rect(x1, y1, x2, y2, r, g, b, a, thick)` | Rectangle outline |
| `imgui.draw_circle_filled(x, y, r, r, g, b, a)` | Filled circle |
| `imgui.draw_circle(x, y, r, r, g, b, a, thick)` | Circle outline |
| `imgui.draw_line(x1, y1, x2, y2, r, g, b, a, thick)` | Line |
| `imgui.draw_text(x, y, r, g, b, a, str)` | Screen-space text |
| `imgui.draw_triangle_filled(x1,y1,x2,y2,x3,y3, r,g,b,a)` | Filled triangle |
| `imgui.draw_triangle(x1,y1,x2,y2,x3,y3, r,g,b,a,thick)` | Triangle outline |

## Utility API

| Function | Description |
|----------|-------------|
| `farever.now()` | Current game time (seconds, monotonic) |
| `farever.sound("alert")` | Play Windows system sound |
| `farever.toast("msg")` | Show centered toast notification |
| `farever.log.info(str)` | Log to `farever-mod.log` |
| `farever.log.warn(str)` | Log warning to `farever-mod.log` |
| `farever.write_combatlog(name, text)` | Write to `%LOCALAPPDATA%\farever-minimap\combatlogs\` |
| `farever.store.get(key, default)` | Get persisted scalar value |
| `farever.store.set(key, value)` | Set persisted scalar value |

## Notes

- `imgui.begin` / `imgui.end` are **NOT** available — the mod opens the window
- The window title is the plugin filename (minus `.lua`)
- `pcall` catches all errors — a broken plugin doesn't crash the mod
- Plugins hot-reload ~1 second after saving the `.lua` file
- `io`, `require`, `dofile`, `os.execute`, `debug` are all removed

## Status Name Matching

The plugin searches for statuses containing "chaos" (case-insensitive) in `kind`:
```lua
local kind = s.kind  -- e.g. "Chaos_Mark" or "Mark_of_Chaos"
if string.find(string.lower(kind), "chaos") then ...
```

If the status name is different, use the **API Inspector** plugin to find the exact `kind` value.
