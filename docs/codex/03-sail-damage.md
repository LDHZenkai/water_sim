# 03: Carrying away canvas

## Goal
Extend the heavy-weather mechanic. Carry too much sail in a blow for too
long and a sail splits. You lose its drive until the crew bends a new one,
which takes time and can only be done with the ship eased.

## Context
- `game/ocean/buoyancy.gd`: `canvas` (0..1, set by `sail` 0..3 via
  `SAIL_CANVAS`), `heel`, `overpressed()` (heel past 12°), `thrust()`.
- `game/exploration/sails.gd` builds four sail islands (`sail_count`) with
  per-vertex `CUSTOM1.z` = sail index, and a shader (`sails.gdshader`) with
  uniforms `fill`, `luff`, `canvas`.
- HUD notices: `hud.show_notice(text, seconds)`. The weather menu log:
  `hud.ship_log()`.
- The helm readout: `helm.conditions()`.

## What to build
1. Sail load per sail: ∝ canvas × |apparent wind|² × polar(angle) (the same
   terms as thrust), plus gust peaks (`weather.gust`). Accumulate "strain"
   while above a limit (full canvas at about 18 m/s apparent), and relax it
   below. When strain passes a threshold, the sail with the highest load splits.
2. A split sail: its share of drive is lost (`thrust` × (1 − share)); it
   flogs (shader: that sail index gets strong `luff` and a torn look, such as
   discarding a ragged region, driven by a per-sail uniform array or a
   small data texture); HUD notice "The fore topsail has split!".
3. Repair: if canvas is at or below reefed for 90 s with heel under 8°,
   "Hands aloft to bend a new sail", then after 120 s it is restored. Show
   progress in the helm readout.
4. Log it: sails split and replaced in `hud.ship_log()`.

## Constraints
- Deterministic (no unseeded RNG). Gusts are already deterministic.
- In the default Fair weather under full sail, no sail may ever split
  (check it over 20 simulated minutes).
- Keep `buoyancy.gd` responsible for the physics and `sails.gd` for visuals.
  Put the damage state in a small new script (`exploration/sail_damage.gd`)
  that `world.gd` wires up.

## Proof
- `tests/sail_damage.gd` (headless, standalone buoyancy plus the new
  script): Fair for 20 minutes gives no damage. A Storm beam reach under
  full sail splits within 3 minutes. The split sail cuts steady speed by
  roughly its share. Reefing and waiting repairs it.
- `helm.gd` and `weather.gd` still pass.
