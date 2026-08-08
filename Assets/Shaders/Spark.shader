Shader "Custom/Spark"
{
    // Sparkler grains for a particle system. Each one is a round glow with a hot core
    // and its own blink, so a handful of them crackle instead of fading together.
    //
    // The blink needs a number that belongs to the particle and stays put for its whole
    // life. The renderer supplies one: turn on the StableRandom.x vertex stream and it
    // arrives in TEXCOORD0.z. Age comes in .w. SparkBurst sets both streams up.
    Properties
    {
        [HDR] _Color ("Colour", Color) = (1.0, 0.72, 0.30, 1)
        _Emission ("Emission", Range(0, 30)) = 6

        _Twinkle ("Twinkle", Range(0, 1)) = 0.7
        _TwinkleSpeed ("Twinkle Speed", Range(0, 80)) = 26

        _Softness ("Glow Softness", Range(0, 1)) = 0.45
        _CoreSize ("Core Size", Range(0, 1)) = 0.22
    }

    SubShader
    {
        Tags
        {
            "RenderType"="Transparent"
            "Queue"="Transparent"
            "RenderPipeline"="UniversalPipeline"
            "PreviewType"="Plane"
        }

        // premultiplied: the halo adds light with alpha at zero, the core writes alpha
        // and covers what is behind it. Straight additive would blow out over the shelf.
        Blend One OneMinusSrcAlpha
        ZWrite Off
        Cull Off

        Pass
        {
            Name "Spark"
            Tags { "LightMode"="UniversalForward" }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            CBUFFER_START(UnityPerMaterial)
                half4 _Color;
                float _Emission;
                float _Twinkle;
                float _TwinkleSpeed;
                float _Softness;
                float _CoreSize;
            CBUFFER_END

            struct Attributes
            {
                float4 positionOS : POSITION;
                half4 color       : COLOR;
                float4 uv         : TEXCOORD0; // xy quad, z stable random, w age
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                half4 color       : COLOR;
                float4 uv         : TEXCOORD0;
            };

            Varyings vert (Attributes IN)
            {
                Varyings OUT;
                OUT.positionCS = TransformObjectToHClip(IN.positionOS.xyz);
                OUT.color = IN.color;
                OUT.uv = IN.uv;
                return OUT;
            }

            half4 frag (Varyings IN) : SV_Target
            {
                // distance out from the middle of the quad, 0 centre to 1 at the edge
                float r = saturate(length(IN.uv.xy - 0.5) * 2.0);

                float glow = pow(saturate(1.0 - r), lerp(7.0, 1.3, _Softness));
                float core = smoothstep(_CoreSize, 0.0, r);

                // its own phase and its own rate, or every spark blinks in unison
                float seed = IN.uv.z;
                float blink = 0.5 + 0.5 * sin(_Time.y * _TwinkleSpeed * (0.5 + seed) + seed * 43.0);
                float lit = lerp(1.0, blink, _Twinkle);

                float fade = IN.color.a * lit;
                half3 tint = _Color.rgb * IN.color.rgb * _Emission;

                half3 rgb = tint * (glow + core) * fade;
                return half4(rgb, saturate(core * fade));
            }
            ENDHLSL
        }
    }
}
