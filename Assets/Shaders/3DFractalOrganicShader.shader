Shader "Custom/3dFractalOrganic"
{
    Properties
    {
        _MainColor ("Physical Body Color", Color) = (0.02, 0.02, 0.02, 1)
        _GlowColor ("Core Neon Color", Color) = (0.0, 0.9, 1.0, 1.0)
        _RingColor ("Ring Solid Color", Color) = (0.0, 0.8, 1.0, 1.0)
        _Scale ("Entity Size", Range(0.01, 1.0)) = 0.3
        _Speed ("Morph Speed", Range(0.0, 3.0)) = 0.8
        
        [Header(Breathing and Pulse)]
        _PulseIntensity ("Pulse Intensity", Range(0.0, 0.3)) = 0.08
        _PulseSpeed ("Pulse Speed", Range(0.1, 20.0)) = 1.2

        [Header(Unified Core and Spikes)]
        _Fold ("Fractal Iterations", Range(2, 6)) = 4
        _Blending ("Core Fusion (Smoothness)", Range(0.05, 1.0)) = 0.3
        _SpikeLength ("Spike Extension", Range(0.1, 2.0)) = 0.8
        
        [Header(Orbital Rings Angelic)]
        [Toggle] _EnableRings ("Enable Orbital Rings", Float) = 1.0
        _RingCount ("Ring Count", Range(1, 6)) = 3
        _RingSpeed ("Base Rotation Speed", Range(0.0, 5.0)) = 1.5
        _RingRadius ("Ring Diameter", Range(0.1, 2.0)) = 0.75
        _RingThickness ("Ring Thickness", Range(0.005, 0.1)) = 0.02

        [Header(Glitch VFX)]
        _GlitchAberration ("Chromatic Aberration", Range(0.0, 2.0)) = 1.0
    }
    SubShader
    {
        Tags 
        { 
            "RenderType"="Transparent" 
            "Queue"="Transparent" 
            "RenderPipeline"="UniversalPipeline"
        }
        Blend SrcAlpha OneMinusSrcAlpha
        Cull Off
        ZWrite Off

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
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 localPos   : TEXCOORD0;
                float3 viewDirOS  : TEXCOORD1;
            };

            CBUFFER_START(UnityPerMaterial)
                float4 _MainColor;
                float4 _GlowColor;
                float4 _RingColor;
                float _Scale;
                float _Speed;
                float _PulseIntensity;
                float _PulseSpeed;
                float _Fold;
                float _Blending;
                float _SpikeLength;
                float _EnableRings;
                float _RingCount;
                float _RingSpeed;
                float _RingRadius;
                float _RingThickness;
                float _GlitchAberration;
            CBUFFER_END

            float2x2 rot(float a)
            {
                float s = sin(a), c = cos(a);
                return float2x2(c, -s, s, c);
            }

            // Плавный минимум с жестким контролем, предотвращающий распад на капли
            float smin(float a, float b, float k)
            {
                float h = max(k - abs(a - b), 0.0);
                return min(a, b) - h * h * 0.25 / k;
            }

            float sdTorus(float3 p, float2 t)
            {
                float2 q = float2(length(p.xz) - t.x, p.y);
                return length(q) - t.y;
            }

            float mapDetailed(float3 p, out float bodyGlow, out float ringGlow, out float minDistRings)
            {
                float time = _Time.y * _Speed;
                float pulseTime = _Time.y * _PulseSpeed;
                
                bodyGlow = 0.0;
                ringGlow = 0.0;
                
                float pulse = 1.0 + sin(pulseTime) * _PulseIntensity;
                float safeScale = max(_Scale * pulse, 0.001);

                // --- 1. ЦЕНТРАЛЬНОЕ ПЛОТНОЕ ТЕЛО ---
                float3 pBody = p;
                pBody.x = abs(pBody.x);

                float3 z = pBody / safeScale;
                float s = 1.0;
                float minDist = 10.0;

                int iters = (int)_Fold;
                for (int j = 0; j < iters; j++)
                {
                    z.xy = mul(rot(time * 0.2 + (float)j * 0.7), z.xy);
                    z.xz = mul(rot(time * 0.15 - (float)j * 0.4), z.xz);
                    
                    // Смещение для монолитности формы вместо точечных шариков
                    z = abs(z) - float3(0.3, 0.5, 0.3) * _SpikeLength;
                    
                    z *= 1.3;
                    s *= 1.3;

                    float elementDist = length(z) / s;
                    minDist = smin(minDist, elementDist, _Blending);
                    
                    bodyGlow += exp(-length(z) * 0.4);
                }

                // Базовая плотная оболочка ядра
                float centralCore = length(pBody / safeScale) - 0.75;
                // Объединяем с нашими складками через жесткий сглаженный минимум
                float finalDist = smin(centralCore, minDist, _Blending * 1.5);
                finalDist *= safeScale;

                minDistRings = 999.0;

                // --- 2. ОРБИТАЛЬНЫЕ КОЛЬЦА ---
                if (_EnableRings > 0.5)
                {
                    int count = (int)_RingCount;
                    float ringTime = _Time.y * _RingSpeed;

                    [unroll(6)]
                    for (int k = 0; k < count; k++)
                    {
                        float index = (float)k;
                        float3 pRing = p;

                        float tiltX = index * 1.25 + 0.4;
                        float tiltY = index * 0.95 + 0.8;

                        pRing.yz = mul(rot(tiltX), pRing.yz);
                        pRing.xy = mul(rot(tiltY), pRing.xy);

                        float speedDir = (index % 2 == 0) ? 1.0 : -1.0;
                        float currentAngle = ringTime * (0.8 + index * 0.4) * speedDir + index * 2.0;
                        
                        pRing.xz = mul(rot(currentAngle), pRing.xz);
                        pRing.xy = mul(rot(currentAngle * 0.5), pRing.xy);

                        float rDist = sdTorus(pRing, float2(_RingRadius, _RingThickness));
                        minDistRings = min(minDistRings, rDist);

                        if (rDist < 0.15)
                        {
                            ringGlow += (0.1 / (rDist + 0.01));
                        }
                    }

                    finalDist = smin(finalDist, minDistRings, 0.04);
                }

                return finalDist;
            }

            float3 calcNormal(float3 p)
            {
                float2 e = float2(0.002, 0.0);
                float dummy1, dummy2, dummy3;
                return normalize(float3(
                    mapDetailed(p + e.xyy, dummy1, dummy2, dummy3) - mapDetailed(p - e.xyy, dummy1, dummy2, dummy3),
                    mapDetailed(p + e.yxy, dummy1, dummy2, dummy3) - mapDetailed(p - e.yxy, dummy1, dummy2, dummy3),
                    mapDetailed(p + e.yyx, dummy1, dummy2, dummy3) - mapDetailed(p - e.yyx, dummy1, dummy2, dummy3)
                ));
            }

            Varyings vert(Attributes input)
            {
                Varyings output;
                VertexPositionInputs vertexInput = GetVertexPositionInputs(input.positionOS.xyz);
                output.positionCS = vertexInput.positionCS;
                output.localPos = input.positionOS.xyz;
                float3 objCamPos = TransformWorldToObject(GetCameraPositionWS());
                output.viewDirOS = normalize(input.positionOS.xyz - objCamPos);
                return output;
            }

            float4 frag(Varyings input) : SV_Target
            {
                float3 ro = input.localPos; 
                float3 rd = input.viewDirOS;

                float t = 0.0;
                float d = 0.0;
                float bodyGlow = 0.0;
                float ringGlow = 0.0;
                float minDistRings = 999.0;
                int steps = 0;
                int maxSteps = 100;

                for (int i = 0; i < maxSteps; i++)
                {
                    float3 p = ro + rd * t;
                    if (abs(p.x) > 5.5 || abs(p.y) > 5.5 || abs(p.z) > 5.5) break;

                    d = mapDetailed(p, bodyGlow, ringGlow, minDistRings);
                    
                    if (d < 0.001)
                    {
                        steps = i;
                        break;
                    }
                    t += max(d * 0.55, 0.001);
                }

                if (d >= 0.001) discard;

                float3 hitPoint = ro + rd * t;

                bool hitRingSurface = (_EnableRings > 0.5 && minDistRings < 0.015);

                if (hitRingSurface)
                {
                    return float4(_RingColor.rgb * 2.0, 1.0);
                }

                float3 normal = calcNormal(hitPoint);
                float3 lightDir = normalize(float3(0.8, 1.0, -0.5));
                float diffuse = max(dot(normal, lightDir), 0.0);
                float ao = pow(1.0 - ((float)steps / (float)maxSteps), 2.0);
                float fresnel = pow(1.0 - max(dot(normal, -rd), 0.0), 3.0);

                float3 baseRender = _MainColor.rgb * diffuse * ao;
                float3 specular = float3(1, 1, 1) * fresnel * 0.6;
                
                float colorShift = dot(normal, float3(1, 0, 0)) * _GlitchAberration;
                
                float3 coreEmissive;
                coreEmissive.r = smoothstep(0.2, 10.0, bodyGlow + colorShift) * _GlowColor.r;
                coreEmissive.g = smoothstep(0.2, 10.0, bodyGlow) * _GlowColor.g;
                coreEmissive.b = smoothstep(0.2, 10.0, bodyGlow - colorShift) * _GlowColor.b;
                coreEmissive *= 4.5;

                float3 finalColor = baseRender + specular + coreEmissive;
                return float4(finalColor, 1.0);
            }
            ENDHLSL
        }
    }
}