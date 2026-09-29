# 02: Bow spray and green water

## Goal
In a seaway the bow should throw spray: sheets of white water when she
slams into a sea, blown aft by the apparent wind across the forecastle.
In heavy weather, green water should come over the rail and run off the
deck.

## Context
- Ship motion: `game/ocean/buoyancy.gd`. `pitch`, `velocity.z` (pitch rate),
  `heave`, `speed` and `forward()`. The hull stays at the world origin; the
  bow is ship-space +X (stem about x = +17, deck edge about y = 3.9 at the forecastle).
- Relative water level at any hull point: `ocean.surface_at(world_point)`
  (CPU, long waves) minus the point's height. The reactive wake solver
  already computes slam and impact foam on the GPU
  (`ocean/compute/wake_output.glsl`), but that is not readable on the CPU.
  Compute a CPU slam signal from the bow's vertical velocity relative to the
  water surface at the bow (finite differences per physics tick).
- Apparent wind: `motion.wind() - motion.forward() * motion.speed`.
- `atmosphere.gd` shows how rain particles are built; reuse the approach
  (GPUParticles3D, world space, restart on camera cuts).

## What to build
1. Slam detection at 2 or 3 points along the bow (both sides). Spray volume
   ∝ max(0, relative downward velocity − 1.5 m/s)², capped.
2. Spray: GPU particles launched up and outward from the bow flare, then
   carried by the apparent wind (drag toward it with a time constant of
   about 0.3 s) and gravity. White, soft, alpha fading; a few hundred
   particles per slam.
3. Green water: when the local sea surface rises above the rail at the bow
   or waist, emit a sheet (a quad strip or particles) flowing inboard and
   aft, and draining through the scuppers over a few seconds. Drive it from
   the same CPU surface query.
4. Sound hook: emit a signal `slammed(strength)` from the new node, so that
   `scripts/sound.gd` can play a thump (optional: implement it there with a
   synthesised low boom like `_make_step`).

## Constraints
- Headless: skip particle creation (no RenderingDevice) but keep the slam
  signal computation, so it can be tested.
- Deterministic with a frozen clock (no slams while frozen).
- Low tier (`--quality=low`) uses half the particles.

## Proof
- `tests/bow_spray.gd` (headless): with Fair weather heading into the sea,
  the slam signal stays near 0. In a Gale head sea at speed, several slams
  happen within 60 s. With the ship furled and still in Calm, there are none.
- Capture a new tour shot `31_bow_spray` (Gale, looking forward from the
  forecastle at a frozen moment just after a slam; choose the time by
  simulating like `07_ship_rolling` does in `dev/tour.gd`).
