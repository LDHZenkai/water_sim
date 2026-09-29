# 04: Settings menu (Esc)

## Goal
Esc opens a small settings menu instead of only releasing the mouse. The
settings persist between runs.

## Context
- Esc is the `pause` action (`game/scripts/player.gd`). It currently toggles
  mouse capture. The weather menu (`scripts/weather_menu.gd`, Tab) shows how
  menus are built in code, and closes on Esc when open.
- Audio buses are created by `scripts/sound.gd`: `Outside` (with `Wind`,
  `Whistle`, `Sea`, `Rain`, `Canvas`), `Thunder`, `Ship`, all feeding `Master`.
- Quality settings: `autoloads/quality.gd` (`tier`, `overrides`,
  `apply_to_world`). Some settings need a restart; say so in the UI.
- Mouse sensitivity: `player.mouse_sensitivity`.

## What to build
1. `scripts/settings_menu.gd` (CanvasLayer, built in code like the weather
   menu). Sections:
   - Audio: master, weather (the `Outside` bus), ship (the `Ship` bus), thunder volume.
   - Controls: mouse sensitivity, invert Y, head bob on/off (set
     `player.head_bob_amount` and `head_sway_amount` to 0).
   - Display: field of view (55..90), render scale (0.5..1.0).
   - Resume and Quit buttons.
2. Persist to `user://settings.cfg` (ConfigFile). Load and apply at start-up
   in `world.gd`.
3. Esc toggles the menu (mouse visible while open). The weather menu keeps
   Tab. Only one menu is open at a time.

## Constraints
- Headless tests must not open menus or touch `user://` unless asked.
- Tabs for indentation in `game/scripts/`.

## Proof
- `tests/settings_menu.gd` (headless): open, change master volume and
  sensitivity, close, re-create the menu, and the values reload from the
  config file. Delete the test config after.
- `run_tests.gd`, `helm.gd`, `weather.gd` still pass.
