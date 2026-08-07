// Analytic exponential height fog with drifting density pockets (GDD: "fog
// pockets" in the mid zone). Runs as a fullscreen pass before post-processing
// so bloom/grade/dither treat fog as part of the scene. Fog color follows
// RenderSettings.fogColor, i.e. the DayNightController's time-of-day gradient.
Shader "Purrfield/Height Fog"
{
    Properties
    {
        _Density ("Density", Range(0, 0.5)) = 0.07
        _HeightFalloff ("Height Falloff", Range(0.05, 3)) = 0.6
        _BaseHeight ("Base Height (world Y)", Float) = -1
        _SkyDistance ("Sky Ray Distance", Float) = 250
        _Tint ("Tint", Color) = (1, 1, 1, 1)
        _NoiseScale ("Pocket Noise Scale", Range(0.001, 0.3)) = 0.05
        _NoiseAmount ("Pocket Noise Amount", Range(0, 1)) = 0.55
        _NoiseSpeed ("Pocket Drift Speed", Range(0, 1)) = 0.05
        _DensityMultiplier ("Density Multiplier (script)", Range(0, 1)) = 1
    }

    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" }
        ZWrite Off
        Cull Off
        ZTest Always

        Pass
        {
            Name "HeightFog"

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            float _Density;
            float _HeightFalloff;
            float _BaseHeight;
            float _SkyDistance;
            half4 _Tint;
            float _NoiseScale;
            float _NoiseAmount;
            float _NoiseSpeed;
            float _DensityMultiplier;

            float Hash21(float2 p)
            {
                p = frac(p * float2(123.34, 456.21));
                p += dot(p, p + 45.32);
                return frac(p.x * p.y);
            }

            float ValueNoise(float2 p)
            {
                float2 i = floor(p);
                float2 f = frac(p);
                float2 u = f * f * (3.0 - 2.0 * f);
                float a = Hash21(i);
                float b = Hash21(i + float2(1, 0));
                float c = Hash21(i + float2(0, 1));
                float d = Hash21(i + float2(1, 1));
                return lerp(lerp(a, b, u.x), lerp(c, d, u.x), u.y);
            }

            half4 frag(Varyings input) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
                float2 uv = input.texcoord;

                half3 col = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_PointClamp, uv).rgb;

                float rawDepth = SampleSceneDepth(uv);
                float3 posWS = ComputeWorldSpacePosition(uv, rawDepth, UNITY_MATRIX_I_VP);

                float3 ro = _WorldSpaceCameraPos.xyz;
                float3 ray = posWS - ro;
                float t = length(ray);
                float3 rd = ray / max(t, 1e-4);

                #if UNITY_REVERSED_Z
                    bool isSky = rawDepth < 1e-5;
                #else
                    bool isSky = rawDepth > 1.0 - 1e-5;
                #endif
                if (isSky) t = _SkyDistance;

                // drifting fog pockets, anchored to world space at the ray end
                float3 pe = ro + rd * t;
                float2 np = pe.xz * _NoiseScale + _Time.y * _NoiseSpeed;
                float n = ValueNoise(np) * 0.65 + ValueNoise(np * 2.7 + 13.1) * 0.35;
                float density = _Density * _DensityMultiplier
                              * lerp(1.0 - _NoiseAmount, 1.0 + _NoiseAmount, n);

                // analytic integral of exp height falloff along the view ray
                float b = max(_HeightFalloff, 1e-3);
                float relY = ro.y - _BaseHeight;
                float rdy = rd.y;
                float integral;
                if (abs(rdy) < 1e-4)
                    integral = density * t * exp(-relY * b);
                else
                    integral = (density / b) * exp(-relY * b) * (1.0 - exp(-t * rdy * b)) / rdy;

                float fog = 1.0 - exp(-max(integral, 0.0));

                half3 fogCol = unity_FogColor.rgb * _Tint.rgb;
                col = lerp(col, fogCol, saturate(fog));
                return half4(col, 1);
            }
            ENDHLSL
        }
    }
}
