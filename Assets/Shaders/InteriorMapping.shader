Shader "Custom/Interior Mapping"
{
    // Rooms behind a facade, with no rooms modelled and no extra geometry at all. The
    // surface casts the view ray onward into a grid of boxes in object space, finds the
    // wall it lands on, and shades that. The parallax is real, so the interiors slide
    // past each other as you move, but the mesh is still just its outside.
    //
    // Wants flat faces. On a sphere the box grid has nothing square to sit behind, so
    // the gallery gives this one a cube: see the marker property at the bottom.
    Properties
    {
        _Rooms ("Rooms Per Side", Range(1, 100)) = 4
        _FrameWidth ("Window Frame", Range(0, 0.25)) = 0.07
        _FrameColor ("Frame Colour", Color) = (0.10, 0.10, 0.12, 1)

        _WallColor ("Wall Colour", Color) = (0.62, 0.57, 0.52, 1)
        _FloorColor ("Floor Colour", Color) = (0.34, 0.29, 0.26, 1)
        _CeilColor ("Ceiling Colour", Color) = (0.82, 0.80, 0.77, 1)

        [HDR] _LightColor ("Window Colour", Color) = (1.0, 0.70, 0.34, 1)
        _LitShare ("Lit Rooms", Range(0, 1)) = 0.45
        _ColorVariation ("Window Colour Spread", Range(0, 1)) = 0.25
        _LightVariation ("Window Brightness Spread", Range(0, 1)) = 0.5
        _RoomVariation ("Unlit Room Spread", Range(0, 1)) = 0.5

        _GlassTint ("Glass Tint", Color) = (0.55, 0.68, 0.78, 1)
        _Tinting ("Glass Tint Strength", Range(0, 1)) = 0.5
        _Reflection ("Glass Sheen", Range(0, 2)) = 0.6

        // marker: the gallery builds a cube instead of a sphere for anything with this
        [HideInInspector] _WantsCube ("Wants Cube", Float) = 1
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "Queue"="Geometry" "RenderPipeline"="UniversalPipeline" }

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

        CBUFFER_START(UnityPerMaterial)
            float _Rooms;
            float _FrameWidth;
            half4 _FrameColor;
            half4 _WallColor;
            half4 _FloorColor;
            half4 _CeilColor;
            half4 _LightColor;
            float _LitShare;
            float _ColorVariation;
            float _LightVariation;
            float _RoomVariation;
            half4 _GlassTint;
            float _Tinting;
            float _Reflection;
        CBUFFER_END
        ENDHLSL

        Pass
        {
            Name "Interior"
            Tags { "LightMode"="UniversalForward" }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 positionOS : TEXCOORD0;
                float3 normalOS   : TEXCOORD1;
                float3 normalWS   : TEXCOORD2;
                float3 viewWS     : TEXCOORD3;
            };

            Varyings vert (Attributes IN)
            {
                Varyings OUT;
                VertexPositionInputs p = GetVertexPositionInputs(IN.positionOS.xyz);
                OUT.positionCS = p.positionCS;
                OUT.positionOS = IN.positionOS.xyz;
                OUT.normalOS = IN.normalOS;
                OUT.normalWS = GetVertexNormalInputs(IN.normalOS).normalWS;
                OUT.viewWS = GetWorldSpaceNormalizeViewDir(p.positionWS);
                return OUT;
            }

            float Hash31 (float3 p)
            {
                p = frac(p * 0.1031);
                p += dot(p, p.yzx + 33.33);
                return frac((p.x + p.y) * p.z);
            }

            half4 frag (Varyings IN) : SV_Target
            {
                // work in 0..1 across the mesh, so the room grid divides it evenly
                float3 surface = IN.positionOS + 0.5;
                float cells = floor(_Rooms);
                float cell = 1.0 / cells;

                // Window frame first. It sits on the surface rather than inside, so it
                // occludes the room and gives the eye something solid to read depth from.
                float3 within = frac(surface * cells);
                float3 toEdge = min(within, 1.0 - within);

                // Only the two axes across the face count. Adding the normal lifts the
                // third one out of the min, since along it "distance to the edge" means
                // nothing: that axis runs straight into the room.
                float3 axis = abs(IN.normalOS);
                float edge = min(min(toEdge.x + axis.x, toEdge.y + axis.y), toEdge.z + axis.z);

                float3 camOS = TransformWorldToObject(_WorldSpaceCameraPos) + 0.5;
                float3 dir = normalize(surface - camOS);

                // nudge inside so the starting cell is the one behind the surface, not
                // the one in front, which the exact boundary could pick either way
                float3 start = surface + dir * (cell * 1e-3);
                float3 index = floor(start * cells);

                // exit point of that box: the nearest far plane along the ray
                float3 low = index * cell;
                float3 high = low + cell;
                float3 planes = (dir > 0.0 ? high : low) - start;
                float3 hits = planes / (abs(dir) < 1e-6 ? 1e-6 : dir);
                float travel = min(hits.x, min(hits.y, hits.z));
                float3 inside = start + dir * travel;

                // which of the three it was, and therefore what kind of surface
                bool horizontal = travel >= hits.y - 1e-6;
                bool ceiling = horizontal && dir.y > 0.0;

                half3 room = horizontal ? (ceiling ? _CeilColor.rgb : _FloorColor.rgb)
                                        : _WallColor.rgb;

                // every room gets its own shade, and its own answer to being lit
                float seed = Hash31(index + 0.5);
                room *= lerp(1.0, 0.55 + seed * 0.9, _RoomVariation);

                if (Hash31(index + 7.3) < _LitShare)
                {
                    // The hue wanders either side of the chosen colour. At zero every
                    // window is that colour exactly; at one the offset covers the whole
                    // wheel. Saturation travels with it, or a wide spread of hues at one
                    // fixed saturation still reads as a single washed tint.
                    float3 hsv = RgbToHsv(_LightColor.rgb);
                    hsv.x = frac(hsv.x + (Hash31(index + 3.1) - 0.5) * _ColorVariation);
                    hsv.y = saturate(hsv.y * lerp(1.0, 0.35 + Hash31(index + 5.9) * 1.5, _ColorVariation));
                    half3 bulb = HsvToRgb(hsv);

                    // and its own wattage, from all the same to some rooms twice the rest
                    float watts = lerp(1.0, 0.35 + Hash31(index + 11.7) * 1.5, _LightVariation);

                    // light pools on the floor and fades up the walls
                    float height = frac(inside.y * cells);
                    room += bulb * lerp(1.15, 0.25, height) * watts;
                }

                // depth: the further the ray travelled, the less light comes back out
                room *= saturate(1.0 - travel / (cell * 2.2) * 0.55);

                // tint rather than multiply, or the glass eats the rooms it is meant to show
                half3 col = room * lerp(half3(1, 1, 1), _GlassTint.rgb, _Tinting);

                // glass: a sheen that hides the interior at grazing angles
                float3 n = normalize(IN.normalWS);
                float facing = saturate(dot(n, normalize(IN.viewWS)));
                Light main = GetMainLight();
                col += _GlassTint.rgb * pow(1.0 - facing, 4.0) * _Reflection;
                col += main.color * pow(saturate(dot(n, normalize(main.direction + normalize(IN.viewWS)))), 90.0) * 0.6;

                // frame over the top of all of it
                float frame = 1.0 - smoothstep(_FrameWidth * 0.6, _FrameWidth, edge);
                col = lerp(col, _FrameColor.rgb * (0.4 + 0.6 * saturate(dot(n, main.direction))), frame);

                return half4(col, 1);
            }
            ENDHLSL
        }

        // Depth and shadows come from the outside of the mesh: the interior is an
        // illusion painted on the surface, it has no geometry to occlude anything.
        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode"="ShadowCaster" }
            ZWrite On
            ColorMask 0

            HLSLPROGRAM
            #pragma vertex ShadowVert
            #pragma fragment ShadowFrag
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

            float3 _LightDirection;
            float3 _LightPosition;

            float4 ShadowVert (float4 positionOS : POSITION, float3 normalOS : NORMAL) : SV_POSITION
            {
                float3 positionWS = TransformObjectToWorld(positionOS.xyz);
                float3 normalWS = TransformObjectToWorldNormal(normalOS);

                #if _CASTING_PUNCTUAL_LIGHT_SHADOW
                    float3 toLight = normalize(_LightPosition - positionWS);
                #else
                    float3 toLight = _LightDirection;
                #endif

                float4 positionCS = TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, toLight));
                #if UNITY_REVERSED_Z
                    positionCS.z = min(positionCS.z, UNITY_NEAR_CLIP_VALUE);
                #else
                    positionCS.z = max(positionCS.z, UNITY_NEAR_CLIP_VALUE);
                #endif
                return positionCS;
            }

            half4 ShadowFrag () : SV_Target { return 0; }
            ENDHLSL
        }

        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode"="DepthOnly" }
            ZWrite On
            ColorMask 0

            HLSLPROGRAM
            #pragma vertex DepthVert
            #pragma fragment DepthFrag

            float4 DepthVert (float4 positionOS : POSITION) : SV_POSITION
            {
                return TransformObjectToHClip(positionOS.xyz);
            }

            half4 DepthFrag () : SV_Target { return 0; }
            ENDHLSL
        }

        Pass
        {
            Name "DepthNormals"
            Tags { "LightMode"="DepthNormals" }
            ZWrite On

            HLSLPROGRAM
            #pragma vertex NormalsVert
            #pragma fragment NormalsFrag

            struct NormalsVaryings
            {
                float4 positionCS : SV_POSITION;
                float3 normalWS   : TEXCOORD0;
            };

            NormalsVaryings NormalsVert (float4 positionOS : POSITION, float3 normalOS : NORMAL)
            {
                NormalsVaryings OUT;
                OUT.positionCS = TransformObjectToHClip(positionOS.xyz);
                OUT.normalWS = TransformObjectToWorldNormal(normalOS);
                return OUT;
            }

            half4 NormalsFrag (NormalsVaryings IN) : SV_Target
            {
                return half4(normalize(IN.normalWS) * 0.5 + 0.5, 0);
            }
            ENDHLSL
        }
    }
}
