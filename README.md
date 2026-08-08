# Unity Shaders

Shaders I wrote for my own projects, kept here as plain files.

If you want to see them working, they live in
[Shader Gallery](https://github.com/xehster/shader-gallery): one Unity scene where every
shader sits on its own sphere, with clips of each. This repo is for when you just need a
file and don't feel like cloning a whole project.

**Unity 6** · Universal Render Pipeline · Shader Graph 17.0.3

## What's here

| | |
|---|---|
| Shader Graph | `Fire`, `Holographic` (+ `StripesHolo` subgraph), `FireParticles` |
| PS1 look | `PS1Lit`, `PS1LitTransparent`, `PS1LitChromatic` (+ `PS1LitChromaticPass.hlsl`) |
| Surfaces | `ConcreteTriplanar`, `GradientMap` (UGUI), `GradientMapMesh` |
| Atmosphere | `HeightFog`, `RetroDither`, `GradientSkybox` |
| Gameplay | `Hologram`, `MoveOutline` |
| Particles | `FireParticleSystem` prefab and its material |

## Dropping them into a project

Copy the files **with their `.meta`**, or Unity assigns new GUIDs and your materials lose
track of the shader. Keep `PS1LitChromaticPass.hlsl` next to `PS1LitChromatic.shader`.

Three of these do nothing on their own. `HeightFog` and `RetroDither` are full-screen
passes and need a `FullScreenPassRendererFeature` on your renderer; `PS1LitChromatic`
needs a `RenderObjects` feature pointed at its `PurrChromaR` and `PurrChromaB` passes.

`GradientMap` is the odd one out: it's built on Unity's built-in UI-Default, because
that's what a UGUI Image expects. For meshes use `GradientMapMesh`.

`Hologram` and `MoveOutline` take their tint through a MaterialPropertyBlock. Without one
they still draw, just in the default colour.

## License

MIT, everything here is mine. Use it, change it, no attribution needed.

The two `placeholder_*` textures next to the particle system are the exception. They're
web stand-ins so the effect renders on import, not mine to license, so swap them before
you ship anything.
