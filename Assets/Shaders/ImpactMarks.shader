Shader "Custom/Impact Marks"
{
    // What a hit leaves behind: a punched hole with cracks running off it where a round
    // went through, a broad dent where something heavy landed.
    //
    // Hits arrive the way ForceField takes them, as an array of object-space positions
    // with the age of each in w, so anything already pushing _Hits works here. Each mark
    // is a field summed into the same pair of totals rather than a decal of its own,
    // which is why two holes close together grow one merged web instead of overlapping.
    //
    // The surface underneath is the scene behind it, which makes it glass, or an ordinary
    // texture, which makes it a wall. That switch is separate from the one that decides
    // what a mark *is*: a hole through glass and a pit in plaster are not the same event.
    Properties
    {
        [Header(Surface)]
        [Toggle] _SeeThrough ("See Through", Float) = 1
        _BaseMap ("Surface Texture", 2D) = "white" {}
        _BaseColor ("Surface Tint", Color) = (0.74, 0.85, 0.9, 1)
        _Refraction ("Refraction", Range(0, 1)) = 0.15
        _Smoothness ("Smoothness", Range(0, 1)) = 0.85
        _SpecStrength ("Specular", Range(0, 4)) = 1.1
        [Toggle] _ZWrite ("Write Depth", Float) = 0

        [Header(Marks)]
        [Enum(Glass,0,Solid,1)] _MarkStyle ("Mark Style", Float) = 0
        _Size ("Mark Size", Range(0.01, 0.5)) = 0.09
        _Variation ("Shape Variation", Range(0, 1)) = 0.6
        _Life ("Lifetime, 0 Is Forever", Range(0, 60)) = 0
        _Spread ("Spread Time", Range(0.01, 1)) = 0.12

        [Header(Bullet)]
        _Spokes ("Cracks", Range(0, 14)) = 7
        _CrackLength ("Crack Length", Range(0.1, 1)) = 0.8
        _CrackWidth ("Crack Width", Range(0.0005, 0.02)) = 0.004
        _Rings ("Rings", Range(0, 1)) = 0.5
        _Hole ("Hole Size", Range(0, 0.5)) = 0.14
        _Crush ("Crushed Rim", Range(0, 1)) = 0.5

        [Header(Melee)]
        _MeleeSize ("Melee Size", Range(0.5, 4)) = 1.8
        _MeleeStretch ("Melee Stretch", Range(1, 3)) = 1.5
        _MeleeWeb ("Melee Web", Range(0, 1)) = 0.7

        [Header(Shards)]
        _Shatter ("View Break Up", Range(0, 1)) = 0.45

        [Header(Colour)]
        _CrackColor ("Crack Colour", Color) = (1, 1, 1, 1)
        _CrackGlow ("Crack Brightness", Range(0, 3)) = 0.8
        _PitColor ("Pit Colour", Color) = (0.05, 0.04, 0.04, 1)
        _DustColor ("Crushed Colour", Color) = (0.86, 0.85, 0.82, 1)

        // marker: the gallery gives anything with this a cube. Marks measure straight-line
        // distance from the hit, which is right on a flat face and wrong on a ball.
        [HideInInspector] _WantsCube ("Wants A Cube", Float) = 1

        // Marker for ImpactSurface, which is how anything finds out this material takes
        // marks: _Hits is an array, and an array declared down in the code is invisible to
        // Material.HasProperty. Deliberately not ForceField's _AcceptsImpacts, or the
        // gallery rig would push its own four hits into the same array and the two drivers
        // would overwrite each other.
        [HideInInspector] _TakesMarks ("Takes Marks", Float) = 1
    }

    SubShader
    {
        Tags { "RenderType"="Transparent" "Queue"="Transparent" "RenderPipeline"="UniversalPipeline" }

        Pass
        {
            Name "ImpactMarks"
            Tags { "LightMode"="UniversalForward" }

            ZWrite [_ZWrite]
            Cull Back

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareOpaqueTexture.hlsl"

            TEXTURE2D(_BaseMap); SAMPLER(sampler_BaseMap);

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseMap_ST;
                half4 _BaseColor;
                half4 _CrackColor;
                half4 _PitColor;
                half4 _DustColor;
                float _SeeThrough;
                float _Refraction;
                float _Smoothness;
                float _SpecStrength;
                float _MarkStyle;
                float _Size;
                float _Variation;
                float _Life;
                float _Spread;
                float _Spokes;
                float _CrackLength;
                float _CrackWidth;
                float _Rings;
                float _Hole;
                float _Crush;
                float _MeleeSize;
                float _MeleeStretch;
                float _MeleeWeb;
                float _CrackGlow;
                float _Shatter;
            CBUFFER_END

            // Set per renderer, same shape ForceField uses: xyz is the hit in object
            // space, w is its age in seconds and 0 means the slot is empty. C# keeps the
            // age current, because _Time in Edit Mode runs on its own clock.
            //
            // _Style carries what kind of hit it was: x is 0 for a round and 1 for a
            // swing, y scales it, z is the swing direction as an angle in the surface
            // frame built below. All zeroes reads as a plain bullet at default size, so
            // pushing _Hits on its own is enough.
            #define MAX_HITS 32
            float4 _Hits[MAX_HITS];
            float4 _Style[MAX_HITS];

            #define TAU 6.2831853

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                float2 uv         : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 positionOS : TEXCOORD0;
                float3 normalOS   : TEXCOORD1;
                float2 uv         : TEXCOORD2;
                float3 normalWS   : TEXCOORD3;
                float3 viewWS     : TEXCOORD4;
            };

            Varyings vert (Attributes IN)
            {
                Varyings OUT;
                VertexPositionInputs p = GetVertexPositionInputs(IN.positionOS.xyz);
                OUT.positionCS = p.positionCS;
                OUT.positionOS = IN.positionOS.xyz;
                OUT.normalOS = IN.normalOS;
                OUT.uv = IN.uv;
                OUT.normalWS = GetVertexNormalInputs(IN.normalOS).normalWS;
                OUT.viewWS = GetWorldSpaceNormalizeViewDir(p.positionWS);
                return OUT;
            }

            float Hash11 (float x)
            {
                x = frac(x * 0.1031);
                x *= x + 33.33;
                return frac(x * (x + x));
            }

            float Hash21 (float a, float b)
            {
                return Hash11(a * 1.618 + b * 57.31 + 0.137);
            }

            /// Scattered specks: one per cell of a grid, jittered off its centre, each
            /// with its own size and its own strength, and each falling off to nothing at
            /// its own edge instead of filling the cell it lives in.
            ///
            /// A flat value per cell is cheaper but the cells are squares, and once they
            /// are more than a pixel or two across the grid shows. The neighbours are
            /// looked at for the same reason: without them no speck ever crosses a cell
            /// border and the lattice comes back.
            float Grains (float2 g, float seed)
            {
                float2 p = floor(g);
                float2 f = g - p;
                float most = 0;

                for (int j = -1; j <= 1; j++)
                for (int i = -1; i <= 1; i++)
                {
                    float2 b = float2(i, j);
                    float2 cell = p + b;

                    float2 at = b + float2(Hash21(cell.x * 1.3, cell.y + seed),
                                           Hash21(cell.x * 7.7 + 3.1, cell.y * 2.3 + seed));

                    // Skewed small on purpose. An even spread of sizes reads as sand;
                    // what crushed glass looks like is dust with the occasional piece
                    // that survived, so most rolls land tiny and a few land large.
                    float roll = Hash21(cell.x * 5.9, cell.y * 1.7 + seed);
                    float big = roll * roll * roll;
                    float size = 0.12 + 0.62 * big;

                    // and a piece catches the light where dust only dulls it
                    float peak = (0.35 + 0.5 * Hash21(cell.x * 2.1 + 9.3, cell.y + seed))
                        * lerp(0.85, 1.35, big);

                    float speck = 1.0 - smoothstep(size * 0.2, size, length(at - f));
                    most = max(most, speck * peak);
                }

                return most;
            }

            /// A wobble that goes round the angle once and joins up with itself, built
            /// from a hash per angular cell.
            ///
            /// Not a sine: a sine at four cycles is a four-leaf clover and at five it is a
            /// star, and the eye names the shape the moment it sees it. Hashed cells have
            /// no period to find. Returns roughly -0.5 to 0.5.
            float AngleWobble (float ang, float cells, float seed)
            {
                float t = (ang / TAU + 0.5) * cells;
                float i = floor(t);
                float f = t - i;
                f = f * f * (3.0 - 2.0 * f);

                float lo = i - cells * floor(i / cells);
                float hi = (i + 1.0) - cells * floor((i + 1.0) / cells);

                return lerp(Hash21(lo, seed), Hash21(hi, seed), f) - 0.5;
            }

            /// How far one radial crack runs, as a share of the mark. Wanted in two
            /// places: for the crack itself, and for the arcs slung between it and its
            /// neighbour, which cannot reach past the shorter of the two.
            ///
            /// Most of them are long, because on a real pane a radial tends to run until
            /// something stops it. The index wraps, or the last sector and the first
            /// disagree about the crack they share.
            float SpokeReach (float slot, float count, float seed, float variation)
            {
                float s = slot - count * floor(slot / count);
                return lerp(1.0, 0.55 + Hash21(s + 7.0, seed) * 1.0, variation);
            }

            /// A frame lying in the surface, so a mark can be measured in two dimensions.
            /// It is built from the fragment's own normal rather than the hit's, which is
            /// the same thing on a flat face and drifts on a curved one. C# builds it the
            /// same way when it works out a swing angle; the two have to agree.
            void SurfaceFrame (float3 n, out float3 t, out float3 b)
            {
                float3 up = abs(n.z) < 0.9 ? float3(0, 0, 1) : float3(1, 0, 0);
                t = normalize(cross(n, up));
                b = cross(n, t);
            }

            /// Everything one hit does to this fragment, added into the running totals.
            /// crack is the bright line work, hole is what has gone, dust is the ring of
            /// pulverised material around it.
            void AddMark (float3 positionOS, float3 n, int i, inout float crack,
                          inout float hole, inout float dust, inout float2 skew)
            {
                float4 hit = _Hits[i];
                float age = hit.w;
                if (age <= 0) return;

                // Age retracts the mark rather than fading it out: it pulls back into its
                // densest part and goes. A mark that dissolves evenly reads as a decal
                // having its alpha turned down, which is exactly what it is not.
                float shrink = 1.0;
                if (_Life > 0)
                {
                    if (age > _Life) return;
                    shrink = 1.0 - smoothstep(0.65, 1.0, age / _Life);
                }

                float4 style = _Style[i];
                bool melee = style.x > 0.5;
                float scale = style.y > 0 ? style.y : 1.0;

                float seed = Hash11(dot(hit.xyz, float3(37.13, 71.7, 13.9)) + 4.7);

                float radius = _Size * scale * (melee ? _MeleeSize : 1.0);
                radius *= lerp(1.0, 0.65 + seed * 0.7, _Variation);
                radius *= shrink;
                if (radius <= 0) return;

                float3 d = positionOS - hit.xyz;
                if (dot(d, d) > radius * radius) return;

                float3 tx, ty;
                SurfaceFrame(n, tx, ty);
                float2 e = float2(dot(d, tx), dot(d, ty));

                // a swing lands along its own direction, so the mark is drawn out that way
                if (melee)
                {
                    float sa, ca;
                    sincos(style.z, sa, ca);
                    e = float2(e.x * ca + e.y * sa, -e.x * sa + e.y * ca);
                    e.x /= _MeleeStretch;
                }

                float r = length(e) / radius;
                if (r > 1.0) return;

                float ang = atan2(e.y, e.x);

                // the cracks race out over the first moments and the hole is simply there
                float spread = saturate(age / _Spread);

                // --- the hole and its crushed rim ------------------------------------
                float holeR = 0;
                if (!melee)
                {
                    // wobbled so it is not a circle punched out with a hole saw
                    holeR = _Hole * (1.0 + (seed - 0.5) * _Variation);
                    holeR *= 1.0 + _Variation * (0.55 * AngleWobble(ang, 7.0, seed + 4.3)
                                               + 0.30 * AngleWobble(ang, 13.0, seed + 9.1));

                    hole = max(hole, 1.0 - smoothstep(holeR * 0.85, holeR, r));

                    float rim = holeR * (1.0 + _Crush * 0.9);
                    float ring = (1.0 - smoothstep(holeR, rim, r)) * smoothstep(holeR * 0.75, holeR, r);
                    // the same grain as the crush zone, so the two match, but kept
                    // lighter: this ring is thin and specks would eat it
                    dust += ring * _Crush * 0.8
                        * (0.45 + 0.85 * Grains(e / radius * 30.0 + seed * 11.0, seed + 4.0));
                }

                // --- the crush zone a blunt blow leaves --------------------------------
                // A round arrives at a point and its cracks start there. A hammer head
                // does not: it grinds a patch of glass to powder and the cracks start at
                // the edge of that. Both facts come straight out of how the two break.
                float crushR = 0;
                if (melee)
                {
                    crushR = 0.17 * (1.0 + _Variation * (0.6 * AngleWobble(ang, 6.0, seed + 8.7)
                                                       + 0.35 * AngleWobble(ang, 11.0, seed + 2.9)));
                    float crushed = smoothstep(crushR, crushR * 0.7, r);

                    // It is powdered glass, so it wants grain rather than an even patch:
                    // separate specks, each solid in the middle and gone by its own edge,
                    // with next to nothing between them. Cells across the surface, not
                    // around the angle, because polar ones are wedges and they comb the
                    // grain into spikes pointing outward.
                    float grit = Grains(e / radius * 26.0 + seed * 17.0, seed);
                    crushed *= 0.1 + 1.05 * grit;

                    dust += crushed * _MeleeWeb * 0.85;

                    // On a wall the same blow leaves a dent, so it wants a dark middle as
                    // well as the light scuff. Never on glass: hole is what gets clipped
                    // there, and a hammer does not punch a clean disc out of a pane.
                    if (_MarkStyle > 0.5) hole = max(hole, crushed * 0.55);
                }

                // where the line work has to keep clear of, whichever kind this is
                float inner = melee ? crushR : holeR;

                // --- radial cracks, the primary ones ----------------------------------
                // These come first and they run: on a real pane they often reach the
                // frame. Everything else hangs off them.
                float count = max(2.0, floor(_Spokes * (melee ? 1.6 : 1.0)
                    * lerp(1.0, 0.5 + seed * 1.1, _Variation)));

                float sector = (ang / TAU + 0.5) * count;
                float slot = floor(sector);
                float shard = 0;   // how many arcs this fragment is outside of
                float local = sector - slot;

                // Which way it points is random; how straight it runs is not. A radial
                // crack follows the principal stress and holds its line, so the jitter
                // sets the angle once and nothing bends it along the way.
                float jitter = (Hash21(slot, seed) - 0.5) * _Variation * 0.9;
                float da = abs(frac(local - 0.5 - jitter) - 0.5);   // turns to the nearest spoke
                float arc = da / count * TAU * r * radius;          // and the same in object units

                float len = SpokeReach(slot, count, seed, _Variation) * _CrackLength * spread;

                float along = saturate(1.0 - r / max(len, 0.02));
                float width = _CrackWidth * (0.35 + 0.65 * along);
                float spoke = saturate(1.0 - arc / max(width, 1e-5)) * along;

                spoke *= smoothstep(inner * 0.8, inner * 1.25 + 1e-4, r);
                if (Hash21(slot * 13.7, seed + 2.3) < 0.18 * _Variation) spoke = 0;
                crack += spoke;

                // --- concentric cracks, the secondary ones ------------------------------
                // The part I had wrong twice. These are not rings: each one runs from one
                // radial crack across to the next and stops there, so a sector carries its
                // own two or three at its own radii and the neighbouring sector carries
                // different ones. Drawn as complete circles instead, off one radius for
                // the whole mark, they read as a target, which is exactly what happened.
                if (_Rings > 0)
                {
                    // an arc hangs between two radials, so it cannot outrun the shorter
                    float span = min(len, SpokeReach(slot + 1.0, count, seed, _Variation)
                        * _CrackLength * spread);

                    int arcs = melee ? 3 : 2;
                    float lo = inner * 1.8 + 0.08;
                    // stopping well inside the radials, which carry on past the last of
                    // them: an arc sitting on their tips closes the mark off like a rim
                    float hi = span * 0.7;

                    for (int a = 0; a < arcs; a++)
                    {
                        // Not every sector gets every arc. Filling them all in is what
                        // pulls the neighbours into line with each other and rebuilds the
                        // rings this was meant to get rid of; leaving gaps is also what
                        // real glass does.
                        if (Hash21(slot * 9.7 + a * 3.3, seed + 5.1) < 0.45) continue;

                        // one arc per band, but the bands overlap, so a sector and the one
                        // beside it step apart instead of lining up
                        float band = (a + Hash21(slot * 3.1 + a * 17.7, seed) * 1.7 - 0.35) / arcs;
                        float at = lerp(lo, hi, saturate(band));
                        if (at <= inner || at >= span) continue;

                        // it sags outward between the two it is hanging from, but only
                        // slightly: a real one is nearly straight across the sector
                        float bow = (0.25 - (local - 0.5) * (local - 0.5)) * at
                            * 0.08 * Hash21(slot + a * 5.3, seed + 1.7);

                        // and it does not run parallel to a circle either: one end sits
                        // higher up its radial than the other
                        bow += (local - 0.5) * at * 0.3
                            * (Hash21(slot * 2.7 + a * 8.9, seed + 6.4) - 0.5);

                        float off = abs(r - at - bow) * radius;
                        crack += saturate(1.0 - off / max(width * 0.6, 1e-5))
                            * _Rings * spread;

                        // this fragment is outside that arc, so it belongs to a piece one
                        // further out: two radials and two arcs bound a shard, and that is
                        // the whole of its identity
                        if (r > at + bow) shard += 1.0;
                    }
                }

                // A crack is a place where the glass stopped being one sheet, and each
                // piece now sits at its own slight angle. Nudging what is seen through
                // each one by a fixed amount is what makes the view break up across the
                // pieces, and that reads as broken far more than the lines do.
                if (_Shatter > 0)
                {
                    float2 tilt = float2(Hash21(slot * 3.7 + shard * 11.3, seed) - 0.5,
                                         Hash21(slot * 8.1 + shard * 5.9, seed + 2.7) - 0.5);

                    // held off the middle, which is powder rather than pieces, and eased
                    // out at the rim so the last shard does not end on a step
                    float held = smoothstep(inner, inner * 1.6 + 0.05, r) * saturate(1.0 - r);
                    skew += tilt * _Shatter * held * spread * 0.02;
                }
            }

            half4 frag (Varyings IN) : SV_Target
            {
                float3 nOS = normalize(IN.normalOS);

                float crack = 0, hole = 0, dust = 0;
                float2 skew = 0;
                for (int i = 0; i < MAX_HITS; i++)
                    AddMark(IN.positionOS, nOS, i, crack, hole, dust, skew);

                crack = saturate(crack);
                dust = saturate(dust);

                // On glass a hole is a hole. On anything solid it is a pit with a bottom,
                // so the surface stays and only its colour changes.
                if (_MarkStyle < 0.5) clip(0.5 - hole);

                float3 n = normalize(IN.normalWS);
                float3 v = normalize(IN.viewWS);
                Light main = GetMainLight();
                float ndotl = saturate(dot(n, main.direction));

                float2 screen = IN.positionCS.xy / _ScaledScreenParams.xy;
                float3 normalVS = TransformWorldToViewDir(n);
                float2 bend = normalVS.xy * _Refraction * 0.1 + skew;

                float3 surface;
                if (_SeeThrough > 0.5)
                {
                    surface = SampleSceneColor(screen + bend) * _BaseColor.rgb
                        * SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap,
                            TRANSFORM_TEX(IN.uv, _BaseMap)).rgb;
                }
                else
                {
                    float3 albedo = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap,
                        TRANSFORM_TEX(IN.uv, _BaseMap)).rgb * _BaseColor.rgb;
                    surface = albedo * (main.color * ndotl * 0.75 + SampleSH(n) * 0.5 + 0.2);
                }

                float3 colour = surface;

                if (_MarkStyle < 0.5)
                {
                    // glass: a crack is a surface that suddenly faces every which way, so
                    // it catches light the rest of the pane is letting straight through
                    colour = lerp(colour, _DustColor.rgb * (main.color * ndotl * 0.4 + 0.7), dust);
                    colour = lerp(colour, _CrackColor.rgb * (0.55 + 0.45 * ndotl), crack);
                    colour += _CrackColor.rgb * crack * _CrackGlow * 0.3;
                }
                else
                {
                    colour = lerp(colour, _PitColor.rgb, hole);
                    colour = lerp(colour, _DustColor.rgb * (main.color * ndotl * 0.6 + 0.5), dust);
                    // no bright line work on a wall: what a round leaves there is a groove
                    colour = lerp(colour, _PitColor.rgb, saturate(crack * 0.75) * (1.0 - hole));
                }

                float3 h = normalize(main.direction + v);
                float spec = pow(saturate(dot(n, h)), exp2(_Smoothness * 9.0 + 1.0));
                colour += main.color * spec * _SpecStrength * (1.0 - saturate(dust + crack));

                return half4(colour, 1.0);
            }
            ENDHLSL
        }
    }
}
