# water_sim
A sailing simulation: a Spanish galleon on a physically simulated sea, with
live weather, storms, wind-driven sails and a crew member (you) who has to
keep their feet on a moving deck.

Godot 4.7 project in `game/`. Run it with the launchers (`Play - High (RTX).bat`,
`Play - Low (fallback).bat`) or `godot --path game`.

## Controls

| Key | On deck | At the helm |
| --- | --- | --- |
| W A S D | Walk | W / S set or take in sail; A / D put the helm over to port / starboard |
| Mouse | Look | Look |
| Shift | Hurry (a jog; nobody sprints on a pitching deck) | |
| C | Crouch (steadier footing) | |
| **Q** (hold) | **Brace**: a hand on the rail or a line. You keep your feet in a knockdown, but shuffle | Always braced on the wheel |
| Space | Jump / let go of a rope | |
| E | Interact: doors, chest, compass, **take the helm** at the wheel on the poop deck | Step away from the helm |
| **Tab** | **Weather menu** | Weather menu |
| Esc | Release the mouse (closes the weather menu) | |

## The weather

Press **Tab** for the weather menu. Every slider sets a target and the weather
eases toward it the way weather does: the wind freshens over a minute, the
sky closes in, rain arrives, and the sea builds over the "sea builds over"
time. **Build the sea now** skips the wait.

| Slider | What it drives |
| --- | --- |
| Wind speed, wind from | The wind on the rig (apparent wind, heel, speed), the wind sea's height, steepness and whitecaps, the rain's slant, the sound in the rigging |
| Gusts | Turbulent gusts and veers (7 s, 19 s and 53 s scales), and squalls in a blow |
| Fetch | Open water upwind: short fetch gives a young, short, steep sea; long fetch a big developed one |
| Swell height, period, from | A distant storm's swell, independent of the local wind |
| Cloud cover | Fair-weather cumulus up to an unbroken overcast that hides the sun |
| Rain | Driving rain (streaks follow the apparent wind), a wet, slippery deck, murk |
| Mist and fog | Visibility |
| Lightning | Strikes with thunder arriving at the speed of sound |

Presets: **Calm, Fair, Fresh, Gale, Storm** (Beaufort 2, 5, 6, 8 and 10).
With *Weather changes on its own* ticked, fronts move through every few
minutes and the weather worsens or eases on its own; moving a slider takes
manual control.

How it works (`scripts/weather.gd`, `ocean/sea_state.gd`):
- The sea is **layered**. When the wind changes, a new wind sea starts to grow
  from the new state while the old one decays, crossfading in energy, so the
  surface never jumps. The ship, the ocean shader and the wake simulation all
  read the same live components.
- **Whitecaps** follow Monahan and O'Muircheartaigh (1980): the fraction of
  white water grows as U^3.41 (0.5% at 8 m/s, 22% at 25 m/s). The shader breaks
  crests where the surface is most compressed, with the threshold set from
  the measured coverage. From force 8 the wind lays foam in streaks.
- **Sky** (`scripts/aligned_sky.gdshader`, `scripts/atmosphere.gd`): a cloud
  deck drifting with the wind at altitude, an overcast that dims the sun and
  softens shadows, fog matched to the cloud base so the horizon dissolves in
  rain, lightning bolts that light the clouds.
- **Sound** (`scripts/sound.gd`) is synthesised at start-up, with no sound
  files: wind and a whistle in the shrouds, the sea and the rush along the
  hull, rain, canvas slatting when the sails luff, timbers creaking as she
  works, footsteps on planking, thunder. The cabin muffles everything outside.

## Sailing the ship

Climb to the poop deck, look at the wheel and press **E** to take the helm.
The readout shows speed, heading, sail, helm, the wind and the point of
sail, the weather, heel, and warnings.

The ship (`ocean/buoyancy.gd`):
- **Sails:** square-rig drive from the apparent wind. Nothing within about 60°
  of the wind, weak abeam, fastest with the wind on the quarter. In 8 m/s that
  gives about 6 kn on a beam reach and 7 kn on a broad reach.
- **Hull:** a few hundred tonnes of galleon, so she gathers way over half a
  minute. Wave-making resistance climbs steeply toward hull speed (~13 kn),
  so even a gale cannot drive her much past 12 kn. Only surfing can.
- **Rudder:** it bites only with way on. Full rudder turns about 2°/s.
- **Heel:** the sails' side force heels her about 2° in a fresh breeze and 18°
  in a storm under full canvas. Past 12° she is **overpressed**: reef (S).
- **The sails themselves** (`exploration/sails.gd`, `sails.gdshader`) fill
  with the apparent wind, shiver and slat when too close to it, are taken
  aback (pressed against the mast) with the wind ahead, and furl up to the
  yards when taken in.

Physically, the hull stays at the world origin and the sea drifts past it:
long waves, FFT cascades and the wake simulation. Every coordinate stays
small however far you sail.

## The novel mechanic: reading the sea

Heavy weather is something to sail, not just watch.

- **Surfing.** Running before a big following sea at speed, the hull is picked
  up by the faces and driven down them by gravity. You can surf well past
  hull speed ("Surfing down the face of a sea!").
- **Broaching.** Surf with the sea on the quarter and it slews her round
  broadside. Meet her with the helm, or she lies beam-on to the next sea.
- **Rogue waves.** In seas over 3.5 m, and on demand from the menu, the weather
  builds a rogue wave the way the ocean does: **dispersive focusing**. A group
  of ordinary wave components, each travelling at its own speed, is phased to
  arrive in step at the ship's future position. Half a minute out it is an
  unremarkable part of the sea; then it stands up into a wall of water twice
  the significant height. The lookout calls its bearing about 20 s ahead:
  **turn her bow into it**.
  - Met bow-on, she climbs it and loses way.
  - Beam-on, she is **knocked down**, rolling some 30°: anyone on deck not
    **bracing (Q)** is thrown across the deck into the lee rail.
  - From astern, she is **pooped**: slewed round with the deck swept.

The weather menu shows the ship's log: distance sailed, best speed, the
longest surf, and every rogue wave, met or not.

## Life on deck

Moving about is meant to feel like being an ordinary 1.8 m person on a
moving 35 m ship, not a floating camera (`scripts/sea_legs.gd`,
`scripts/player.gd`).
- **Apparent gravity.** What you feel is gravity minus the acceleration of
  the deck under your feet: heave, and roll and pitch about axes metres below
  you (worse on the poop deck or aloft), plus the hull's surge and turning.
  Your "down" tilts and your weight changes: you walk slower uphill and
  quicker downhill, feel light as she drops into a trough and heavy as she
  rises.
- **Footing.** A standing person tips at a sideways-to-vertical force ratio
  of about 0.25 (motion-induced interruptions, Graham 1990); walking or
  hurrying, sooner. Beyond it you stagger downhill; beyond shoe friction
  (lower on a wet deck) you slide. Crouching helps; bracing (Q) holds.
- **The body.** Steps bob your head once per step and sway it once per
  stride, with footfalls on the planks. Your head lags the deck's lurches on
  your neck, and your inner ear holds your view to apparent gravity, so a
  lurch tilts the horizon for a moment. Landings jolt.

## The water

The sea is simulated from physics. There are no scrolling normal maps or
texture packs: every wave comes from a measured ocean wave spectrum.

| Layer | What it is | Where |
| --- | --- | --- |
| Sea state | Fetch-limited JONSWAP wind sea (Hasselmann 1973) with Donelan-Banner directional spreading, plus a swell system, driven live by the weather | `ocean/sea_state.gd`, `ocean/default_sea.tres` |
| Long waves (> 12 m) | Explicit components drawn from the spectrum (32 per sea layer, up to 96 live), evaluated identically on the CPU (ship motion, swimming, tests) and in the vertex shader | `ocean/sea_state.gd`, `ocean/surface.gdshaderinc` |
| Short waves (12 m down to 5 cm) | GPU FFT (Tessendorf) in three cascades of 167 m, 30 m and 5 m, each owning one band of the same spectrum. Choppy horizontal displacement, Jacobian whitecaps that persist and decay, full mip chains | `ocean/fft_ocean.gd`, `ocean/compute/` |
| Reactive water | Exact-dispersion wave solver (Tessendorf's eWave) in a 128 m box around the ship. The hull presses on the water by its draft below the passing waves. Heave, pitch, roll and chop along the hull radiate real waves; her way through the water draws a Kelvin wake; splashes ring outward. Foam is carried by the flow | `ocean/wake_sim.gd`, `ocean/compute/wake_*.glsl` |
| Optics | Fresnel sky reflection. Sun glitter roughness from the slope variance hidden in each pixel (LEAN mapping plus the Cox-Munk remainder). Water colour from absorption and backscatter coefficients. Crest glow from forward-scattered sunlight | `ocean/water.gdshaderinc`, `ocean/ocean.gdshader` |

The default sea (`game/ocean/default_sea.tres`) is the Fair preset's; the
weather menu changes it live. The ship's motion tests
(`tests/local_waterline.gd`) bound pitch to 4° and roll to 3° for it.

## Command-line switches

Pass these after `--`, for example `godot --path game -- --weather=Gale`.

| Switch | Effect |
| --- | --- |
| `--weather=Fair` | Starting weather: Calm, Fair, Fresh, Gale or Storm, fully developed |
| `--weather-dynamic=on` | `off` keeps the weather where you set it (no fronts) |
| `--sails=3` | Starting sail, 0..3 (furled .. full, default full) |
| `--ship-speed=0` | Starting speed in knots, 0..12. 0 starts furled and still. Default: the steady speed for the starting sail |
| `--ocean-fft=off` | Disable the GPU FFT cascades (legacy detail maps) |
| `--ocean-wake=off` | Disable the reactive wave simulation |
| `--ocean-waves=32` | Long-wave components per sea layer (8..64) |
| `--quality=low` | 128² FFT and wake grids, 96 m wake box, half the rain |

The GPU parts need a RenderingDevice (Forward+ or Mobile renderer). Under
`--headless` or the Compatibility renderer they switch off and the long waves
still run.

## Tests

```
godot --headless --path game -s tests/run_tests.gd      # main suite
godot --headless --path game -s res://tests/helm.gd     # sailing physics and the helm
godot --headless --path game -s res://tests/weather.gd  # weather, sea layers, rogue waves, surfing, sails, menu, footing
godot --path game -s res://tests/gpu_ocean.gd            # GPU physics (needs a window)
```

`weather.gd` checks:
- a new wind builds a new sea without a jump and settles to its height
- a rogue group focuses to its full crest at the ship and is dispersed 30 s earlier
- a following gale makes her surf past her steady speed, and a quartering sea makes her broach
- full canvas is overpressed in a storm, reefed it is not
- a beam-on breaking sea knocks her down 20 to 45°
- the sails fill on a reach and are taken aback head to wind
- the menu drives the weather, and presets move the sliders
- a knockdown throws an unbraced player across the deck, while a braced one holds
- the lookout calls a rogue wave and the log counts it

`gpu_ocean.gd` checks the physics against theory:
- each FFT cascade's height and slope variance match the spectrum
- crests compress
- the field repeats exactly with its quantised period
- a resting hull stays still
- heave radiates waves at the deep-water dispersion wavelength
- a current produces a downstream wake inside the Kelvin wedge
- the boundary absorbs outgoing waves

## Working with Codex (or any coding agent)

`AGENTS.md` describes the project for coding agents: layout, conventions,
how to run the tests and captures, and the traps. `docs/codex/` holds
self-contained task briefs sized for one agent session each.
