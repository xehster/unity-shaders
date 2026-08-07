Shader "Purrfield/Gradient Skybox"
{
    Properties
    {
        _TopColor ("Top Color", Color) = (0.62, 0.72, 0.85, 1)
        _HorizonColor ("Horizon Color", Color) = (0.90, 0.86, 0.84, 1)
        _BottomColor ("Bottom Color", Color) = (0.43, 0.41, 0.38, 1)
        _HorizonExp ("Horizon Softness", Range(0.1, 4)) = 0.55
        _SunColor ("Sun Color", Color) = (1, 0.94, 0.82, 1)
        _SunSize ("Sun Size", Range(0.0005, 0.1)) = 0.015
        _SunHaze ("Sun Haze", Range(0, 2)) = 0.7
        _SunDirection ("Sun Direction", Vector) = (0, 0.3, 1, 0)
    }

    SubShader
    {
        Tags
        {
            "RenderType" = "Background"
            "Queue" = "Background"
            "RenderPipeline" = "UniversalPipeline"
            "PreviewType" = "Skybox"
        }
        Cull Off
        ZWrite Off

        Pass
        {
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            CBUFFER_START(UnityPerMaterial)
                half4 _TopColor;
                half4 _HorizonColor;
                half4 _BottomColor;
                half _HorizonExp;
                half4 _SunColor;
                half _SunSize;
                half _SunHaze;
                float4 _SunDirection;
            CBUFFER_END

            struct Attributes
            {
                float4 positionOS : POSITION;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 dirWS : TEXCOORD0;
            };

            Varyings vert(Attributes v)
            {
                Varyings o;
                o.positionCS = TransformObjectToHClip(v.positionOS.xyz);
                // Skybox mesh vertices double as view directions.
                o.dirWS = v.positionOS.xyz;
                return o;
            }

            // Self-contained interleaved gradient noise for banding-free gradients.
            half IGN(float2 p)
            {
                return frac(52.9829189 * frac(dot(p, float2(0.06711056, 0.00583715))));
            }

            half4 frag(Varyings i) : SV_Target
            {
                float3 dir = normalize(i.dirWS);

                half up = saturate(dir.y);
                half down = saturate(-dir.y);

                half3 col = lerp(_HorizonColor.rgb, _TopColor.rgb, pow(up, _HorizonExp));
                col = lerp(col, _BottomColor.rgb, pow(down, 0.45));

                // Sun disc + horizon-hugging haze
                float3 sunDir = normalize(_SunDirection.xyz);
                half cosAngle = dot(dir, sunDir);
                half disc = smoothstep(1.0 - _SunSize, 1.0 - _SunSize * 0.35, cosAngle);
                half haze = pow(saturate(cosAngle), 10.0) * _SunHaze * (1.0 - abs(dir.y));
                col += _SunColor.rgb * (disc + haze * 0.30);

                // Dither against gradient banding
                col += (IGN(i.positionCS.xy) - 0.5) * (1.5 / 255.0);

                return half4(col, 1);
            }
            ENDHLSL
        }
    }
}
