# 01: Wet decks in rain and spray

## Goal
When it rains, or seas come aboard, the ship's timber should look wet:
darker, glossier, with a thin sheen that picks up the sky, and water
running off toward the scuppers as she heels. It should dry over a few
minutes after the rain stops.

## Context
- The weather's live state is `weather.current` (`game/scripts/weather.gd`).
  `current.rain` runs 0..1. `world.gd` already sets `$Player.wet` from rain and sea height.
- Deck and hull materials: the hull uses `ocean/wet_hull.gdshader` (it already
  has a waterline wetness). Decks and props come from `exploration/cabin.gd`
  (`deck_material`, `plank`: ORMMaterial3D) and `exploration/deck_props.gd`
  (`timber`).
- `atmosphere.gd` is the right owner for a new `wetness` value (0..1). Rise
  quickly with rain, and decay with a time constant of about 3 minutes when dry.
  Spray: add wetness when `ocean` reports slam or green water, or start with
  rain only.

## What to build
1. A `wetness` value in `atmosphere.gd` (rain-driven, slow to dry).
2. Wet shading for the exterior timber (decks, rails, masts): albedo
   darkened by about 35%, roughness toward 0.15, specular up. That is
   porous wood saturated with water (Lekner and Dorf 1988 give the physics
   of darkening). Keep it cheap: a shared uniform on a small wet-wood shader,
   or per-material parameters updated when wetness changes by more than
   0.02. Don't create a material per frame.
3. Leave the cabin interior (inside `cabin.contains`) dry.
4. Optional: streaks running to leeward, using the ship's heel (`buoyancy.heel`).

## Constraints
- Follow `AGENTS.md`. `game/exploration/` uses one-space indentation.
- No new textures unless generated procedurally. No per-frame allocations.
- Frozen captures (`SimClock.frozen`) must be deterministic. Use the rain
  target directly when frozen.

## Proof
- Add `tests/wet_deck.gd` (headless): set Storm, advance about 60 s of
  physics, and check wetness > 0.8 and that the deck material's roughness
  parameter is below 0.3. Set Calm and advance 10 minutes: wetness < 0.1.
- `run_tests.gd`, `helm.gd`, `weather.gd` still pass.
- Capture `24_storm_poop_deck` and `10_poop_deck` (see AGENTS.md). The storm
  deck is visibly darker and glossier; the fair one is unchanged.
