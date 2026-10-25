Shader "Purrfield/EnergyBlade"
{
    // The energy sword (EnergySword_Plan.md): a near-white core inside an additive element-coloured shell, revealed
    // in stages (grip → guard → blade) by _Reveal, edge texture per element (_Mode). Transparent, self-lit.
    Properties
    {
        [HDR] _Color ("Shell Color", Color) = (1, 0.5, 0.15, 1)
        _Core ("Core Color", Color) = (1, 0.97, 0.9, 1)
        _Glow ("Glow", Range(0, 8)) = 2.5
        _Reveal ("Reveal", Range(0, 1)) = 1
        _Mode ("Element Mode (0 water 1 electric 2 fire 3 air)", Range(0, 3)) = 2
        _Swell ("Swell", Range(1, 2)) = 1
        _Alpha ("Opacity", Range(0, 1)) = 1
    }
    SubShader
    {
        Tags { "RenderType" = "Transparent" "Queue" = "Transparent" "RenderPipeline" = "UniversalPipeline" }
        Pass
        {
            Name "EnergyBlade"
            Blend SrcAlpha One
            ZWrite Off
            ZTest LEqual
            Cull Off

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            CBUFFER_START(UnityPerMaterial)
                half4 _Color;
                half4 _Core;
                half _Glow;
                half _Reveal;
                half _Mode;
                half _Swell;
                half _Alpha;
            CBUFFER_END

            struct Attributes { float4 positionOS : POSITION; float3 normalOS : NORMAL; float2 uv : TEXCOORD0; float2 uv2 : TEXCOORD1; };
            struct Varyings { float4 positionCS : SV_POSITION; float3 positionWS : TEXCOORD0; half3 normalWS : TEXCOORD1; float2 uv : TEXCOORD2; float2 uv2 : TEXCOORD3; };

            Varyings vert (Attributes v)
            {
                Varyings o;
                float3 pos = v.positionOS.xyz;
                // the heavy's swell: the blade fattens (only across, not along)
                if (v.uv2.x > 1.5) pos.xz *= _Swell;
                o.positionWS = TransformObjectToWorld(pos);
                o.positionCS = TransformWorldToHClip(o.positionWS);
                o.normalWS = TransformObjectToWorldNormal(v.normalOS);
                o.uv = v.uv;
                o.uv2 = v.uv2;
                return o;
            }

            float hash21(float2 p) { p = frac(p * float2(123.34, 456.21)); p += dot(p, p + 45.32); return frac(p.x * p.y); }
            float noise(float2 p)
            {
                float2 i = floor(p), f = frac(p); f = f * f * (3 - 2 * f);
                return lerp(lerp(hash21(i), hash21(i + float2(1, 0)), f.x), lerp(hash21(i + float2(0, 1)), hash21(i + float2(1, 1)), f.x), f.y);
            }

            // how far this part is revealed (0..1) and where its front is, in part-local "along" units
            float PartReveal(float part)
            {
                if (part < 0.5) return saturate(_Reveal / 0.3);
                if (part < 1.5) return saturate((_Reveal - 0.2) / 0.3);
                return saturate((_Reveal - 0.4) / 0.6);
            }

            half4 frag (Varyings i) : SV_Target
            {
                float part = i.uv2.x;
                float r = PartReveal(part);
                // grip grows from its centre, guard opens from its centre sideways (|across|), blade from guard to tip (along)
                float coord = part < 0.5 ? abs(i.uv.y - 0.5) * 2 : part < 1.5 ? abs(i.uv.x) : i.uv.y;
                // fully revealed: keep the end caps (coord == 1: pommel, guard ends, tip) and drop the hot band at part ends
                bool full = r >= 0.999;
                if (full) coord = min(coord, 0.999);
                clip(r - coord - 1e-4);
                float front = full ? 0 : saturate(1 - (r - coord) * 8);       // 1 right at the reveal front

                float t = _Time.y;
                float along = i.uv2.y;
                float edge = abs(i.uv.x);                           // 0 centre line, 1 edge
                // element texture of the edge
                float tex;
                if (_Mode < 0.5)      tex = 0.5 + 0.5 * sin(along * 40 - t * 9 + noise(float2(along * 6, t)) * 3);       // water ripples running up
                else if (_Mode < 1.5) tex = step(0.82, noise(float2(along * 30, floor(t * 24)))) + 0.3 * noise(float2(along * 50, t * 30)); // electric skips
                else if (_Mode < 2.5) tex = noise(float2(edge * 3, along * 10 - t * 6)) * (0.6 + 0.4 * noise(float2(along * 22, t * 4)));    // fire licking up
                else                  tex = 0.5 + 0.5 * sin(along * 25 + edge * 6 - t * 7);                             // air streams twisting

                float3 V = normalize(GetWorldSpaceViewDir(i.positionWS));
                float fres = 1 - saturate(abs(dot(normalize(i.normalWS), V)));
                float core = saturate(1 - edge * 1.6);              // dense centre
                float shell = saturate(edge * 1.2 + fres) * (0.55 + 0.45 * tex);

                half3 col = _Core.rgb * core * 1.5 + _Color.rgb * shell * _Glow + _Color.rgb * front * _Glow * 1.5;
                half a = saturate(core + shell * 0.8 + front) * _Alpha;
                return half4(col, a);
            }
            ENDHLSL
        }
    }
}
