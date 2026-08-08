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
| Surfaces | `ConcreteTriplanar`, `FrostedGlass`, `InteriorMapping`, `GradientMap` (UGUI), `GradientMapMesh` |
| Atmosphere | `HeightFog`, `RetroDither`, `CrtVhs`, `GradientSkybox` |
| Gameplay | `Hologram`, `MoveOutline`, `ForceField`, `FlyingCrying` (+ the `FlyingCrying/` art and its baker) |
| Recolour | `PaletteSwap`, `PaletteSwapUI` (+ the `PaletteSwap/` textures) |
| Particles | `FireParticleSystem` and `SparkBurst`, each with its material |

## Dropping them into a project

Copy the files **with their `.meta`**, or Unity assigns new GUIDs and your materials lose
track of the shader. Keep `PS1LitChromaticPass.hlsl` next to `PS1LitChromatic.shader`.

Four of these do nothing on their own. `HeightFog`, `RetroDither` and `CrtVhs` are
full-screen passes and need a `FullScreenPassRendererFeature` on your renderer;
`PS1LitChromatic` needs a `RenderObjects` feature pointed at its `PurrChromaR` and
`PurrChromaB` passes.

`FrostedGlass` reads the scene behind it, so tick **Opaque Texture** on your URP asset or
it comes out flat.

Two are UGUI shaders built on Unity's built-in UI-Default, because that's what an Image
expects: `GradientMap` and `PaletteSwapUI`. The mesh versions are `GradientMapMesh` and
`PaletteSwap`.

Both palette shaders want the two textures in `PaletteSwap/`. `Palettes.png` is the
colours, one row per palette and one column per slot, and the shader reads its size from
the texture, so add rows and columns and it follows. `PaletteIndex.png` is optional: it's
a demo index map, where the red channel is a slot number rather than a colour. Leave
**Source Is An Index Map** off and any ordinary texture works, keyed off its brightness.
Both must be imported point-filtered and uncompressed, and the index map with sRGB off,
or the numbers stop being numbers.

`InteriorMapping` and `FlyingCrying` want flat faces or a rounded solid, not a plane:
both cast the view ray onward into a grid laid out over the whole surface, so they have
nothing to say on a single quad.

`FlyingCrying` covers a surface in eyes that blink out of step and follow a point. It
reads one packed texture rather than the drawings themselves: redraw the parts in
`FlyingCrying/Source` and run **Shader Gallery > Bake Eye Mask** to pack them again. The
shapes live in the alpha, the lids run widest open to shut, and extra lid frames are
picked up on their own. Point the pupils with `_LookAt`, a world position whose `w` at 0
means watch the camera instead.

The name is from KOTEK, my first game. This thing was hand drawn in 2D back then and its
working name was flyingcrying, because it flew and it cried. The original is the avatar
on this account.

`Hologram` and `MoveOutline` take their tint through a MaterialPropertyBlock. Without one
they still draw, just in the default colour.

`ForceField` takes impact points the same way, as a `_Hits` array of object-space
positions with the age of each hit in `w`. Without any it's just a shield.

`SparkBurst` is a particle system rather than a shader: `Spark` draws the grains and the
`SparkBurst` component next to the prefab turns speed, reach and duration into one set of
fields, with `Fire()` for a single hit. It needs that script, so copy the three files
together.

## License

MIT, everything here is mine. Use it, change it, no attribution needed.

The two `placeholder_*` textures next to the particle system are the exception. They're
web stand-ins so the effect renders on import, not mine to license, so swap them before
you ship anything.
