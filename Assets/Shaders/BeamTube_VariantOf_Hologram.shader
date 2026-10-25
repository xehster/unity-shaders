Shader "Purrfield/Beam Tube (Variant of Hologram)"
{
    Properties
    {
        [HDR] _Color ("Color", Color) = (0.38, 1.4, 1.8, 1)
        _Alpha ("Opacity", Range(0, 1)) = 0.8
        _PulseSpeed ("Pulse Speed", Range(0, 12)) = 3
        _PulseDensity ("Pulses Along Length", Range(0, 30)) = 7
        _PulseStrength ("Pulse Strength", Range(0, 1)) = 0.25
        _FresnelStrength ("Edge Glow", Range(0, 2)) = 0.35
    }

    SubShader
    {
        Tags
        {
            "RenderType" = "Transparent"
            "Queue" = "Transparent"
            "RenderPipeline" = "UniversalPipeline"
        }

        Pass
        {
            Name "BeamTube"
            Blend SrcAlpha One
            ZWrite Off
            ZTest LEqual
            Cull Back

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            CBUFFER_START(UnityPerMaterial)
                half4 _Color;
                half _Alpha;
                float _PulseSpeed;
                float _PulseDensity;
                half _PulseStrength;
                half _FresnelStrength;
            CBUFFER_END

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                float2 uv : TEXCOORD0;
                half4 color : COLOR;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 positionWS : TEXCOORD0;
                half3 normalWS : TEXCOORD1;
                float2 uv : TEXCOORD2;
                half4 color : COLOR;
            };

            Varyings vert(Attributes input)
            {
                Varyings output;
                output.positionWS = TransformObjectToWorld(input.positionOS.xyz);
                output.positionCS = TransformWorldToHClip(output.positionWS);
                output.normalWS = TransformObjectToWorldNormal(input.normalOS);
                output.uv = input.uv;
                output.color = input.color;
                return output;
            }

            half4 frag(Varyings input) : SV_Target
            {
                half pulseWave = 0.5 + 0.5 * sin(
                    (input.uv.x * _PulseDensity - _Time.y * _PulseSpeed) * 6.2831853);
                half pulse = lerp(1.0, pulseWave, _PulseStrength);

                half3 normalWS = normalize(input.normalWS);
                half3 viewWS = GetWorldSpaceNormalizeViewDir(input.positionWS);
                half fresnel = 1.0 - saturate(abs(dot(normalWS, viewWS)));
                half glow = 1.0 + fresnel * _FresnelStrength;

                // Per-vertex RGB carries the beam's colour along its length
                // (ProceduralBeamTube writes a near->far blend for compound
                // beams). _Color stays as a global intensity/tint multiplier.
                half3 tint = input.color.rgb * _Color.rgb;
                half alpha = saturate(_Alpha * input.color.a * pulse);
                return half4(tint * glow * alpha, alpha);
            }
            ENDHLSL
        }
    }
}
