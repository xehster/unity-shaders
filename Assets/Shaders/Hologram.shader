// Placement hologram: additive fresnel + scrolling scanlines, tinted by the
// placer (blue = valid spot, red = invalid). Used by the machine spawner ghost
// and its beam. Keeps the PS1 vertex snap so the hologram jitters like
// everything else in the world.
Shader "Purrfield/Hologram"
{
    Properties
    {
        [HDR] _Color ("Color", Color) = (0.25, 0.75, 1, 1)
        _Alpha ("Opacity", Range(0, 1)) = 0.55
        _BaseGlow ("Base Glow (faces)", Range(0, 1)) = 0.35
        _FresnelPower ("Fresnel Power", Range(0.5, 8)) = 2.5
        _ScanlineDensity ("Scanlines per meter", Range(0, 60)) = 18
        _ScanlineStrength ("Scanline Strength", Range(0, 1)) = 0.45
        _ScanlineSpeed ("Scanline Scroll Speed", Range(-4, 4)) = 0.6
        _VertexSnapPixels ("Vertex Grid Height (0 = off)", Float) = 240
        [Toggle] _BeamMode ("Beam Mode (LineRenderer projector cone)", Float) = 0
        _BeamPulseSpeed ("Beam Pulse Speed", Range(0, 12)) = 4
        _BeamPulseDensity ("Beam Pulses along length", Range(0, 30)) = 9
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
            Name "Hologram"
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
                half _BaseGlow;
                half _FresnelPower;
                float _ScanlineDensity;
                half _ScanlineStrength;
                float _ScanlineSpeed;
                float _VertexSnapPixels;
                float _BeamMode;
                float _BeamPulseSpeed;
                float _BeamPulseDensity;
            CBUFFER_END

            float4 ApplyVertexSnap(float4 positionCS)
            {
                if (_VertexSnapPixels < 1.0)
                    return positionCS;
                float aspect = _ScreenParams.x / max(_ScreenParams.y, 1.0);
                float2 grid = float2(_VertexSnapPixels * aspect, _VertexSnapPixels);
                float2 ndc = positionCS.xy / positionCS.w;
                ndc = floor(ndc * grid * 0.5) / (grid * 0.5) + 1.0 / grid;
                positionCS.xy = ndc * positionCS.w;
                return positionCS;
            }

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                float2 uv : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 positionWS : TEXCOORD0;
                half3 normalWS : TEXCOORD1;
                float2 uv : TEXCOORD2;
            };

            Varyings vert(Attributes v)
            {
                Varyings o;
                o.positionWS = TransformObjectToWorld(v.positionOS.xyz);
                o.normalWS = TransformObjectToWorldNormal(v.normalOS);
                o.positionCS = ApplyVertexSnap(TransformWorldToHClip(o.positionWS));
                o.uv = v.uv;
                return o;
            }

            half4 frag(Varyings i) : SV_Target
            {
                half a;
                if (_BeamMode > 0.5)
                {
                    // LineRenderer strip: uv.x runs along the beam, uv.y across.
                    // Soft edges make the ribbon read as a volumetric light cone;
                    // pulses stream from the hand toward the hologram.
                    half edge = smoothstep(0.5, 0.1, abs(i.uv.y - 0.5));
                    half pulse = 0.65 + 0.35 * sin((i.uv.x * _BeamPulseDensity - _Time.y * _BeamPulseSpeed) * 6.2831853);
                    half fade = lerp(1.0, 0.45, i.uv.x); // dimmer toward the wide end
                    a = edge * pulse * fade * _Alpha;
                }
                else
                {
                    half3 n = normalize(i.normalWS);
                    half3 v = GetWorldSpaceNormalizeViewDir(i.positionWS);
                    half fres = pow(1.0 - saturate(abs(dot(n, v))), _FresnelPower);

                    float scanPhase = i.positionWS.y * _ScanlineDensity - _Time.y * _ScanlineSpeed * _ScanlineDensity;
                    half scan = lerp(1.0, 0.5 + 0.5 * sin(scanPhase * 6.2831853), _ScanlineStrength);

                    a = saturate(_BaseGlow + fres) * scan * _Alpha;
                }
                return half4(_Color.rgb * a, a);
            }
            ENDHLSL
        }
    }
}
