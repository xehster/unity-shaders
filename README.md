# Unity Shaders

Shaders and effects from my Unity projects. I keep the files here and try them out in
[Shader Gallery](https://github.com/xehster/shader-gallery).

Unity 6 · Universal Render Pipeline · Shader Graph 17.0.3

![Shader Gallery](docs/gallery.gif)

Recorded with the gallery's built-in GIF recorder. I haven't figured out a good way to
show every effect in the gallery yet, so some look wrong here. A sphere doesn't do much
for a sword or a shower of sparks. The descriptions below explain what the effects are
meant to look like; this page covers the ones currently on display.

## Surfaces

### PS1 Lit

[PS1Lit.shader](Assets/Shaders/PS1Lit.shader) — vertices snap to a pixel grid and textures
warp with perspective, with URP lighting and shadows on top. This is the base look for
objects in Purrfield.

### PS1 Lit Chromatic

[PS1LitChromatic.shader](Assets/Shaders/PS1LitChromatic.shader) — the PS1 material with
red and blue fringes offset from the surface. Keep `PS1LitChromaticPass.hlsl` beside it.
The extra colour passes need a Render Objects renderer feature using the `PurrChromaR`
and `PurrChromaB` LightMode tags.

### PS1 Lit Transparent

[PS1LitTransparent.shader](Assets/Shaders/PS1LitTransparent.shader) — the transparent
version of PS1 Lit, with the same vertex snapping and texture warp.

### PS1 Lit Emissive

The glowing sample uses [PS1Lit.shader](Assets/Shaders/PS1Lit.shader) too. It is a
material setup, not another shader: the emission colour lights up the surface while
the geometry keeps its PS1 wobble.

### ConcreteTriplanar

[ConcreteTriplanar.shader](Assets/Shaders/ConcreteTriplanar.shader) — textured concrete
projected from three directions, so it works on walls and awkward meshes without a UV
unwrap. Uses colour, normal, roughness and AO maps. World projection lines up across
objects; object projection keeps the texture attached when an object turns.

### PrototypeGrid

[PrototypeGrid.shader](Assets/Shaders/PrototypeGrid.shader) — a measuring grid for
blockouts. The lines are drawn in the shader and keep their spacing in metres when a
mesh is scaled. Fine divisions and heavier major lines make sizes easier to read.
Keep `PrototypeGridInput.hlsl` and `PurrGI.hlsl` beside it.

### Frosted Glass

[FrostedGlass.shader](Assets/Shaders/FrostedGlass.shader) — cloudy glass that bends and
blurs the scene behind it. Frost, grain, tint and refraction are separate controls.
Needs **Opaque Texture** enabled on the URP asset.

### Dirty Glass

[DirtyGlass.shader](Assets/Shaders/DirtyGlass.shader) — dirt that builds up in patches,
with streaks and specks on top. It can cover transparent glass or an ordinary opaque
surface. Lowering Dirt breaks the patches apart instead of just fading the whole thing.

The `DirtyGlass/` folder contains the wiping tools. `Wipeable` paints a mask where you
rub the surface, and dirt can slowly creep back afterwards. The component's inspector
has Scene view controls for wiping, washing and resetting the dirt. See Through needs
**Opaque Texture**.

### Interior Mapping

[InteriorMapping.shader](Assets/Shaders/InteriorMapping.shader) — rooms behind a flat
surface, drawn by tracing the view into a grid of interiors. The apparent depth changes
as the camera moves. Use it on a box or building facade to get windows with depth
without modelling each room.

### Impact Marks

[ImpactMarks.shader](Assets/Shaders/ImpactMarks.shader) — bullet holes, crushed patches
and cracks. Glass breaks into pieces that shift the view behind them; solid surfaces
get dark cracks and dents instead of transparent holes.

`ImpactMarks/ImpactSurface.cs` feeds the hits to the shader. Its inspector lets you
shoot at the object in the Scene view or Shift-drag for a directional hit. The glass
view distortion needs **Opaque Texture**. Flat surfaces suit the marks best.

## Colour

### gmap (mesh)

[GradientMapMesh.shader](Assets/Shaders/GradientMapMesh.shader) — recolours a mesh by
mapping the source texture's brightness between shadow and light colours. Keeps the
texture's shading and can preserve dark outlines.

### gmap

[GradientMap.shader](Assets/Shaders/GradientMap.shader) — the uGUI version of the same
idea, for Images on a Canvas. It includes UI masking and clipping support.

### Palette Swap

[PaletteSwap.shader](Assets/Shaders/PaletteSwap.shader) — recolours a mesh from a palette
texture. It can read explicit colour indices or use the brightness of an ordinary
image. Each palette occupies one row, so switching rows changes the colour scheme.

### Palette Swap (UI)

[PaletteSwapUI.shader](Assets/Shaders/PaletteSwapUI.shader) — palette swapping for uGUI,
with the same index-map and brightness modes. Both versions use the textures in
`PaletteSwap/`. Import palettes point-filtered and uncompressed; index maps also need
sRGB off.

## Holograms and energy

### Hologram

[Hologram.shader](Assets/Shaders/Hologram.shader) — the placement preview in Purrfield:
a transparent glowing outline with scrolling scanlines. Its tint tells you whether a
machine can be placed there. A separate beam mode draws pulses along a LineRenderer.

### PS1 Lit + MoveOutline

[MoveOutline.shader](Assets/Shaders/MoveOutline.shader) draws a coloured rim around the
PS1-lit object. In the game it marks movable machines and changes colour for the one
under the crosshair. The outline follows the same vertex snapping as the surface.

### Holographic

[HolographicShader.shadergraph](Assets/Shaders/HolographicShader.shadergraph) — a Shader
Graph holographic material with scrolling stripes and a glowing edge. Keep the
`StripesHolo` subgraph with it.

### Force Field

[ForceField.shader](Assets/Shaders/ForceField.shader) — a transparent shield with a
moving honeycomb pattern and a bright rim. Hits send rings out from their contact
points. The surface wraps around the sphere without a texture seam; a script supplies
up to four hit positions and their ages through `_Hits`.

### Pulse Field — Variant of Force Field

[PulseField_VariantOf_ForceField.shader](Assets/Shaders/PulseField_VariantOf_ForceField.shader)
uses the shield's volume and rim for an aura around a robot. Rings travel outward along
the ground and fade with height. In Purrfield the damage and repair coils use this
same effect in different colours.

### Beam Tube — Variant of Hologram

[BeamTube_VariantOf_Hologram.shader](Assets/Shaders/BeamTube_VariantOf_Hologram.shader)
is related to Hologram's beam mode. In the game it draws a cylindrical beam along a
chain of points, with pulses running down its length, brighter edges and colour that
can change along the beam. It needs a tube mesh with normals, vertex colours and U
running along the length.

### Electric Arc

[ElectricArc.shader](Assets/Shaders/ElectricArc.shader) — lightning with a pale core,
coloured glow and a flickering current running along it. In the game a LineRenderer's
jagged path is rebuilt every few frames, making the bolt jump between its endpoints.
The shader draws the light; the script supplies the path.

### EnergyBlade

[EnergyBlade.shader](Assets/Shaders/EnergyBlade.shader) — Purrfield's summoned energy
sword. Energy streams from the forearm modules, then the grip, guard and blade appear
in sequence. The blade has a near-white core and coloured edges: water ripples,
electrical flashes, fire or flowing air. It swells during a heavy wind-up and dissolves
when the guard drops.

`EnergySwordMesh.cs` builds the sword with the UV data the shader expects. `_Reveal`
controls its appearance, and `_Mode` chooses the element. The streams, swing trail and
weapon behaviour belong to the game's controller.

## Fire, water and particles

### Fire

[Fire.shadergraph](Assets/Shaders/Fire.shadergraph) — an animated fire material made in
Shader Graph. Scrolling texture layers provide the movement and colour. This is the
material sample on a mesh.

### FireParticles

[FireParticles.shadergraph](Assets/Shaders/FireParticles.shadergraph) — the fire material
for particles, shown separately so its surface settings can be adjusted.

### FireParticleSystem

[FireParticleSystem.prefab](Assets/ParticleSystem/FireParticleSystem.prefab) — the actual
particle setup using the fire material. Rising particles give the flame its shape and
movement; the prefab and material are in `Assets/ParticleSystem/`.

### FireGround

[FireGround.shader](Assets/Shaders/FireGround.shader) — a patch of fire on the floor.
It looks like hot embers and glowing cracks over a scorched surface, with an uneven
edge fading into the ground. In Purrfield it can flare up or shift towards a purple
plasma colour. Uses `SurfaceShape.hlsl` and `PurrGI.hlsl` on a flattened cylinder.

### Puddle

[Puddle.shader](Assets/Shaders/Puddle.shader) — a shallow puddle with a dark wet rim,
sky reflections and small ripples. In the game, walking through it sends rings across
the water. It can become electrically charged or darken and swirl into a portal.

Use it on a flattened cylinder with `SurfaceShape.hlsl` and `PurrGI.hlsl`. The idle
movement is built in; a script supplies the footstep ripples.

### Spark

[Spark.shader](Assets/Shaders/Spark.shader) — round spark grains with a hot core, a soft
halo and individual flicker. It uses particle colour, age and a stable random value
from the particle renderer.

### SparkBurst

[SparkBurst.prefab](Assets/ParticleSystem/SparkBurst.prefab) — the burst setup using
Spark. The `SparkBurst` component controls speed, reach and duration, with `Fire()` for
a single burst. Keep the prefab, script and material together.

### Wall Slide Spark — Variant of Spark

[WallSlideSpark_VariantOf_Spark.shader](Assets/Shaders/WallSlideSpark_VariantOf_Spark.shader)
draws short streaks and four-point sparkles instead of round grains. In Purrfield,
sliding along a wall throws showers of sparks from the robot's feet. Most are small
bright dashes with gaps between them; a few burst into stars, and slower embers linger
behind.

The streaks use stretched particles, and the stars use ordinary billboards. The
renderer needs these vertex streams in order: Position, Color, UV, SizeXY, Speed,
AgePercent, StableRandomX.

### Flying Crying

[FlyingCrying.shader](Assets/Shaders/FlyingCrying.shader) covers a surface in eyes that
blink independently and follow a point or the camera. The packed eye texture is in
`FlyingCrying/`; its source drawings and editor baker are there too.

The name comes from KOTEK, my first game, where the original was hand drawn in 2D.
It flew and it cried. That version is still my account avatar.

### Droplets

[Droplets.shader](Assets/Shaders/Droplets.shader) — cartoon drops that gather, run down
a sphere and merge under one outline before falling off. Refraction and highlights
can make them look more like water, or be turned down for a simpler drawn shape.

The component in `Assets/ParticleSystem/Droplets.cs` handles the drops; this isn't a
Unity ParticleSystem. `EyeSources.cs` connects their starting points to Flying Crying's
eyes. Fall mode also works without a sphere. Needs **Depth Texture** and **Opaque
Texture** on the URP asset.

## Procedural experiments

These are raymarched shapes drawn inside a mesh. The object supplies the space to draw
in; the visible shape is calculated by the shader.

### 3dFractalOrganic

[3DFractalOrganicShader.shader](Assets/Shaders/3DFractalOrganicShader.shader) — a dark,
morphing body with a neon core, fused spikes and orbiting rings. The shape breathes
and pulses; the rings and colour separation can be adjusted independently.

### 3DFractalShader

[3dFractalShader.shader](Assets/Shaders/3dFractalShader.shader) — a folded, morphing form
with a dark body and glowing energy. A simpler experiment than the organic version,
with controls for scale, folding and animation speed.

### BiblicalRings_CrystalDome

[BiblicalRings_SecondTry.shader](Assets/Shaders/BiblicalRings_SecondTry.shader) — rotating
metal rings carrying eyes under shiny glass domes. The iris colours, eye count and
inner/outer eye visibility are adjustable.

### BiblicalRings_TrueDomeLenses

[BiblicalRings_Ophanim_Broken.shader](Assets/Shaders/BiblicalRings_Ophanim_Broken.shader)
— another ring-and-eye experiment, with raised lenses and concentric iris patterns.
The old filename is still there; this version has separate controls for ring spacing,
lens height and gloss.

### CyberEntity_OriginalMaterial

[MechanicalDiaphragm.shader](Assets/Shaders/MechanicalDiaphragm.shader) — a perforated
outer shell around a moving internal mechanism and an energy core. Hole expansion
opens the shell; inverting the holes leaves patches in place of the openings.

### CyberRibbons_ComplexShell

[CyberRibbons.shader](Assets/Shaders/CyberRibbons.shader) — a shell of twisted armour
ribbons with pulsing energy. The ribbons can spread apart, change thickness and taper
towards their tips.

### CyberShell_FractalFold

[DifferentCyberRibbons.shader](Assets/Shaders/DifferentCyberRibbons.shader) — a folded
shell with glowing nodes. Complexity and fold angle change its structure; Open /
Disassemble pulls the form apart.

### FractalShader

[FractalShader.shader](Assets/Shaders/FractalShader.shader) — a glowing, continuously
inverting fractal with violet, cyan, green and pink colour changes. Repeated folds
and twists produce the internal detail.

## Behind the shelves

These affect the gallery as a whole rather than occupying their own shelf slots.

**[Gradient Skybox](Assets/Shaders/GradientSkybox.shader)** colours the sky with a gradient.
**[Height Fog](Assets/Shaders/HeightFog.shader)** adds height-based haze to the scene.
**[Retro Dither](Assets/Shaders/RetroDither.shader)** adds the dithered screen treatment.
The latter two run as Full Screen Pass renderer features.

## Using the files

Copy a shader with its `.meta` and any accompanying includes, textures or components.
The `.meta` files keep Unity's references intact. Most materials can be adjusted in
the ordinary material inspector; effects driven by hits, particles or custom geometry
also need the setup described above.

## License

MIT; see [LICENSE](LICENSE).

The two `placeholder_*` textures beside the particle system are web stand-ins, not
mine to license. Replace them before shipping. The concrete textures in the gallery
project are placeholders too and aren't covered by this repository's license.
