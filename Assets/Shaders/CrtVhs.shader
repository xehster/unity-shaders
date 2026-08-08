Shader "Custom/CRT VHS"
{
    // A tube and a worn tape, in that order: the picture is bent around the glass, the
    // tape drags it sideways, then the phosphor grid puts it back together.
    //
    // Full-screen pass. Drop it on a FullScreenPassRendererFeature; it covers everything
    // the camera drew, which is the point, and also why it ships switched off.
    Properties
    {
        _Curvature ("Curvature", Range(0, 1)) = 0.25
        _Vignette ("Vignette", Range(0, 1)) = 0.3

        _ScanlineCount ("Scanlines", Range(100, 1200)) = 480
        _ScanlineDepth ("Scanline Depth", Range(0, 1)) = 0.35
        _MaskStrength ("Aperture Mask", Range(0, 1)) = 0.3

        _Bleed ("Colour Bleed", Range(0, 6)) = 1.5
        _Jitter ("Tape Jitter", Range(0, 1)) = 0.35
        _Tearing ("Tearing", Range(0, 1)) = 0.3
        _Noise ("Noise", Range(0, 1)) = 0.15

        _Tracking ("Tracking Bar", Range(0, 1)) = 0.3
        _TrackingSpeed ("Tracking Speed", Range(0, 2)) = 0.25

        _Boost ("Brightness", Range(0.5, 2)) = 1.45
    }

    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" }
        ZWrite Off
        Cull Off
        ZTest Always

        Pass
        {
            Name "CrtVhs"

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            float _Curvature;
            float _Vignette;
            float _ScanlineCount;
            float _ScanlineDepth;
            float _MaskStrength;
            float _Bleed;
            float _Jitter;
            float _Tearing;
            float _Noise;
            float _Tracking;
            float _TrackingSpeed;
            float _Boost;

            float Hash21 (float2 p)
            {
                p = frac(p * float2(123.34, 456.21));
                p += dot(p, p + 45.32);
                return frac(p.x * p.y);
            }

            // Push the picture out towards the corners the way a tube does. More at the
            // edges than the middle, which is what makes the glass read as curved rather
            // than as a scaled image.
            float2 Bulge (float2 uv, float amount)
            {
                uv = uv * 2.0 - 1.0;
                float2 pull = abs(uv.yx) / float2(6.0, 5.0);
                uv += uv * pull * pull * amount * 4.0;
                return uv * 0.5 + 0.5;
            }

            half3 Tap (float2 uv)
            {
                return SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv).rgb;
            }

            half4 frag (Varyings input) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);

                float2 uv = Bulge(input.texcoord, _Curvature);

                // the bulge pushes the corners past the edge of the picture, and past the
                // edge of a tube there is only unlit glass
                if (any(uv < 0.0) || any(uv > 1.0)) return half4(0, 0, 0, 1);

                // A tracking fault is a band of tape the head is reading badly. It rolls
                // up the picture, drags that strip sideways and washes it out.
                float bar = exp(-pow((frac(uv.y + _Time.y * _TrackingSpeed) - 0.5) * 22.0, 2.0)) * _Tracking;

                // per-line wobble plus the whole picture breathing left and right
                float scanRow = floor(uv.y * _ScanlineCount);
                float wobble = (Hash21(float2(scanRow, floor(_Time.y * 24.0))) - 0.5) * 0.004;
                wobble += sin(_Time.y * 1.3) * 0.0012;

                // tearing picks a few bands at a time rather than smearing everything
                float band = floor(uv.y * 40.0 - _Time.y * 6.0);
                float pick = Hash21(float2(band, floor(_Time.y * 10.0)));
                float tear = pick > 0.93 ? (Hash21(float2(band, 7.7)) - 0.5) * 0.06 : 0.0;

                uv.x += wobble * _Jitter + tear * _Tearing + bar * 0.02;

                // colour bleed: the chroma signal lags the luma, so the channels smear apart
                float spread = _Bleed / max(_ScreenParams.x, 1.0);
                half3 col = half3(Tap(uv + float2(spread, 0)).r,
                                  Tap(uv).g,
                                  Tap(uv - float2(spread, 0)).b);

                col = lerp(col, col + 0.18, bar);

                // phosphor: rows dimmed between the beams, columns split into a triad
                float scan = sin(uv.y * _ScanlineCount * PI) * 0.5 + 0.5;
                col *= lerp(1.0, scan, _ScanlineDepth);

                int triad = (int)fmod(input.positionCS.x, 3.0);
                half3 mask = triad == 0 ? half3(1.0, 0.6, 0.6)
                           : triad == 1 ? half3(0.6, 1.0, 0.6)
                                        : half3(0.6, 0.6, 1.0);
                col *= lerp(half3(1, 1, 1), mask, _MaskStrength);

                col += (Hash21(input.positionCS.xy + _Time.y * 60.0) - 0.5) * _Noise * 0.35;

                float2 edge = uv * (1.0 - uv);
                col *= pow(saturate(edge.x * edge.y * 16.0), _Vignette * 1.5);

                return half4(saturate(col * _Boost), 1);
            }
            ENDHLSL
        }
    }
}
