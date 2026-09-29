# 05: Time of day

## Goal
Add a time-of-day slider to the weather menu (and optionally let time pass)
covering dawn, day, dusk and night: the sun moves, the sky and sea change
colour, and at night there are stars and a moon, and the ship's lanterns glow.

## Context
- Today the scene is lit for one late afternoon: an HDR panorama
  (`assets/polyhaven/hdris/qwantani_late_afternoon_puresky_4k.hdr`) in
  `scripts/aligned_sky.gdshader`, and a sun direction measured from that
  panorama (`world.gd`, `SUN_UV`, `sun_direction()`). `tests/run_tests.gd`
  checks the sun matches the panorama's sun disk; keep that true for the
  default time.
- The ocean reads `sun_direction`, `sun_energy` and `sun_color` uniforms
  (`ocean/ocean.gd` sets them once; `atmosphere.gd` updates `sun_energy`).
  The ocean's reflection map `sky_map` is built from the panorama.
- `atmosphere.gd` owns per-frame lighting under weather. Extend it rather
  than adding a second owner, and keep the overcast logic working at any hour.
- The cabin has lamps (`exploration/cabin.gd`, `lamps`), and deck lanterns
  are in `deck_props.gd`.

## What to build
1. `time_of_day` (hours) in the weather state and menu. Default: the
   panorama's own time, so the default look is unchanged.
2. A procedural sky: a physically based analytic model (Preetham, or a cheap
   Hosek-Wilkie fit) blended in as the sun moves away from the panorama's
   time. Stars and the moon at night, hidden by cloud cover.
3. Sun and moon lights: direction, colour temperature and intensity from
   elevation. The moon is dimmer and bluish. Shadows from whichever is up.
4. Ocean: update `sun_direction` and `sun_color` live. Rebuild or blend
   `sky_map` so the reflections match (a lower-resolution radiance capture
   is fine).
5. Night: the lanterns and cabin lamps are brighter relative to the scene;
   exposure adapts within limits.

## Constraints
- The default time must reproduce today's look, and `run_tests.gd`'s sun
  checks must still pass.
- Frozen tours: add `time` to the tour shot keys; captures stay deterministic.
- Performance: the sky may update incrementally. Don't re-render the
  reflection map every frame at full resolution.

## Proof
- Tests: the default time gives the same sun direction as today (within 0.1°).
  At noon the sun elevation is above 50° at the scene's latitude and date
  (pick and document them). At midnight the sun is below the horizon and
  the moon light is enabled.
- Tour shots at dawn, noon, dusk and night, from `02_ship_exterior_wide` and `10_poop_deck`.
