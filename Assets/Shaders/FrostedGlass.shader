Shader "Custom/Frosted Glass"
{
    // Frosted glass: the scene behind the surface, bent by the normal and smeared by a
    // ring of taps, with a lit edge on top. Needs Opaque Texture on in the URP asset,
    // that copy of the scene is the whole trick.
    Properties
    {
        _Tint ("Glass Colour", Color) = (0.62, 0.82, 0.95, 1)
        _Density ("Colour Strength", Range(0, 1)) = 0.6
        _HueDrift ("Hue Drift", Range(0, 1)) = 0
        _Cloud ("Cloudiness", Range(0, 1)) = 0.3

        _Frost ("Frost", Range(0, 1)) = 0.5
        _Grain ("Grain", Range(0, 1)) = 0.5
        _GrainScale ("Grain Scale", Range(1, 200)) = 60
        _Refraction ("Refraction", Range(0, 1)) = 0.25

        _EdgeColor ("Edge Colour", Color) = (1, 1, 1, 1)
        _EdgeStrength ("Edge Strength", Range(0, 2)) = 0.5
        _EdgePower ("Edge Falloff", Range(0.5, 8)) = 3

        _Smoothness ("Smoothness", Range(0, 1)) = 0.8
        _SpecStrength ("Specular", Range(0, 4)) = 1.2
    }

    SubShader
    {
        // Transparent queue so the opaque copy is already filled in by the time this
        // draws, but the output is solid, hence no blending.
        Tags { "RenderType"="Transparent" "Queue"="Transparent" "RenderPipeline"="UniversalPipeline" }

        Pass
        {
            Name "Glass"
            Tags { "LightMode"="UniversalForward" }

            ZWrite Off
            Cull Back

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareOpaqueTexture.hlsl"

            CBUFFER_START(UnityPerMaterial)
                half4 _Tint;
                float _Density;
                float _HueDrift;
                float _Cloud;
                float _Frost;
                float _Grain;
                float _GrainScale;
                float _Refraction;
                half4 _EdgeColor;
                float _EdgeStrength;
                float _EdgePower;
                float _Smoothness;
                float _SpecStrength;
            CBUFFER_END

            // taps around the ring, and the golden angle that spaces them out
            #define TAPS 12
            #define GLASS_GOLDEN_ANGLE 2.3999632
            #define TAU 6.2831853

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 positionOS : TEXCOORD0;
                float3 normalWS   : TEXCOORD1;
                float3 viewWS     : TEXCOORD2;
            };

            Varyings vert (Attributes IN)
            {
                Varyings OUT;
                VertexPositionInputs p = GetVertexPositionInputs(IN.positionOS.xyz);
                OUT.positionCS = p.positionCS;
                OUT.positionOS = IN.positionOS.xyz;
                OUT.normalWS = GetVertexNormalInputs(IN.normalOS).normalWS;
                OUT.viewWS = GetWorldSpaceNormalizeViewDir(p.positionWS);
                return OUT;
            }

            // The colour with its hue wound on by the clock. Leave the drift at zero and
            // this hands back the swatch untouched.
            float3 GlassColour ()
            {
                float3 hsv = RgbToHsv(_Tint.rgb);
                hsv.x = frac(hsv.x + _Time.y * _HueDrift * 0.1);
                return HsvToRgb(hsv);
            }

            float Hash (float3 p)
            {
                p = frac(p * 0.1031);
                p += dot(p, p.yzx + 33.33);
                return frac((p.x + p.y) * p.z);
            }

            half4 frag (Varyings IN) : SV_Target
            {
                float3 n = normalize(IN.normalWS);
                float3 v = normalize(IN.viewWS);
                float facing = saturate(dot(n, v));

                float2 screen = IN.positionCS.xy / _ScaledScreenParams.xy;
                float2 texel = 1.0 / _ScaledScreenParams.xy;

                // Bending the ray by the view space normal is the cheap stand-in for
                // refraction. It has no thickness behind it, but on a curved surface the
                // eye reads it as glass anyway.
                float3 normalVS = TransformWorldToViewDir(n);
                float2 bend = normalVS.xy * _Refraction * 0.1;

                // The grain rides the surface rather than the screen, so it stays put
                // when the glass turns. It offsets both the angle and the reach of the
                // ring, which is what makes the blur look etched instead of gaussian.
                float seed = Hash(IN.positionOS * _GrainScale);
                float reach = _Frost * 40.0 * lerp(1.0, 0.4 + seed * 1.6, _Grain);
                float phase = seed * TAU * _Grain;

                // a glancing view looks through more glass, so the smear grows there
                reach *= lerp(1.0, 3.0, 1.0 - facing);

                float3 behind = 0;
                [unroll]
                for (int i = 0; i < TAPS; i++)
                {
                    float step = (i + 0.5) / TAPS;
                    float angle = i * GLASS_GOLDEN_ANGLE + phase;
                    float2 ring = float2(cos(angle), sin(angle)) * sqrt(step) * reach;
                    behind += SampleSceneColor(screen + bend + ring * texel);
                }
                behind /= TAPS;

                float3 colour = GlassColour();
                float3 glass = lerp(behind, behind * colour, _Density);

                Light main = GetMainLight();

                // Etched glass throws some light back instead of passing it through, and
                // that milkiness is most of what tells the eye the surface is frosted.
                float3 milk = colour * (main.color * saturate(dot(n, main.direction)) * 0.5 + 0.5);
                glass = lerp(glass, milk, _Cloud);

                // edge: glass gathers light where it turns away from the eye
                float edge = pow(1.0 - facing, _EdgePower) * _EdgeStrength;

                float3 h = normalize(main.direction + v);
                float spec = pow(saturate(dot(n, h)), exp2(_Smoothness * 9.0 + 1.0));

                glass += _EdgeColor.rgb * edge;
                glass += main.color * spec * _SpecStrength;

                return half4(glass, 1.0);
            }
            ENDHLSL
        }
    }
}
