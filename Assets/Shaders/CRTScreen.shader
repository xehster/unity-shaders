// Glowing CRT screen for the cable-chamber studio: emissive picture + scanlines, a gentle brightness
// wobble and, now and then, a glitch — each screen on its own clock (seeded from its position).
// The picture can be a flipbook atlas (_Flipbook) for an animated screen.
// Globals from StudioController (see StudioFx.hlsl); with them at 0 the screen just glows steadily.
Shader "Purrfield/CRT Screen"
{
    Properties
    {
        _BaseMap ("Picture", 2D) = "white" {}
        _AltMap ("Picture to jump to (glitch)", 2D) = "black" {}
        [HDR] _EmissionColor ("Glow", Color) = (3.2, 3.2, 3.2, 1)
        _Scanlines ("Scanline Strength", Range(0, 1)) = 0.18
        _ScanlineCount ("Scanlines", Float) = 240
        _Vignette ("Edge Darkening", Range(0, 1)) = 0.35
        _Flipbook ("Flipbook: columns, rows, frames, fps (frames <= 1 = still picture)", Vector) = (1, 1, 1, 0)
        _FlipbookPad ("Flipbook cell padding (fraction of a cell, x / y)", Vector) = (0, 0, 0, 0)
        _PictureCrop ("Picture crop: part of the frame stretched over the screen (u0, v0, u1, v1)", Vector) = (0, 0, 1, 1)
        [HideInInspector] _ScreenSeed ("Seed (set per screen by StudioScreen; <0 = from position)", Float) = -1
    }

    SubShader
    {
        Tags { "RenderType" = "Opaque" "Queue" = "Geometry" "RenderPipeline" = "UniversalPipeline" }

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "StudioFx.hlsl"

        TEXTURE2D(_BaseMap); SAMPLER(sampler_BaseMap);
        TEXTURE2D(_AltMap); SAMPLER(sampler_AltMap);

        CBUFFER_START(UnityPerMaterial)
            float4 _BaseMap_ST;
            float4 _AltMap_ST;
            half4 _EmissionColor;
            half _Scanlines;
            float _ScanlineCount;
            half _Vignette;
            float4 _Flipbook;
            float4 _FlipbookPad;
            float4 _PictureCrop;
            float _ScreenSeed;
        CBUFFER_END

        // animated picture: an atlas of frames (row 0 at the top), played at _Flipbook.w fps; each screen starts
        // at its own frame. Glitch offsets wrap inside the frame, never into the neighbouring cell.
        float2 FlipUV(float2 u, float t, float seed)
        {
            if (_Flipbook.z <= 1.0) return lerp(_PictureCrop.xy, _PictureCrop.zw, u);
            float frame = fmod(floor(t * _Flipbook.w + seed * _Flipbook.z), _Flipbook.z);
            float col = fmod(frame, _Flipbook.x), row = floor(frame / _Flipbook.x);
            float2 inner = lerp(_FlipbookPad.xy, 1.0 - _FlipbookPad.xy, lerp(_PictureCrop.xy, _PictureCrop.zw, frac(u)));
            return float2((col + inner.x) / _Flipbook.x, 1.0 - (row + 1.0 - inner.y) / _Flipbook.y);
        }

        half3 ScreenColor(float2 uv, float seed, float t)
        {
            float4 st = StudioScreenState(t, seed);
            float type = st.y; float k = st.w; float prog = st.z;
            float2 u = uv;
            if (type == 0) // bands tear sideways
            {
                float band = floor(u.y * 14.0 + floor(t * 30.0));
                u.x += (StudioHash11(band + seed * 50.0) - 0.5) * 0.18 * k * step(0.55, StudioHash11(band * 1.7));
            }
            if (type == 2) u.y = frac(u.y + prog * 0.6 * k); // picture rolls
            half3 c;
            if (type == 1) // channels drift apart
            {
                float o = 0.012 * k;
                c.r = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, FlipUV(u + float2(o, 0), t, seed)).r;
                c.g = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, FlipUV(u, t, seed)).g;
                c.b = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, FlipUV(u - float2(o, 0), t, seed)).b;
            }
            else if (type == 5 && k > 0.5)
                c = SAMPLE_TEXTURE2D(_AltMap, sampler_AltMap, u).rgb;
            else
                c = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, FlipUV(u, t, seed)).rgb;
            if (type == 3) // snow
            {
                float n = StudioHash11(dot(floor(uv * float2(160, 120)), float2(1.0, 157.0)) + floor(t * 40.0) * 3.1);
                c = lerp(c, n.xxx, 0.75 * k);
            }
            // scanlines + a slow bright bar rolling down + dark edges
            float scan = 1.0 - _Scanlines * (0.5 + 0.5 * sin(uv.y * _ScanlineCount * 6.2831));
            float bar = 1.0 + 0.08 * smoothstep(0.08, 0.0, abs(frac(uv.y - t * 0.11 - seed) - 0.5) - 0.42);
            float2 e = uv * (1.0 - uv) * 4.0;
            float vig = lerp(1.0, saturate(pow(max(e.x * e.y, 0.0), 0.35)), _Vignette);
            return c * _EmissionColor.rgb * (scan * bar * vig * st.x);
        }
        ENDHLSL

        Pass
        {
            Name "Unlit"
            Tags { "LightMode" = "UniversalForward" }
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_fog
            struct Attributes { float4 positionOS : POSITION; float2 uv : TEXCOORD0; };
            struct Varyings { float4 positionCS : SV_POSITION; float2 uv : TEXCOORD0; half fog : TEXCOORD1; nointerpolation float seed : TEXCOORD2; };
            Varyings vert(Attributes v)
            {
                Varyings o;
                o.positionCS = TransformObjectToHClip(v.positionOS.xyz);
                o.uv = TRANSFORM_TEX(v.uv, _BaseMap);
                o.fog = ComputeFogFactor(o.positionCS.z);
                o.seed = _ScreenSeed >= 0 ? _ScreenSeed : StudioObjectSeed();
                return o;
            }
            half4 frag(Varyings i) : SV_Target
            {
                half3 c = ScreenColor(i.uv, i.seed, _Time.y);
                return half4(MixFog(c, i.fog), 1);
            }
            ENDHLSL
        }

        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode" = "DepthOnly" }
            ZWrite On ColorMask R
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            float4 vert(float4 p : POSITION) : SV_POSITION { return TransformObjectToHClip(p.xyz); }
            half4 frag() : SV_Target { return 0; }
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
            struct A { float4 p : POSITION; float3 n : NORMAL; };
            struct V { float4 p : SV_POSITION; half3 n : TEXCOORD0; };
            V vert(A a) { V o; o.p = TransformObjectToHClip(a.p.xyz); o.n = TransformObjectToWorldNormal(a.n); return o; }
            half4 frag(V i) : SV_Target { return half4(normalize(i.n), 0); }
            ENDHLSL
        }

        // baker: the screens light the room in the probe bake
        Pass
        {
            Name "Meta"
            Tags { "LightMode" = "Meta" }
            Cull Off
            HLSLPROGRAM
            #pragma vertex PurrMetaVertex
            #pragma fragment fragMeta
            #define PURR_META_ST _BaseMap_ST
            #include "PurrMetaPass.hlsl"
            half4 fragMeta(PurrMetaVaryings i) : SV_Target
            {
                half3 c = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, FlipUV(i.uv, 0, 0)).rgb * _EmissionColor.rgb;
                return PurrMetaOut(0.02, c);
            }
            ENDHLSL
        }
    }
}
