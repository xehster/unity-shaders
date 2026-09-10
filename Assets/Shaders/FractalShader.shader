Shader "Custom/FractalShader"
{
    Properties
    {
        _Speed ("Inversion Speed", Range(0.0, 3.0)) = 0.8
        _Scale ("Core Scale", Range(0.5, 4.0)) = 1.6
        _Iterations ("Fractal Depth", Range(3, 8)) = 5
        _Complexity ("Warp Density", Range(0.5, 3.0)) = 1.2
        _Glow ("Bioluminescence", Range(0.5, 5.0)) = 2.0
    }
    SubShader
    {
        Tags 
        { 
            "RenderType"="Transparent" 
            "Queue"="Transparent" 
            "RenderPipeline"="UniversalPipeline"
        }
        Blend One One
        ZWrite Off
        Cull Off

        Pass
        {
            Name "Forward"
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv         : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 localPos   : TEXCOORD0;
                float3 viewDirOS  : TEXCOORD1;
            };

            CBUFFER_START(UnityPerMaterial)
                float _Speed;
                float _Scale;
                float _Iterations;
                float _Complexity;
                float _Glow;
            CBUFFER_END

            // Cosine Palette for Pseudohuasca Color Transitions
            float3 palette(float t)
            {
                float3 a = float3(0.5, 0.5, 0.5);
                float3 b = float3(0.5, 0.5, 0.5);
                float3 c = float3(1.0, 1.0, 1.0);
                float3 d = float3(0.263, 0.416, 0.557); // Deep Violet -> Acid Cyan/Green -> Pink
                return a + b * cos(6.28318 * (c * t + d));
            }

            // 2D Rotation Helper
            float2x2 rot(float a)
            {
                float s = sin(a), c = cos(a);
                return float2x2(c, -s, s, c);
            }

            // Central Inversion Distance Estimator (Volumetric Core)
            float map(float3 p, out float orbit)
            {
                float time = _Time.y * _Speed;
                
                // 1. Central Radial Inversion & Symmetry (Rorschach Fold)
                p.x = abs(p.x);
                
                float3 z = p * _Scale;
                float scale = 1.0;
                float trap = 1e5;

                int iterCount = (int)_Iterations;
                for (int i = 0; i < iterCount; i++)
                {
                    // Continuous Spherical Folding (Inverting space from center 0,0,0)
                    z = clamp(z, -1.0, 1.0) * 2.0 - z;
                    
                    float r2 = dot(z, z);
                    
                    // Inversion core logic: smaller than 0.25 scales up, creating infinite center generation
                    float factor = 1.4 / clamp(r2, 0.15, 1.0);
                    z *= factor;
                    scale *= factor;

                    // Twist the layers into alien-organic tentacles
                    z.xy = mul(z.xy, rot(time * 0.2 + float(i) * 0.3 * _Complexity));
                    z.xz = mul(z.xz, rot(time * 0.15));

                    trap = min(trap, length(z.xz) + 0.1 * abs(z.y));
                }

                orbit = trap;
                // Thin filaments expanding from origin
                return (length(z.xy) - 0.2) / scale;
            }

            Varyings vert(Attributes input)
            {
                Varyings output;
                VertexPositionInputs vertexInput = GetVertexPositionInputs(input.positionOS.xyz);
                output.positionCS = vertexInput.positionCS;
                output.localPos = input.positionOS.xyz;
                
                // Calculate ray direction in Local Object Space
                float3 objCamPos = TransformWorldToObject(GetCameraPositionWS());
                output.viewDirOS = normalize(input.positionOS.xyz - objCamPos);
                return output;
            }

            float4 frag(Varyings input) : SV_Target
            {
                // Raymarching through the volume of the sphere/cube
                float3 ro = input.localPos; // Ray Origin on surface
                float3 rd = input.viewDirOS; // Ray Direction pointing inwards

                float t = 0.0;
                float3 accumGlow = float3(0.0, 0.0, 0.0);
                float time = _Time.y * _Speed;

                // 3D Volume Marching through the center
                for (int i = 0; i < 40; i++)
                {
                    float3 p = ro + rd * t;

                    // Limit marching to local unit bounds
                    if (length(p) > 1.8) break;

                    float orbit = 0.0;
                    float d = map(p, orbit);

                    d = max(abs(d), 0.003);

                    // Volumetric energy density accumulation
                    float density = exp(-d * 6.0) * _Glow;
                    float3 col = palette(orbit * 0.12 + length(p) * 0.8 + time * 0.2);

                    accumGlow += col * density * 0.015;

                    t += d * 0.5; // Step forward
                }

                return float4(accumGlow, 1.0);
            }
            ENDHLSL
        }
    }
}