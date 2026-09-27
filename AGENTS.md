# AGENTS.md: working on water_sim

Guidance for coding agents (Codex, Claude Code, others). Read it before
changing anything. Task briefs sized for one session each are in
`docs/codex/`.

## What this is

A Godot 4.7 sailing simulation (GDScript + GLSL compute), in `game/`:
a galleon on a physically simulated sea, with live weather, sails driven by
the apparent wind, and a first-person crew member on a moving deck. See
`README.md` for the player's view and the physics references.

## Layout

| Path | What |
| --- | --- |
| `game/scripts/world.gd` | Builds everything: ship, sea, light, weather, atmosphere, HUD, weather menu, sound, helm. Start here |
| `game/scripts/weather.gd` | Live weather: targets and easing, presets, fronts, gusts, squalls, lightning, rogue waves. Drives the sea and the wind |
| `game/scripts/atmosphere.gd` | Sky clouds, sun and fog under overcast, rain particles, lightning bolts and flash |
| `game/scripts/weather_menu.gd`, `hud.gd`, `sound.gd` | Tab menu; notices and warnings; procedural audio |
| `game/scripts/player.gd`, `sea_legs.gd` | First-person movement, carried in ship space; apparent gravity, stagger, brace, gait |
| `game/ocean/sea_state.gd` + `default_sea.tres` | Wave spectrum, explicit long-wave components, live sea layers, rogue-wave focusing |
| `game/ocean/buoyancy.gd` | Ship motion: sailing (surge, yaw, heel), surfing, broaching, knockdowns, heave/roll/pitch |
| `game/ocean/ocean.gd`, `fft_ocean.gd`, `wake_sim.gd`, `compute/*.glsl`, `*.gdshader*` | Ocean surface, GPU FFT cascades, reactive wave solver, shaders |
| `game/exploration/` | Ship interior and props, helm, sails rig, rigging climb, doors, interactables |
| `game/dev/tour.gd` | Frozen-time photo captures of named shots |
| `game/tests/` | Headless and GPU test scripts (each `extends SceneTree`) |

## Conventions

- **Indentation:** `game/ocean/` and `game/exploration/` scripts use ONE SPACE
  per level; `game/scripts/`, `game/autoloads/` and `game/tests/weather.gd`
  use tabs. Match the file you are in; mixing breaks the parser.
- **Comments:** `##` doc comments explain the physics or the why, with
  references where a formula comes from a paper. No commented-out code.
- **Units:** SI throughout (m, s, m/s, rad). Knots and compass degrees appear
  only in UI text.
- **Frames:** ship space has the bow toward +X, up +Y, starboard +Z. World XZ:
  north is -Z, east is +X. The hull stays at the world origin; the sea drifts
  past it (`buoyancy.drift`). Bearings in the UI are the compass direction a
  wind or sea comes FROM.
- **Determinism:** tests and tours depend on seeded RNGs and fixed-step
  integration. Don't add unseeded randomness to physics.
- After adding any file under `game/`, run `godot --headless --import --path game`
  to create its `.uid` (and `.import`) file. Commit those too.

## Traps (each of these has cost real time)

1. **Constant-folded resource properties.** `const SEA = preload("res://ocean/default_sea.tres")`
   then `SEA.wind_speed` in ANOTHER script is folded at compile time to the
   file's value, and never sees the live weather. Read live values through
   methods (`SEA.wind()`, `SEA.sea_key()`) or `SEA.get("wind_speed")`, and write
   with `SEA.set(...)`. Assigning `SEA.x = ...` through the constant is a
   parse error.
2. **Names that shadow Object methods** (`_set`, `_get`, `set`, `get`,
   `notification` and so on) break silently or loudly. Pick another name.
3. **Untyped `:=` from Variant** (dictionary values, `get()`) fails type
   inference. Declare the type: `var x: float = d.value`.
4. **Headless has no RenderingDevice:** FFT, wake, particles and audio are
   disabled or skipped under `--headless`. GPU tests need a window (xvfb).
5. **Frozen clock:** tours call `world.freeze_at(t)`, and `SimClock.frozen`
   stops weather, ship and wake stepping. Anything time-based must behave
   when frozen (see `atmosphere.gd`).
6. **Environment colours are sRGB**; shader outputs are linear. Convert
   (`Color.linear_to_srgb()`) when matching fog to sky.
7. **RID lifetimes:** release the wake before the FFT (its uniform sets use
   the FFT textures). Check `uniform_set_is_valid` before freeing.
8. **Environment ownership:** the cabin owns `tonemap_exposure` and
   `ambient_light_energy` each frame. The weather sets `cabin.base_exposure`
   and `cabin.base_ambient` instead of writing the environment directly.

## Running

```
godot --path game                                   # play (window)
godot --path game -- --weather=Storm --sails=1      # start in a storm, reefed
godot --headless --path game -s tests/run_tests.gd  # main suite (about 1 min)
godot --headless --path game -s res://tests/helm.gd
godot --headless --path game -s res://tests/weather.gd
godot --path game -s res://tests/gpu_ocean.gd       # needs a window / GPU
```

Frozen photo of a named shot (see `SHOTS` in `game/dev/tour.gd`), for
example on a machine without a GPU (lavapipe + xvfb):

```
VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json xvfb-run -a -s "-screen 0 1280x720x24" \
  godot --path game --rendering-method forward_plus --write-movie out/f.png --fixed-fps 60 \
  --quit-after 24 res://dev/tour.tscn -- --quality=high --shot=25_storm_exterior --expect=960x540
```

The last frame (`out/f00000023.png`) is the capture. Weather shots take
`weather`, `sail`, `lightning`, `rogue`, `menu` and `helm` keys.

## Before you commit

- Run the three headless suites above. They must all pass. Some legacy M2
  audits (`tests/m2b_*.gd`, `audit_hull.gd`) are diagnostic, and their
  pre-existing output is not a regression; compare against `main` if unsure.
- If you touched rendering, capture the affected tour shots and look at them.
- Keep commits focused, with a message that says what changed and why.
