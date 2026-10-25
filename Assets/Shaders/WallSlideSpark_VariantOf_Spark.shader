Shader "Purrfield/Wall Slide Spark (Variant of Spark)"
{
    Properties
    {
        _MainTex ("Texture (unused, kept for Shuriken UI)", 2D) = "white" {}

        // Two colours only, and every spark gets both: a light yellow body with a warmer
        // yellow-orange edge. No per-spark colour variety — mixed temperatures read as dirt.
        [Header(Colour)]
        _CoreColour ("Body (light yellow)", Color) = (1.0, 0.94, 0.62, 1)
        _RimColour  ("Edge (warm yellow-orange)", Color) = (1.0, 0.66, 0.20, 1)
        _Brightness ("Brightness", Range(0.5, 40)) = 11.0
        _RimStrength ("Edge strength", Range(0, 3)) = 1.1

        [Header(Streak shape)]
        _Sharpness ("Needle sharpness", Range(1, 16)) = 5.0
        _CapSoftness ("End softness", Range(0.01, 0.5)) = 0.18

        [Header(Life)]
        _FlickerRate  ("Flicker rate", Range(0, 120)) = 45
        _FlickerDepth ("Flicker depth", Range(0, 0.6)) = 0.18

        // 1 on the ember material: a four-pointed sparkle instead of a streak. Embers are a
        // separate billboard system — a stretched quad cannot hold a shape, and a nearly
        // stationary stretched particle snaps to the screen axes (the stray vertical bars).
        [Header(Mode)]
        [Toggle] _EmberMode ("Ember (four-point sparkle)", Float) = 0
        _StarPoint ("Star point sharpness", Range(0.2, 0.9)) = 0.5
        _StarGlow ("Star glow", Range(0, 2)) = 0.7
    }

    SubShader
    {
        Tags { "RenderType"="Transparent" "Queue"="Transparent+20" "RenderPipeline"="UniversalPipeline" "IgnoreProjector"="True" }
        Blend SrcAlpha One
        ZWrite Off
        Cull Off

        Pass
        {
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            // Vertex streams, set on both renderers in WallRun.cs:
            //   TEXCOORD1.xy = size XY   .z = speed   .w = age (0..1)
            //   TEXCOORD2.x  = stable random per particle
            struct Attributes
            {
                float4 positionOS : POSITION;
                float4 color      : COLOR;
                float2 uv         : TEXCOORD0;
                float4 sizeSpeed  : TEXCOORD1;
                float  random     : TEXCOORD2;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float4 color      : TEXCOORD0;
                float2 uv         : TEXCOORD1;
                float4 sizeSpeed  : TEXCOORD2;
                float  random     : TEXCOORD3;
            };

            CBUFFER_START(UnityPerMaterial)
                float4 _CoreColour, _RimColour;
                float _Brightness, _RimStrength;
                float _Sharpness, _CapSoftness;
                float _FlickerRate, _FlickerDepth;
                float _EmberMode, _StarPoint, _StarGlow;
            CBUFFER_END

            Varyings vert(Attributes input)
            {
                Varyings output;
                output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
                output.color = input.color;
                output.uv = input.uv;
                output.sizeSpeed = input.sizeSpeed;
                output.random = input.random;
                return output;
            }

            half4 frag(Varyings input) : SV_Target
            {
                float age = saturate(input.sizeSpeed.w);
                float rnd = input.random;

                // Gentle crackle with a per-spark phase, so the shower is alive without any spark
                // changing colour.
                float flick = 0.5 + 0.5 * sin(age * _FlickerRate + rnd * 43.0);
                float life = lerp(1.0 - _FlickerDepth, 1.0 + _FlickerDepth, flick);

                float body;   // light-yellow core of the shape
                float edge;   // warmer rim around it

                if (_EmberMode > 0.5)
                {
                    // Four-pointed sparkle: with an exponent below 1 the unit shape of
                    // |x|^p + |y|^p is concave, which is exactly a four-point star — long on the
                    // axes, pinched on the diagonals.
                    float2 d = input.uv * 2.0 - 1.0;
                    float s = pow(abs(d.x), _StarPoint) + pow(abs(d.y), _StarPoint);
                    body = smoothstep(1.05, 0.55, s);
                    edge = smoothstep(1.25, 0.6, s) - body * 0.5;
                    // A soft halo so it blooms rather than sitting on the frame as a decal.
                    edge += exp(-max(s - 0.6, 0.0) * 3.0) * _StarGlow * 0.35;
                }
                else
                {
                    // A motion-blurred dash is even along its length with soft ends. Drawn
                    // symmetrically on purpose: the stretched quad's U axis flips with the
                    // direction of travel relative to the camera, so anything asymmetric (a bright
                    // "head") lands on the wrong end for half the shower — which is why sparks
                    // looked like they were flying in different directions.
                    float along = saturate(input.uv.x);
                    float lateral = input.uv.y * 2.0 - 1.0;

                    float caps = smoothstep(0.0, _CapSoftness, along)
                               * smoothstep(1.0, 1.0 - _CapSoftness, along);
                    float core = saturate(1.0 - abs(lateral));
                    body = pow(core, _Sharpness) * caps;
                    edge = pow(core, 1.6) * caps * 0.55;
                }

                float3 colour = _CoreColour.rgb * body + _RimColour.rgb * edge * _RimStrength;
                colour *= _Brightness * life;
                return half4(colour, input.color.a);
            }
            ENDHLSL
        }
    }
}
