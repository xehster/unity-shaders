# Unity Shaders

**Three Shader Graph shaders and one particle system**, built for my own Unity projects.
Kept here so I can reuse them instead of rebuilding them each time — and so anyone
curious can see what they look like and how they're put together.

**Unity 6** · Universal Render Pipeline · Shader Graph 17.0.3

| | |
|---|---|
| **Shaders** | `Fire` · `Holographic` (+ `StripesHolo` subgraph) · `FireParticles` |
| **Particle system** | `FireParticleSystem` prefab + its material |

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

## Using them

1. These target URP. Make sure the **Universal RP** and **Shader Graph** packages are
   installed in your project.
2. Copy the `.shadergraph` files — **with their `.meta` files** — into your `Assets/`.
   `HolographicShader` needs `StripesHolo.ShaderSubGraph` alongside it.
3. Create a material from each shader and assign it.
4. For the particle system, drag the prefab in — it already points at its material.

## License

MIT — the three shaders, the subgraph and the particle system are mine; use them, change
them, no attribution needed.

The two `placeholder_*` textures are **not** covered by that licence — they're web
stand-ins so the effect renders on import. Swap them for your own before shipping
anything.
