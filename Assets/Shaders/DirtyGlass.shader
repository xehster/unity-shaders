Shader "Custom/Dirty Glass"
{
    // Grime over a surface, and a mask that says where it has been rubbed off.
    //
    // The surface underneath is either the scene behind it, which makes it glass and
    // needs Opaque Texture on in the URP asset, or an ordinary texture, which makes it
    // any dirty thing at all. Everything above that line is the same either way.
    //
    // Dirt is a noise field with a moving threshold rather than a picture faded in and
    // out: at low amounts only the densest spots survive, and they grow into each other
    // as the amount climbs. Wiping lifts the threshold locally, so a half-wiped patch
    // thins out and breaks up the way a real one does instead of going evenly pale.
    Properties
    {
        [Header(Surface)]
        [Toggle] _SeeThrough ("See Through", Float) = 1
        _BaseMap ("Surface Texture", 2D) = "white" {}
        _BaseColor ("Surface Tint", Color) = (0.78, 0.88, 0.92, 1)
        _Refraction ("Refraction", Range(0, 1)) = 0.2
        _Smoothness ("Smoothness", Range(0, 1)) = 0.85
        _SpecStrength ("Specular", Range(0, 4)) = 1.1
        [Toggle] _ZWrite ("Write Depth", Float) = 0

        [Header(Dirt)]
        _Dirt ("Dirt", Range(0, 1)) = 0.6
        _DirtColor ("Dirt Colour", Color) = (0.36, 0.30, 0.22, 1)
        _ColorRange ("Colour Range", Range(0, 1)) = 0.35
        _Opacity ("Opacity", Range(0, 1)) = 0.9
        _Softness ("Edge Softness", Range(0.01, 1)) = 0.35
        _Scale ("Scale", Range(0.2, 40)) = 10
        _Contrast ("Patchiness", Range(0, 1)) = 0.5

        [Header(Character)]
        _Streaks ("Streaks", Range(0, 1)) = 0.4
        _StreakLength ("Streak Length", Range(1, 20)) = 6
        _Specks ("Specks", Range(0, 1)) = 0.35
        _EdgeGrime ("Edge Grime", Range(0, 1)) = 0.2
        _Smudge ("Smudge", Range(0, 1)) = 0.5

        [Header(Sources)]
        [Toggle] _DirtInUV ("Lay Dirt Out In UV", Float) = 0
        [Toggle] _UseDirtMap ("Use A Dirt Texture", Float) = 0
        _DirtMap ("Dirt Texture", 2D) = "white" {}
        _WipeMask ("Wipe Mask (filled by Wipeable)", 2D) = "black" {}
    }

    SubShader
    {
        // Transparent queue so the copy of the scene is already there to be read, even
        // though what comes out is solid.
        Tags { "RenderType"="Transparent" "Queue"="Transparent" "RenderPipeline"="UniversalPipeline" }

        Pass
        {
            Name "DirtyGlass"
            Tags { "LightMode"="UniversalForward" }

            ZWrite [_ZWrite]
            Cull Back

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareOpaqueTexture.hlsl"

            TEXTURE2D(_BaseMap);   SAMPLER(sampler_BaseMap);
            TEXTURE2D(_DirtMap);   SAMPLER(sampler_DirtMap);
            TEXTURE2D(_WipeMask);  SAMPLER(sampler_WipeMask);

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseMap_ST;
                float4 _DirtMap_ST;
                half4 _BaseColor;
                half4 _DirtColor;
                float _SeeThrough;
                float _Refraction;
                float _Smoothness;
                float _SpecStrength;
                float _Dirt;
                float _ColorRange;
                float _Opacity;
                float _Softness;
                float _Scale;
                float _Contrast;
                float _Streaks;
                float _StreakLength;
                float _Specks;
                float _EdgeGrime;
                float _Smudge;
                float _DirtInUV;
                float _UseDirtMap;
            CBUFFER_END

            #define TAPS 6
            #define DIRT_GOLDEN_ANGLE 2.3999632

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
                float2 uv         : TEXCOORD1;
                float3 normalWS   : TEXCOORD2;
                float3 viewWS     : TEXCOORD3;
            };

            Varyings vert (Attributes IN)
            {
                Varyings OUT;
                VertexPositionInputs p = GetVertexPositionInputs(IN.positionOS.xyz);
                OUT.positionCS = p.positionCS;
                OUT.positionOS = IN.positionOS.xyz;
                OUT.uv = IN.uv;
                OUT.normalWS = GetVertexNormalInputs(IN.normalOS).normalWS;
                OUT.viewWS = GetWorldSpaceNormalizeViewDir(p.positionWS);
                return OUT;
            }

            float Hash31 (float3 p)
            {
                p = frac(p * 0.3183099 + float3(0.11, 0.17, 0.13));
                p *= 17.0;
                return frac(p.x * p.y * p.z * (p.x + p.y + p.z));
            }

            float Noise (float3 x)
            {
                float3 i = floor(x);
                float3 f = frac(x);
                f = f * f * (3.0 - 2.0 * f);

                float2 c = float2(0.0, 1.0);
                float a = lerp(lerp(Hash31(i + c.xxx), Hash31(i + c.yxx), f.x),
                               lerp(Hash31(i + c.xyx), Hash31(i + c.yyx), f.x), f.y);
                float b = lerp(lerp(Hash31(i + c.xxy), Hash31(i + c.yxy), f.x),
                               lerp(Hash31(i + c.xyy), Hash31(i + c.yyy), f.x), f.y);
                return lerp(a, b, f.z);
            }

            float Fbm (float3 p)
            {
                float sum = 0.5 * Noise(p);
                sum += 0.25 * Noise(p * 2.03);
                sum += 0.125 * Noise(p * 4.01);
                return sum / 0.875;
            }

            /// Where the dirt is measured from. Object space suits a solid, since a 3D
            /// field has no seams and no pinched poles to give it away; UV suits a pane,
            /// or anything wearing a dirt texture, which needs a flat domain to live in.
            float3 DirtDomain (Varyings IN)
            {
                return _DirtInUV > 0.5
                    ? float3(IN.uv * _Scale, 0.0)
                    : IN.positionOS * _Scale;
            }

            half4 frag (Varyings IN) : SV_Target
            {
                float3 n = normalize(IN.normalWS);
                float3 v = normalize(IN.viewWS);
                float facing = saturate(dot(n, v));
                Light main = GetMainLight();

                float3 p = DirtDomain(IN);

                // the broad layer: either the noise or a texture standing in for it
                float patches = _UseDirtMap > 0.5
                    ? SAMPLE_TEXTURE2D(_DirtMap, sampler_DirtMap, TRANSFORM_TEX(IN.uv, _DirtMap)).r
                    : Fbm(p);

                // Streaks are the same noise with the run direction squashed, so what was
                // a blob is drawn out into a drip. That direction is object down, which
                // in UV space is v, which on an upright pane is the same thing.
                float3 drawn = float3(p.x, p.y / _StreakLength, p.z);
                float streak = Fbm(drawn * 1.7 + 21.3);
                float field = lerp(patches, max(patches, streak * 0.95), _Streaks);

                // Value noise crowds around its middle, which would make the threshold
                // sweep past nearly everything at once and take the surface from clean to
                // caked in a narrow band of the slider. Pushing the field away from the
                // middle is what buys the slider its whole travel.
                field = saturate(0.5 + (field - 0.5) * (1.0 + _Contrast * 1.6));

                // grime gathers where the surface turns away, the way it does in a corner
                field = saturate(field + pow(1.0 - facing, 3.0) * _EdgeGrime);

                float grit = Noise(p * 4.0 + 51.7);

                // A cloth does not lift dirt evenly. Letting the fine noise hold the wipe
                // back a little leaves grit behind along the edge of a stroke, where the
                // mask is thin, while a spot gone over properly still comes up clean.
                float wiped = SAMPLE_TEXTURE2D(_WipeMask, sampler_WipeMask, IN.uv).r;
                wiped = saturate(wiped * 1.18 - grit * 0.18);

                float amount = _Dirt * saturate(1.0 - wiped);

                // The sweep runs from past the top of the field to past the bottom, so 0
                // really is spotless with the edge grime counted in and 1 really is
                // caked. It eases through the middle because that is where the noise
                // crowds: a straight sweep spends most of the slider there and the whole
                // surface turns over in a couple of hundredths.
                float d = amount - 0.5;
                float level = 0.5 - (0.48 * d + 4.46 * d * d * d);
                float edge = _Softness * 0.5;
                float cover = smoothstep(level - edge, level + edge, field);

                // A deposit is not a decal of one strength: thin at its edges, and only
                // where it has piled up does it stop the light. Without this the glass
                // reads as painted rather than dirty.
                cover *= lerp(0.55, 1.0, saturate(field * 1.15));

                // Specks are their own dirt, not part of the patches: grit sits where it
                // landed, whether or not there is grime around it. Kept as the top slice
                // of that same fine noise, and the slice widens as the surface gets dirtier.
                float gate = 1.0 - amount * 0.45;
                cover = max(cover, smoothstep(gate, gate + 0.05, grit) * _Specks);

                cover *= _Opacity;

                float2 screen = IN.positionCS.xy / _ScaledScreenParams.xy;
                float2 texel = 1.0 / _ScaledScreenParams.xy;
                float3 normalVS = TransformWorldToViewDir(n);
                float2 bend = normalVS.xy * _Refraction * 0.1;

                float3 surface;
                if (_SeeThrough > 0.5)
                {
                    // Dirt scatters what comes through it, so the smear is driven by how
                    // much dirt is in front of this pixel rather than being a fixed blur.
                    float reach = _Smudge * cover * 26.0;

                    float3 behind = 0;
                    [unroll]
                    for (int i = 0; i < TAPS; i++)
                    {
                        float step = (i + 0.5) / TAPS;
                        float angle = i * DIRT_GOLDEN_ANGLE;
                        float2 ring = float2(cos(angle), sin(angle)) * sqrt(step) * reach;
                        behind += SampleSceneColor(screen + bend + ring * texel);
                    }
                    // the texture is a print on the pane rather than dead weight here,
                    // and white, which is what it is unless something is assigned,
                    // leaves the view through the glass alone
                    surface = behind / TAPS * _BaseColor.rgb * SAMPLE_TEXTURE2D(
                        _BaseMap, sampler_BaseMap, TRANSFORM_TEX(IN.uv, _BaseMap)).rgb;
                }
                else
                {
                    float3 albedo = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap,
                        TRANSFORM_TEX(IN.uv, _BaseMap)).rgb * _BaseColor.rgb;
                    surface = albedo * (main.color * saturate(dot(n, main.direction)) * 0.75
                        + SampleSH(n) * 0.5 + 0.2);
                }

                // Colour: one slow wander through the field decides this patch's shade, so
                // neighbouring deposits differ but each one holds together. Hue, saturation
                // and value all move, because grime that only shifts hue reads as tinted
                // plastic. Range at 0 hands back the swatch exactly.
                float tone = Fbm(p * 0.31 + 7.7) - 0.5;
                float spot = Fbm(p * 1.9 + 33.1) - 0.5;

                float3 hsv = RgbToHsv(saturate(_DirtColor.rgb));
                hsv.x = frac(hsv.x + tone * _ColorRange * 0.22);
                hsv.y = saturate(hsv.y + spot * _ColorRange * 0.5);
                hsv.z = saturate(hsv.z * (1.0 + (tone + spot) * _ColorRange * 0.8));
                float3 grime = HsvToRgb(hsv);

                // thicker deposits sit darker, and the whole layer is matte, so it takes
                // the light flat rather than picking up the highlight
                grime *= lerp(1.15, 0.72, saturate(field));
                grime *= main.color * saturate(dot(n, main.direction)) * 0.55 + 0.6;

                float3 colour = lerp(surface, grime, cover);

                float3 h = normalize(main.direction + v);
                float spec = pow(saturate(dot(n, h)), exp2(_Smoothness * 9.0 + 1.0));
                colour += main.color * spec * _SpecStrength * (1.0 - cover);

                return half4(colour, 1.0);
            }
            ENDHLSL
        }
    }
}
