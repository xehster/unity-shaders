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
| Surfaces | `ConcreteTriplanar`, `FrostedGlass`, `DirtyGlass` (+ the `DirtyGlass/` wiping kit), `InteriorMapping`, `GradientMap` (UGUI), `GradientMapMesh` |
| Atmosphere | `HeightFog`, `RetroDither`, `CrtVhs`, `GradientSkybox` |
| Gameplay | `Hologram`, `MoveOutline`, `ForceField`, `ImpactMarks` (+ the `ImpactMarks/` driver), `FlyingCrying` (+ the `FlyingCrying/` art and its baker) |
| Recolour | `PaletteSwap`, `PaletteSwapUI` (+ the `PaletteSwap/` textures) |
| Particles | `FireParticleSystem`, `SparkBurst`, `Droplets`, each with its material |

## Dropping them into a project

Copy the files **with their `.meta`**, or Unity assigns new GUIDs and your materials lose
track of the shader. Keep `PS1LitChromaticPass.hlsl` next to `PS1LitChromatic.shader`.

Four of these do nothing on their own. `HeightFog`, `RetroDither` and `CrtVhs` are
full-screen passes and need a `FullScreenPassRendererFeature` on your renderer;
`PS1LitChromatic` needs a `RenderObjects` feature pointed at its `PurrChromaR` and
`PurrChromaB` passes.

`FrostedGlass` reads the scene behind it, so tick **Opaque Texture** on your URP asset or
it comes out flat. So does `DirtyGlass`, below, whenever **See Through** is on.

`DirtyGlass` is grime you can rub off. The dirt is a noise field with a moving threshold
rather than a picture faded in and out, so at low amounts only the densest spots survive
and they grow together as **Dirt** climbs, and 0 really is spotless. Colour takes a
swatch and a **Colour Range** that moves hue, saturation and value together, because
grime that only shifts hue reads as tinted plastic. Streaks, specks and the grime that
gathers where the surface turns away are separate layers over that.

Turn **See Through** off and it lights an ordinary texture instead of reading the scene,
which is how the same dirt goes on something that isn't glass; with it on, that texture
is still used, as a print on the pane. **Lay Dirt Out In UV** picks the domain: object
space has no seams and no pinched poles, so leave it off for a solid and turn it on for a
flat pane. **Use A Dirt Texture** swaps the noise for your own and keeps the rest.

Wiping is `Wipeable` from `DirtyGlass/`, which owns a mask in UV space and paints brush
dabs into it with `WipeBrush`. The shader lifts its threshold where the mask is bright,
so a half-wiped patch thins out and breaks up instead of going evenly pale, and the fine
noise holds the cloth back a little so grit is left along the edge of a stroke. Select
the object and press **Wipe it by hand** to drag over it in the Scene view, or leave
`wipeWithMouse` on for play mode; **Wash it all off** and **Dirty it up again** sit next
to it, and `creepBack` walks the dirt back over what was cleaned. It adds a MeshCollider,
since that is the only collider that can say which UV was clicked. Nothing in it knows
what dirt looks like, so any shader with a mask property can be wiped the same way.

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

`ImpactMarks` reads that same array and leaves damage where the hits landed: a punched
hole with cracks running off it for a round, a crushed patch and a web for something
blunt. The shapes follow how glass actually breaks, which is worth knowing before turning
the sliders. Radial cracks come first and they run long and dead straight, because they
follow the principal stress. The concentric ones are secondary and are **not rings**: each
runs from one radial across to the next and stops there, at its own radius, so no two
sectors line up. Draw them as full circles instead and every mark reads as a target. A
round arrives at a point, so its cracks start at one; a hammer grinds a patch to powder
first, and the cracks start at the edge of that.

**View Break Up** is the one to turn up: each piece bounded by two radials and two
concentrics gets its own small offset into the scene behind, so the view jumps between the
pieces. That sells the break far harder than the lines do, and it needs **Opaque Texture**
on the URP asset.

**Mark Style** decides what a mark *is* and is separate from **See Through**, which
decides what the surface is. A hole through glass and a pit in plaster are not the same
event: on Solid the hole stops being a hole, the cracks go dark and short, and a blunt hit
adds a dent.

Hits come in through `ImpactSurface` from `ImpactMarks/`: a ring buffer of 32, aged every
frame, with the kind, size and swing direction in a second array. Each mark's shape is
hashed from **where it landed**, never from its slot, or recycling a slot silently
restyles a mark already on screen. Select the object and press **Shoot it by hand** to
click at it in the Scene view, Shift-drag to swing, or leave `autoFire` on. Marks measure
straight-line distance from the hit, so a flat face is right and a strongly curved one
will look odd.

`SparkBurst` is a particle system rather than a shader: `Spark` draws the grains and the
`SparkBurst` component next to the prefab turns speed, reach and duration into one set of
fields, with `Fire()` for a single hit. It needs that script, so copy the three files
together.

`Droplets` is cartoon water that merges: put the component on an object, point it at a
sphere and tears run down it, clinging to each other on the way and drawing as one shape
under one outline. Copy `Droplets.shader`, `Droplets.cs` and the material together, and
add `EyeSources.cs` as well if the sources should be the eyes of `FlyingCrying`.

It is not a Unity ParticleSystem. Merging has to be drawn from every droplet at once, so
they are kept in a plain list and handed to the shader as an array, up to 32 of them. That
array is also why the outline can be shared: each droplet lays down a soft field, the
fields add up, and the shape is the line where the sum crosses a threshold. Turn the
bulge, refraction and highlight to zero for a bare outline and up for water.

Set `Path` to `Fall` and it needs no host and no sphere, which is the mode to use anywhere
else. It reads the depth and colour of the frame, so both **Depth Texture** and **Opaque
Texture** want ticking on the URP asset.

## License

MIT, everything here is mine. Use it, change it, no attribution needed.

The two `placeholder_*` textures next to the particle system are the exception. They're
web stand-ins so the effect renders on import, not mine to license, so swap them before
you ship anything.
