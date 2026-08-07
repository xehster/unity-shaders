# Unity Shaders

**Three Shader Graph shaders, a particle system and a set of hand-written ShaderLab
shaders**, built for my own Unity projects. Kept here so I can reuse them instead of
rebuilding them each time — and so anyone curious can see what they look like and how
they're put together.

**Unity 6** · Universal Render Pipeline · Shader Graph 17.0.3

| | |
|---|---|
| **Shader Graph** | `Fire` · `Holographic` (+ `StripesHolo` subgraph) · `FireParticles` |
| **Particle system** | `FireParticleSystem` prefab + its material |
| **Hand-written (ShaderLab/HLSL)** | PS1 family · `ConcreteTriplanar` · `HeightFog` · `RetroDither` · `Hologram` · `MoveOutline` · `GradientSkybox` |

---

# Shaders

## 1. Fire

![Fire shader](docs/fire-preview.gif)

Turbulent flame surface — animated noise drives the flame shape, a colour ramp takes it
from deep violet through magenta to white-hot highlights. Meant to be applied to geometry,
not to particles.

`Assets/Shaders/Fire.shadergraph`

---

## 2. Holographic

![Holographic shader](docs/holographic-preview.gif)

Sci-fi hologram: horizontal scanlines, soft rim falloff and transparency, so it reads as
a projection rather than a solid. The scanline pattern lives in its own subgraph, so it
can be reused on other materials.

In a level, on a building:

![Holographic shader in a scene](docs/holographic-in-scene.gif)

`Assets/Shaders/HolographicShader.shadergraph` · `Assets/Shaders/StripesHolo.ShaderSubGraph`

---

## 3. Fire Particles

![Fire particles in isolation](docs/fire-particles-preview.gif)

The particle-facing counterpart to the Fire shader — additive, driven by a flipbook and a
noise displacement map, and built to be rendered by a particle system rather than on a mesh.

`Assets/Shaders/FireParticles.shadergraph`

---

# Particle system

![Fire particles driving a thruster](docs/fire-particles-in-scene.gif)

The Fire Particles shader above is what colours it; this prefab is what makes it move.
Emission curves, shape, lifetime and velocities are the part that actually makes it read
as a thruster jet.

`Assets/ParticleSystem/FireParticleSystem.prefab` · `Assets/ParticleSystem/FireParticlesMaterial.mat`

### Placeholder textures — swap these out

The two textures wired into the material are **placeholders**, included only so the
effect renders as soon as you import it:

| File | Slot | What to replace it with |
|---|---|---|
| `placeholder_noise.jpg` | `_DisplacementNoise` | any greyscale noise / turbulence map |
| `placeholder_fire_flipbook.png` | `_FireShapes` | any 5×5 flipbook sheet of flame or smoke |

They're stand-ins grabbed from around the web and are not mine to license — drop your own
in and the effect keeps working.

---

# Hand-written shaders (ShaderLab / HLSL)

Written for an in-development project of mine with a "PS1 geometry, modern lighting"
look. No Shader Graph here - plain ShaderLab with HLSL passes, URP forward path.

Every gif below is the same bouncing sphere under the same light, so the shaders can be
compared against each other rather than against a nice backdrop.

## PS1 Lit

![PS1 Lit](docs/ps1-lit.gif)

The base of the family. Two artifacts do the work: vertices snap to a virtual low-res
grid, so the silhouette wobbles as things move, and UVs are interpolated without
perspective correction, so textures warp across long triangles. Everything under that is
a normal URP lit pass - realtime shadows, additional lights, fog, ambient SH, emission.

`_VertexSnapPixels` is the grid height (240 looks right, 0 turns snapping off) and
`_AffineAmount` fades the warp, so you can go from a hint of it to full 1996.

The same shader with HDR emission, if you have bloom in your stack:

![PS1 Lit with emission](docs/ps1-lit-emissive.gif)

`Assets/Shaders/PS1Lit.shader`

---

## PS1 Lit Chromatic

![PS1 Lit Chromatic](docs/ps1-lit-chromatic.gif)

Per-object chromatic aberration, and deliberately not a post effect: two extra passes
(`PurrChromaR` and `PurrChromaB`) redraw the object with the red and blue channels pushed
apart, so only materials on this shader get fringes while everything around them stays
clean. They need a `RenderObjects` feature on your renderer filtering for those two pass
names - without it the shader still renders, just without fringes.

The shift is zero at screen centre and grows towards the edges, like a real lens. An
object framed dead centre shows almost nothing, which is worth knowing before you decide
`_ChromaShift` is broken. Roughly 3x the raster cost, so it's for hero objects.

`Assets/Shaders/PS1LitChromatic.shader` · `Assets/Shaders/PS1LitChromaticPass.hlsl`

---

## PS1 Lit Transparent

![PS1 Lit Transparent](docs/ps1-lit-transparent.gif)

Alpha-blended sibling for glass, crystal and anything you want to see through. Standard
`SrcAlpha OneMinusSrcAlpha` with depth writes off, alpha comes from `_BaseColor`, snap and
warp behave exactly as in the base shader.

`Assets/Shaders/PS1LitTransparent.shader`

---

## Concrete Triplanar

![Concrete Triplanar](docs/concrete-triplanar.gif)

Box projection blended by the surface normal, so no UV unwrap is needed - handy on meshes
that came out of a pile of boolean operations. It rebuilds a Blender concrete setup: base
colour times AO, lerped towards white, roughness into smoothness, whiteout normal blend.

Projection is in world space by default. Textures stay put as objects move through them
and neighbouring meshes line up seamlessly, which is what you want for architecture - but
a rotating object just slides through a stationary pattern and reads as if it isn't
turning at all. The `_OBJECT_SPACE_TRIPLANAR` keyword switches to mesh coordinates: the
texture sticks to the surface and turns with it, which is what the gif above shows. Leave
it off for anything with badly uneven scale, like floors and stretched cubes, or the
texture smears along the long axis.

`Assets/Shaders/ConcreteTriplanar.shader`

---

## Hologram

![Hologram](docs/hologram.gif)

The placement ghost: additive fresnel with scanlines scrolling along world height. The
placer tints it through a MaterialPropertyBlock - blue for a valid spot, red for a
blocked one. `_BeamMode` reworks it for a LineRenderer ribbon, sending pulses along the
length instead of scanlines, which is what the projector beam uses.

`Assets/Shaders/Hologram.shader`

---

## Move Outline

![Move Outline](docs/move-outline.gif)

Classic inverted hull. The mesh is drawn a second time with front faces culled and
vertices pushed out along their normals, so only a rim around the silhouette survives the
depth test. Goes in a second material slot on top of the normal one, and keeps the same
vertex snap so the rim jitters in step with the mesh instead of floating around it.

`Assets/Shaders/MoveOutline.shader`

---

## Atmosphere and full-screen passes

These three don't sit on a mesh, so there's nothing to put on a sphere.

`HeightFog.shader` is analytic exponential height fog with drifting density pockets. It
runs before post-processing, so bloom and grading treat the fog as part of the scene, and
takes its colour from `RenderSettings.fogColor` - point a day/night script at that and the
fog follows. `_DensityMultiplier` is left free for scripts; mine thins the fog while the
player is indoors so the outdoor soup doesn't fill the rooms.

`RetroDither.shader` posterizes each channel and lays a 4x4 Bayer pattern over the result,
at full resolution with no downscaling. It runs after post-processing, so the film grade
gets crushed along with everything else. If you record gifs of your game with this on:
per-pixel noise changing every frame ruins GIF inter-frame compression, and adding a
second dither in the palette pass only doubles the file size for no visible gain.

`GradientSkybox.shader` is a zenith / horizon / ground gradient with a sun disc and haze,
dithered against banding.

## Notes before you drop these in

- They target **URP forward**. `HeightFog` and `RetroDither` need a
  `FullScreenPassRendererFeature` on your renderer, and `PS1LitChromatic` needs a
  `RenderObjects` feature pointed at its two pass names, or none of them do anything.
- `PS1LitChromatic` needs `PS1LitChromaticPass.hlsl` next to it.
- `Hologram` and `MoveOutline` expect their tint through a MaterialPropertyBlock; without
  one they still render, just in the default colour.

## Using them

1. These target URP. Make sure the **Universal RP** and **Shader Graph** packages are
   installed in your project.
2. Copy the `.shadergraph` files — **with their `.meta` files** — into your `Assets/`.
   `HolographicShader` needs `StripesHolo.ShaderSubGraph` alongside it.
3. The hand-written ones are plain `.shader` files, same deal — copy them with their
   `.meta`, and keep `PS1LitChromaticPass.hlsl` next to `PS1LitChromatic.shader`.
4. Create a material from each shader and assign it.
5. For the particle system, drag the prefab in — it already points at its material.

## License

MIT — the shader graphs, the subgraph, the particle system and the hand-written shaders
are all mine; use them, change them, no attribution needed.

The two `placeholder_*` textures are **not** covered by that licence — they're web
stand-ins so the effect renders on import. Swap them for your own before shipping
anything.
