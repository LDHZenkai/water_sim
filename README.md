# water_sim
A pirate ship floating on an ultra realistic water surface.

Godot 4.7 project in `game/`. Run it with the launchers (`Play - High (RTX).bat`,
`Play - Low (fallback).bat`) or `godot --path game`.

## The water

The sea is simulated from physics. There are no scrolling normal maps or
texture packs: every wave comes from a measured ocean wave spectrum.

| Layer | What it is | Where |
| --- | --- | --- |
| Sea state | Fetch-limited JONSWAP wind sea (Hasselmann 1973) with Donelan-Banner directional spreading, plus a swell system | `ocean/sea_state.gd`, `ocean/default_sea.tres` |
| Long waves (> 12 m) | 32 explicit components drawn from the spectrum, evaluated identically on the CPU (ship buoyancy, swimming, tests) and in the vertex shader | `ocean/sea_state.gd`, `ocean/surface.gdshaderinc` |
| Short waves (12 m down to 5 cm) | GPU FFT (Tessendorf) in three cascades of 167 m, 30 m and 5 m, each owning one band of the same spectrum. Choppy horizontal displacement, Jacobian whitecaps that persist and decay, full mip chains | `ocean/fft_ocean.gd`, `ocean/compute/` |
| Reactive water | Exact-dispersion wave solver (Tessendorf's eWave) in a 128 m box around the ship. The hull presses on the water by its draft below the passing waves. Heave, pitch, roll and chop along the hull radiate real waves; a current draws a Kelvin wake; splashes ring outward. Foam is carried by the flow | `ocean/wake_sim.gd`, `ocean/compute/wake_*.glsl` |
| Optics | Fresnel sky reflection. Sun glitter roughness from the slope variance hidden in each pixel (LEAN mapping plus the Cox-Munk remainder). Water colour from absorption and backscatter coefficients. Crest glow from forward-scattered sunlight | `ocean/water.gdshaderinc`, `ocean/ocean.gdshader` |

### Changing the sea

Open `game/ocean/default_sea.tres` in the Godot inspector. Wind speed, fetch,
swell height, period and heading, and choppiness are physical quantities; the
rest follows from them. Stronger wind gives a steeper, higher, more broken sea
with more whitecaps. The ship's motion tests (`tests/local_waterline.gd`) bound
pitch to 4° and roll to 3° for the default sea.

### Command-line switches

Pass these after `--`, for example `godot --path game -- --ship-speed=5`.

| Switch | Effect |
| --- | --- |
| `--ship-speed=6` | Knots through the water, 0..12 (default 6; 0 anchors the ship). The sea streams past the hull, which makes a bow wave, Kelvin wake and turbulent stern wake |
| `--ocean-fft=off` | Disable the GPU FFT cascades (legacy detail maps) |
| `--ocean-wake=off` | Disable the reactive wave simulation |
| `--ocean-waves=32` | Long-wave component count (8..64) |
| `--quality=low` | 128² FFT and wake grids, 96 m wake box |

The GPU parts need a RenderingDevice (Forward+ or Mobile renderer). Under
`--headless` or the Compatibility renderer they switch off and the long waves
still run.

## Tests

```
godot --headless --path game -s tests/run_tests.gd   # main suite
godot --path game -s res://tests/gpu_ocean.gd         # GPU physics (needs a window)
```

`gpu_ocean.gd` checks the physics against theory:
- each FFT cascade's height and slope variance match the spectrum
- crests compress
- the field repeats exactly with its quantised period
- a resting hull stays still
- heave radiates waves at the deep-water dispersion wavelength
- a current produces a downstream wake inside the Kelvin wedge
- the boundary absorbs outgoing waves
