Shader "Purrfield/PrototypeGrid"
{
    // Measuring grid for blockout and prototyping.
    //
    // The whole point is that it does NOT stretch with the object. A grid TEXTURE on an ordinary
    // material is mapped through the mesh's own 0..1 UVs, so scaling a cube to 4x1x2 stretches the
    // same square over four metres and the material tells you nothing about size. Here the grid is
    // generated from world position instead, so one cell is one metre no matter what the object is
    // scaled to: that same cube reads 4 cells by 1 by 2, and two objects standing next to each
    // other line up because both are measuring the same world.
    //
    // It is also drawn rather than sampled - no texture, no UV unwrap, no resolution to run out of
    // when the camera comes close. The lines are kept a constant thickness ON SCREEN using screen
    // space derivatives (fwidth), which is what keeps distant floors from turning into aliased
    // moire and near walls from showing fat blurry bands.
    //
    // Lit through UniversalFragmentPBR like everything else, so a blockout sits in the real scene
    // lighting and you can judge a space by it instead of by a flat unlit overlay.
    Properties
    {
        [Header(Grid)]
        _CellSize     ("Cell Size (metres)", Float) = 1.0
        _MajorEvery   ("Major Line Every N Cells", Float) = 5
        _FineDivisions("Fine Cells Per Cell (0 = off)", Float) = 10
        _LineWidth    ("Minor Line Width (pixels)", Range(0.5, 6)) = 1.0
        _MajorWidth   ("Major Line Width (pixels)", Range(0.5, 8)) = 2.0
        _FineWidth    ("Fine Line Width (pixels)", Range(0.3, 4)) = 0.7

        // Where cell zero is. Corner is the one that makes the grid a ruler for THIS object: the
        // lines start exactly on its lowest corner, so three of its faces sit on lines and the
        // leftover along each axis is the fractional part of its size, readable at a glance.
        // World keeps every object measuring the same world grid, which is what you want when you
        // are lining several pieces up with each other rather than sizing one.
        [KeywordEnum(World, Corner, Pivot)] _Anchor ("Grid Origin", Float) = 1

        [Header(Colours)]
        _BaseColor    ("Base", Color) = (0.22, 0.24, 0.28, 1)
        _LineColor    ("Minor Line", Color) = (0.42, 0.46, 0.52, 1)
        _MajorColor   ("Major Line", Color) = (0.85, 0.90, 1.0, 1)
        _FineColor    ("Fine Line", Color) = (0.30, 0.33, 0.38, 1)

        [Header(Surface)]
        _Smoothness   ("Smoothness", Range(0, 1)) = 0.15
        _Metallic     ("Metallic", Range(0, 1)) = 0.0
        _Sharpness    ("Triplanar Sharpness", Range(1, 16)) = 8.0

        // World: the grid belongs to the world and objects sliding through it slide through the
        // grid too. Attached: it belongs to the object and travels with it, still in real metres -
        // object space is multiplied back up by the object's scale, because raw object space is
        // exactly the 0..1-style stretching this shader exists to avoid.
        [Toggle(_ATTACHED_SPACE)] _AttachedSpace ("Attach Grid To Object", Float) = 0

        // Matches the rest of the project's materials so a blockout piece jitters like the world
        // around it. Set to 0 while actually measuring something.
        _VertexSnapPixels ("Vertex Grid Height (0 = off)", Float) = 240
    }

    SubShader
    {
        Tags { "RenderType" = "Opaque" "Queue" = "Geometry" "RenderPipeline" = "UniversalPipeline" }

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode" = "UniversalForward" }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile_fragment _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile_fragment _ _SHADOWS_SOFT
            #pragma multi_compile _ _SCREEN_SPACE_OCCLUSION
            #pragma multi_compile _ _FORWARD_PLUS
            #pragma multi_compile _ LIGHTMAP_ON
            #include_with_pragmas "Packages/com.unity.render-pipelines.universal/ShaderLibrary/ProbeVolumeVariants.hlsl"
            #pragma multi_compile _ DIRLIGHTMAP_COMBINED
            #pragma multi_compile_fog
            #pragma shader_feature_local _ATTACHED_SPACE
            #pragma shader_feature_local _ANCHOR_WORLD _ANCHOR_CORNER _ANCHOR_PIVOT

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "PurrGI.hlsl"
            #include "PrototypeGridInput.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                float2 lightmapUV : TEXCOORD1;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 positionWS : TEXCOORD0;
                float3 normalWS   : TEXCOORD1;
                float3 gridPos    : TEXCOORD2;   // what the grid is measured in, metres
                float3 gridNormal : TEXCOORD3;   // same space, for the triplanar blend
                float  fogFactor  : TEXCOORD4;
                DECLARE_LIGHTMAP_OR_SH(lightmapUV, vertexSH, 5);
            };

            Varyings vert (Attributes IN)
            {
                Varyings o = (Varyings)0;

                float3 wp = TransformObjectToWorld(IN.positionOS.xyz);
                float3 wn = TransformObjectToWorldNormal(IN.normalOS);

                o.positionWS = wp;
                o.normalWS   = wn;

                #if defined(_ATTACHED_SPACE)
                    // Object space carries no size of its own - a 4 m cube and a 1 m cube are both
                    // 1 unit across in it. Scaling it back up by the transform's own scale is what
                    // keeps a cell a metre while still letting the grid ride along with the object.
                    o.gridPos    = IN.positionOS.xyz * ObjectScale();
                    o.gridNormal = normalize(IN.normalOS);
                #else
                    o.gridPos    = wp - GridAnchorWS();
                    o.gridNormal = normalize(wn);
                #endif

                o.positionCS = ApplyVertexSnap(TransformWorldToHClip(wp));
                o.fogFactor  = ComputeFogFactor(o.positionCS.z);

                OUTPUT_LIGHTMAP_UV(IN.lightmapUV, unity_LightmapST, o.lightmapUV);
                OUTPUT_SH(wn, o.vertexSH);
                return o;
            }

            /// One plane's worth of grid: how much of this pixel is line, 0..1.
            ///
            /// abs(frac(uv - 0.5) - 0.5) is the distance to the nearest cell edge in cells;
            /// dividing by fwidth converts that to a distance in PIXELS, which is the whole trick -
            /// it is what makes a line the same thickness whether the surface is a metre away or
            /// fifty, and what keeps the far end of a floor from aliasing into moire.
            float GridMask(float2 uv, float widthPixels)
            {
                float2 toEdge = abs(frac(uv - 0.5) - 0.5);
                float2 pixels = toEdge / max(fwidth(uv), 1e-6);
                return 1.0 - saturate(min(pixels.x, pixels.y) / max(widthPixels, 1e-3));
            }

            /// Grid on all three planes at once, blended by how much each one faces the camera-
            /// facing normal. Box projection rather than UVs, so it works on any mesh - a
            /// boolean-heavy blockout piece has no sensible unwrap and does not need one.
            float TriplanarGrid(float3 p, float3 n, float cell, float widthPixels)
            {
                float3 w = pow(abs(n), _Sharpness);
                w /= max(w.x + w.y + w.z, 1e-5);

                float x = GridMask(p.yz / cell, widthPixels);
                float y = GridMask(p.xz / cell, widthPixels);
                float z = GridMask(p.xy / cell, widthPixels);

                return x * w.x + y * w.y + z * w.z;
            }

            half4 frag (Varyings IN) : SV_Target
            {
                float cell = max(_CellSize, 1e-3);
                float3 gp = IN.gridPos;
                float3 gn = normalize(IN.gridNormal);

                float minor = TriplanarGrid(gp, gn, cell, _LineWidth);

                // Every Nth line drawn heavier. Reading "how many cells is that" off an unbroken
                // field of identical lines means counting them one by one; a heavier line every
                // five turns it into something you can read at a glance, which is the entire
                // reason for a measuring grid.
                float majorCell = cell * max(_MajorEvery, 1.0);
                float major = TriplanarGrid(gp, gn, majorCell, _MajorWidth);

                // Painted coarsest-last so the heavier line always wins where they coincide -
                // every major line is also a minor and a fine one, and letting the fine line paint
                // over it would break the very hierarchy that makes the grid readable.
                float3 albedo = _BaseColor.rgb;

                if (_FineDivisions >= 2.0)
                {
                    float fine = TriplanarGrid(gp, gn, cell / _FineDivisions, _FineWidth);
                    albedo = lerp(albedo, _FineColor.rgb, fine);
                }

                albedo = lerp(albedo, _LineColor.rgb, minor);
                albedo = lerp(albedo, _MajorColor.rgb, major);

                SurfaceData s = (SurfaceData)0;
                s.albedo     = albedo;
                s.metallic   = _Metallic;
                s.smoothness = _Smoothness;
                s.occlusion  = 1.0;
                s.alpha      = 1.0;

                float3 normalWS = normalize(IN.normalWS);

                InputData inp = (InputData)0;
                inp.positionWS = IN.positionWS;
                inp.normalWS   = normalWS;
                inp.viewDirectionWS = GetWorldSpaceNormalizeViewDir(IN.positionWS);
                inp.shadowCoord = TransformWorldToShadowCoord(IN.positionWS);
                inp.fogCoord    = IN.fogFactor;
                inp.bakedGI     = PURR_SAMPLE_GI(IN.lightmapUV, IN.vertexSH, IN.positionWS, normalWS, IN.positionCS);
                inp.normalizedScreenSpaceUV = GetNormalizedScreenSpaceUV(IN.positionCS);
                inp.shadowMask  = unity_ProbesOcclusion;

                half4 color = UniversalFragmentPBR(inp, s);
                color.rgb = MixFog(color.rgb, IN.fogFactor);
                return color;
            }
            ENDHLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode" = "ShadowCaster" }
            ZWrite On ColorMask 0

            HLSLPROGRAM
            #pragma vertex vertS
            #pragma fragment fragS
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "PrototypeGridInput.hlsl"

            float3 _LightDirection;
            float3 _LightPosition;

            struct A { float4 positionOS : POSITION; float3 normalOS : NORMAL; };
            struct V { float4 positionCS : SV_POSITION; };

            V vertS (A IN)
            {
                V o;
                float3 wp = TransformObjectToWorld(IN.positionOS.xyz);
                float3 wn = TransformObjectToWorldNormal(IN.normalOS);
                #if defined(_CASTING_PUNCTUAL_LIGHT_SHADOW)
                    float3 lightDir = normalize(_LightPosition - wp);
                #else
                    float3 lightDir = _LightDirection;
                #endif
                o.positionCS = TransformWorldToHClip(ApplyShadowBias(wp, wn, lightDir));
                #if UNITY_REVERSED_Z
                    o.positionCS.z = min(o.positionCS.z, UNITY_NEAR_CLIP_VALUE);
                #else
                    o.positionCS.z = max(o.positionCS.z, UNITY_NEAR_CLIP_VALUE);
                #endif
                return o;
            }
            half4 fragS (V IN) : SV_Target { return 0; }
            ENDHLSL
        }

        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode" = "DepthOnly" }
            ZWrite On ColorMask 0

            HLSLPROGRAM
            #pragma vertex vertD
            #pragma fragment fragD
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "PrototypeGridInput.hlsl"

            struct A { float4 positionOS : POSITION; };
            struct V { float4 positionCS : SV_POSITION; };

            V vertD (A IN)
            {
                V o;
                o.positionCS = ApplyVertexSnap(TransformObjectToHClip(IN.positionOS.xyz));
                return o;
            }
            half4 fragD (V IN) : SV_Target { return 0; }
            ENDHLSL
        }

        Pass
        {
            Name "DepthNormals"
            Tags { "LightMode" = "DepthNormals" }
            ZWrite On

            HLSLPROGRAM
            #pragma vertex vertN
            #pragma fragment fragN
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "PrototypeGridInput.hlsl"

            struct A { float4 positionOS : POSITION; float3 normalOS : NORMAL; };
            struct V { float4 positionCS : SV_POSITION; float3 normalWS : TEXCOORD0; };

            V vertN (A IN)
            {
                V o;
                o.positionCS = ApplyVertexSnap(TransformObjectToHClip(IN.positionOS.xyz));
                o.normalWS = TransformObjectToWorldNormal(IN.normalOS);
                return o;
            }
            half4 fragN (V IN) : SV_Target { return half4(normalize(IN.normalWS), 0); }
            ENDHLSL
        }
    }

    FallBack "Universal Render Pipeline/Lit"
}
