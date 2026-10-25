Shader "Purrfield/Electric Arc"
{
    // A lightning bolt drawn on a LineRenderer (ZapFx rebuilds the jagged path every few frames).
    // Across the strip (uv.y) a white-hot core sits inside a coloured glow; along it (uv.x) a
    // fast noise makes the current crawl and flicker, and both ends taper so the bolt reads as
    // jumping between two points rather than as a painted stripe. Additive, HDR — it blooms.
    Properties
    {
        [HDR] _Color ("Glow", Color) = (0.35, 0.65, 4.0, 1)
        [HDR] _CoreColor ("Core", Color) = (3, 3.4, 4, 1)
        _CoreWidth ("Core Width", Range(0.01, 0.5)) = 0.12
        _GlowFalloff ("Glow Falloff", Range(0.5, 8)) = 2.5
        _Flicker ("Flicker", Range(0, 1)) = 0.6
        _CrawlSpeed ("Crawl Speed", Range(0, 60)) = 24
        _Intensity ("Intensity", Range(0, 4)) = 1
    }

    SubShader
    {
        Tags { "RenderType"="Transparent" "Queue"="Transparent+10" "RenderPipeline"="UniversalPipeline" "IgnoreProjector"="True" }

        Pass
        {
            Name "Arc"
            Blend One One
            ZWrite Off
            Cull Off

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            CBUFFER_START(UnityPerMaterial)
                half4 _Color;
                half4 _CoreColor;
                half _CoreWidth;
                half _GlowFalloff;
                half _Flicker;
                half _CrawlSpeed;
                half _Intensity;
            CBUFFER_END

            struct Attributes { float4 positionOS : POSITION; float2 uv : TEXCOORD0; half4 color : COLOR; };
            struct Varyings { float4 positionCS : SV_POSITION; float2 uv : TEXCOORD0; half4 color : COLOR; };

            Varyings vert (Attributes IN)
            {
                Varyings OUT;
                OUT.positionCS = TransformObjectToHClip(IN.positionOS.xyz);
                OUT.uv = IN.uv;
                OUT.color = IN.color;
                return OUT;
            }

            float Hash (float n) { return frac(sin(n) * 43758.5453); }
            float Noise1 (float x) { float i = floor(x); float f = frac(x); return lerp(Hash(i), Hash(i + 1), f * f * (3 - 2 * f)); }

            half4 frag (Varyings IN) : SV_Target
            {
                float across = abs(IN.uv.y * 2 - 1);                           // 0 in the middle, 1 at the edge
                float core = saturate(1 - across / _CoreWidth);
                float glow = pow(saturate(1 - across), _GlowFalloff);

                float t = _Time.y * _CrawlSpeed;
                float crawl = Noise1(IN.uv.x * 18 - t) * Noise1(IN.uv.x * 7 + t * 0.7);
                float flick = lerp(1, 0.35 + 1.3 * crawl, _Flicker);

                float ends = saturate(IN.uv.x * 8) * saturate((1 - IN.uv.x) * 8);  // taper both ends

                half3 col = (_CoreColor.rgb * core + _Color.rgb * glow) * flick * ends * _Intensity * IN.color.a;
                return half4(col, 1);
            }
            ENDHLSL
        }
    }
}
