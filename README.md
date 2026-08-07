# Unity Shaders

A personal collection of Shader Graph shaders I built for my own Unity projects.
Kept here so I can reuse them instead of rebuilding them each time — and so anyone
curious can see what they look like and how they're put together.

**Unity 6** · Universal Render Pipeline · Shader Graph 17.0.3

---

## Fire

![Fire shader](docs/fire-preview.gif)

Turbulent flame surface — animated noise drives the flame shape, a colour ramp takes it
from deep violet through magenta to white-hot highlights. Used as a surface material
rather than a particle effect.

`Assets/Shaders/Fire.shadergraph`

---

## Holographic

![Holographic shader](docs/holographic-preview.gif)

Sci-fi hologram: horizontal scanlines, soft rim falloff and transparency, so it reads as
a projection rather than a solid. The scanline pattern lives in its own subgraph, so it
can be reused on other materials.

In a level, on a building:

![Holographic shader in a scene](docs/holographic-in-scene.gif)

`Assets/Shaders/HolographicShader.shadergraph` · `Assets/Shaders/StripesHolo.ShaderSubGraph`

---

## Fire Particles

![Fire particles driving a thruster](docs/fire-particles-in-scene.gif)

The particle-facing version of the fire — additive, built to be driven by a particle
system. Above it's running as a thruster jet; on its own it looks like this:

![Fire particles in isolation](docs/fire-particles-preview.gif)

`Assets/Shaders/FireParticles.shadergraph`

The particle system itself is included as a prefab — emission curves, shape, lifetime and
velocities are the part that actually makes it read as a jet:

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

## Using them

1. These target URP. Make sure the **Universal RP** and **Shader Graph** packages are
   installed in your project.
2. Copy the `.shadergraph` files — **with their `.meta` files** — into your `Assets/`.
   `HolographicShader` needs `StripesHolo.ShaderSubGraph` alongside it.
3. Create a material from each shader and assign it.

## License

MIT — the shaders, the subgraph and the particle system are mine; use them, change them,
no attribution needed.

The two `placeholder_*` textures are **not** covered by that licence — they're web
stand-ins so the effect renders on import. Swap them for your own before shipping
anything.
