Shader "DIVA/gmap (mesh)"
{
    // Same recolour as DIVA/gmap, but for geometry instead of UGUI.
    // The UI version is Cull Off / ZWrite Off / transparent queue, which is right for a
    // flat Image and wrong for a sphere - back faces draw over front ones. This one is
    // opaque, single sided and writes depth, so it can sit in a 3D scene.
    Properties
    {
        [MainTexture] _MainTex ("Texture", 2D) = "white" {}
        _Color ("Tint", Color) = (1,1,1,1)
        _ShadowColor ("Shadow Colour", Color) = (0.40,0.24,0.18,1)
        _LightColor  ("Light Colour",  Color) = (1.0,0.86,0.74,1)
        _Lo ("Luminance Lo", Range(0,1)) = 0.25
        _Hi ("Luminance Hi", Range(0,1)) = 1.0
        _Strength ("Strength", Range(0,1)) = 1

        // Black-outline preservation: dark + desaturated base pixels stay original.
        _KeepInk ("Keep Outline", Range(0,1)) = 1
        _InkVal  ("Ink Value Threshold", Range(0,1)) = 0.01
        _InkSoft ("Ink Value Softness", Range(0,0.3)) = 0.10
        _InkSat  ("Ink Max Saturation", Range(0,1)) = 0.35
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        Pass
        {
            Name "Unlit"
            Tags { "LightMode"="UniversalForward" }

            Cull Back
            ZWrite On

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_fog

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            TEXTURE2D(_MainTex); SAMPLER(sampler_MainTex);

            CBUFFER_START(UnityPerMaterial)
                float4 _MainTex_ST;
                half4 _Color;
                half4 _ShadowColor;
                half4 _LightColor;
                float _Lo;
                float _Hi;
                float _Strength;
                float _KeepInk;
                float _InkVal;
                float _InkSoft;
                float _InkSat;
            CBUFFER_END

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv         : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv         : TEXCOORD0;
                float  fogFactor  : TEXCOORD1;
            };

            Varyings vert (Attributes IN)
            {
                Varyings OUT;
                VertexPositionInputs p = GetVertexPositionInputs(IN.positionOS.xyz);
                OUT.positionCS = p.positionCS;
                OUT.uv = TRANSFORM_TEX(IN.uv, _MainTex);
                OUT.fogFactor = ComputeFogFactor(p.positionCS.z);
                return OUT;
            }

            half4 frag (Varyings IN) : SV_Target
            {
                half4 tex = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv);

                // luminance of the source pixel, remapped into the ramp range
                float lum = dot(tex.rgb, float3(0.299, 0.587, 0.114));
                float t = saturate((lum - _Lo) / max(0.0001, (_Hi - _Lo)));
                float3 ramp = lerp(_ShadowColor.rgb, _LightColor.rgb, t);

                float3 rgb = lerp(tex.rgb, ramp, _Strength);

                // keep the black ink: dark and desaturated pixels stay as they were,
                // soft thresholds so antialiased edges don't tear
                float val = max(tex.r, max(tex.g, tex.b));
                float mn  = min(tex.r, min(tex.g, tex.b));
                float sat = val > 1e-4 ? (val - mn) / val : 0.0;
                float darkMask = 1.0 - smoothstep(_InkVal, _InkVal + _InkSoft, val);
                float satMask  = 1.0 - smoothstep(_InkSat, _InkSat + 0.15, sat);
                rgb = lerp(rgb, tex.rgb, darkMask * satMask * _KeepInk);

                half4 color = half4(rgb * _Color.rgb, 1.0);
                color.rgb = MixFog(color.rgb, IN.fogFactor);
                return color;
            }
            ENDHLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode"="ShadowCaster" }
            ZWrite On ColorMask 0
            HLSLPROGRAM
            #pragma vertex vertS
            #pragma fragment fragS
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

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

        // depth passes so the sphere plays along with SSAO and the full-screen effects
        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode"="DepthOnly" }
            ZWrite On ColorMask 0
            HLSLPROGRAM
            #pragma vertex vertD
            #pragma fragment fragD
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            struct A { float4 positionOS : POSITION; };
            struct V { float4 positionCS : SV_POSITION; };
            V vertD (A IN) { V o; o.positionCS = TransformObjectToHClip(IN.positionOS.xyz); return o; }
            half4 fragD (V IN) : SV_Target { return 0; }
            ENDHLSL
        }

        Pass
        {
            Name "DepthNormals"
            Tags { "LightMode"="DepthNormals" }
            ZWrite On
            HLSLPROGRAM
            #pragma vertex vertN
            #pragma fragment fragN
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            struct A { float4 positionOS : POSITION; float3 normalOS : NORMAL; };
            struct V { float4 positionCS : SV_POSITION; float3 normalWS : TEXCOORD0; };
            V vertN (A IN)
            {
                V o;
                o.positionCS = TransformObjectToHClip(IN.positionOS.xyz);
                o.normalWS = TransformObjectToWorldNormal(IN.normalOS);
                return o;
            }
            half4 fragN (V IN) : SV_Target { return half4(normalize(IN.normalWS) * 0.5 + 0.5, 0); }
            ENDHLSL
        }
    }
}
