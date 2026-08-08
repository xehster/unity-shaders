// PS1 Lit + per-object chromatic aberration: two extra fringe passes rewrite
// the R and B channels slightly shifted radially from the screen center (like
// a real lens - zero at center, growing to the edges). Keep _ChromaShift under
// ~1px for the reference "barely there" look. Costs ~3x the object's raster
// work, so use on hero objects, not on everything.
Shader "Purrfield/PS1 Lit Chromatic"
{
    Properties
    {
        _BaseMap ("Base Map", 2D) = "white" {}
        _BaseColor ("Base Color", Color) = (1, 1, 1, 1)
        _EmissionMap ("Emission Map", 2D) = "white" {}
        [HDR] _EmissionColor ("Emission Color", Color) = (0, 0, 0, 1)
        _VertexSnapPixels ("Vertex Grid Height (0 = off)", Float) = 240
        _AffineAmount ("Affine Texture Warp", Range(0, 1)) = 1
        _ChromaShift ("Chromatic Shift (px at screen edge)", Range(0, 4)) = 0.8
    }

    SubShader
    {
        Tags
        {
            "RenderType" = "Opaque"
            "Queue" = "Geometry"
            "RenderPipeline" = "UniversalPipeline"
        }

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

        CBUFFER_START(UnityPerMaterial)
            float4 _BaseMap_ST;
            half4 _BaseColor;
            half4 _EmissionColor;
            float _VertexSnapPixels;
            half _AffineAmount;
            float _ChromaShift;
        CBUFFER_END

        float4 ApplyVertexSnap(float4 positionCS)
        {
            if (_VertexSnapPixels < 1.0)
                return positionCS;
            float aspect = _ScreenParams.x / max(_ScreenParams.y, 1.0);
            float2 grid = float2(_VertexSnapPixels * aspect, _VertexSnapPixels);
            float2 ndc = positionCS.xy / positionCS.w;
            ndc = floor(ndc * grid * 0.5) / (grid * 0.5) + 1.0 / grid;
            positionCS.xy = ndc * positionCS.w;
            return positionCS;
        }

        // radial screen-space shift, sign = +1 pushes outward, -1 inward
        float4 ApplyChromaShift(float4 positionCS, float sign)
        {
            float2 ndc = positionCS.xy / positionCS.w;
            float2 shift = ndc * (_ChromaShift * 2.0 / max(_ScreenParams.y, 1.0)) * sign;
            positionCS.xy += shift * positionCS.w;
            return positionCS;
        }
        ENDHLSL

        // ---------- shared lit program (used by main + fringe passes) ----------
        // main pass writes RGB + depth; fringe passes re-render shifted with
        // ColorMask R / B so only that channel is displaced.

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode" = "UniversalForward" }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #define CHROMA_SIGN 0
            #include_with_pragmas "PS1LitChromaticPass.hlsl"
            ENDHLSL
        }

        Pass
        {
            Name "FringeR"
            Tags { "LightMode" = "PurrChromaR" }
            ZWrite Off
            ZTest LEqual
            Offset -1, -2
            ColorMask R

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #define CHROMA_SIGN 1
            #include_with_pragmas "PS1LitChromaticPass.hlsl"
            ENDHLSL
        }

        Pass
        {
            Name "FringeB"
            Tags { "LightMode" = "PurrChromaB" }
            ZWrite Off
            ZTest LEqual
            Offset -1, -2
            ColorMask B

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #define CHROMA_SIGN -1
            #include_with_pragmas "PS1LitChromaticPass.hlsl"
            ENDHLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode" = "ShadowCaster" }

            ZWrite On
            ZTest LEqual
            ColorMask 0

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW

            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/CommonMaterial.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

            float3 _LightDirection;
            float3 _LightPosition;

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
            };

            Varyings vert(Attributes v)
            {
                Varyings o;
                float3 positionWS = TransformObjectToWorld(v.positionOS.xyz);
                float3 normalWS = TransformObjectToWorldNormal(v.normalOS);

                #if _CASTING_PUNCTUAL_LIGHT_SHADOW
                    float3 lightDirectionWS = normalize(_LightPosition - positionWS);
                #else
                    float3 lightDirectionWS = _LightDirection;
                #endif

                o.positionCS = TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, lightDirectionWS));
                #if UNITY_REVERSED_Z
                    o.positionCS.z = min(o.positionCS.z, UNITY_NEAR_CLIP_VALUE);
                #else
                    o.positionCS.z = max(o.positionCS.z, UNITY_NEAR_CLIP_VALUE);
                #endif
                return o;
            }

            half4 frag(Varyings i) : SV_Target
            {
                return 0;
            }
            ENDHLSL
        }

        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode" = "DepthOnly" }

            ZWrite On
            ColorMask R

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            struct Attributes
            {
                float4 positionOS : POSITION;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
            };

            Varyings vert(Attributes v)
            {
                Varyings o;
                o.positionCS = ApplyVertexSnap(TransformObjectToHClip(v.positionOS.xyz));
                return o;
            }

            half4 frag(Varyings i) : SV_Target
            {
                return 0;
            }
            ENDHLSL
        }

        Pass
        {
            Name "DepthNormals"
            Tags { "LightMode" = "DepthNormals" }

            ZWrite On

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                half3 normalWS : TEXCOORD0;
            };

            Varyings vert(Attributes v)
            {
                Varyings o;
                o.positionCS = ApplyVertexSnap(TransformObjectToHClip(v.positionOS.xyz));
                o.normalWS = TransformObjectToWorldNormal(v.normalOS);
                return o;
            }

            half4 frag(Varyings i) : SV_Target
            {
                return half4(normalize(i.normalWS), 0);
            }
            ENDHLSL
        }
    }

    FallBack "Purrfield/PS1 Lit"
}
