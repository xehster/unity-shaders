Shader "Custom/BiblicalRings_TrueDomeLenses"
{
    Properties
    {
        [Header(Ring Base Material)]
        _RingColor ("Base Metal Color", Color) = (0.8, 0.7, 0.5, 1.0)
        _RingGloss ("Metal Glossiness", Range(1.0, 64.0)) = 20.0
        
        [Header(Lens Material)]
        _OuterRingColor ("1. Outer Ring", Color) = (0.0, 0.0, 0.0, 1.0)
        _MidRingColor ("2. Mid Ring (Glow)", Color) = (0.0, 0.8, 1.0, 1.0)
        _InnerRingColor ("3. Thick Ring", Color) = (0.0, 0.0, 0.0, 1.0)
        _PupilColor ("4. Pupil", Color) = (1.0, 0.1, 0.1, 1.0)
        _LensGloss ("Lens Specular Intensity", Range(1.0, 128.0)) = 100.0
        
        [Header(Ring Geometry)]
        _RingThickness ("Ring Depth", Range(0.01, 0.2)) = 0.05
        _RingWidth ("Ring Width", Range(0.01, 0.5)) = 0.15
        
        [Header(Ring Layout)]
        _Scale ("Global Scale", Range(0.1, 5.0)) = 1.0
        _RingCount ("Number of Rings", Range(1, 7)) = 3.0
        _Radius ("Outer Radius", Range(0.5, 3.0)) = 1.5
        _Spacing ("Spacing Between Rings", Range(0.01, 0.3)) = 0.15
        
        [Header(Lens Settings)]
        [Enum(Simple Dots,0,Concentric Lens,1)] _EyeStyle ("Eye Style", Float) = 1.0
        _EyeCount ("Number of Lenses", Range(0, 20)) = 8.0
        _EyeScale ("Overall Eye Size", Range(0.05, 0.5)) = 0.15
        _DomeHeight ("Lens Dome Height (Volume)", Range(0.0, 0.2)) = 0.05
        
        [Header(Dynamics)]
        _Speed ("Rotation Speed", Range(0.0, 5.0)) = 1.0
    }
    SubShader
    {
        Tags { "RenderType"="Transparent" "Queue"="Transparent" }
        Blend SrcAlpha OneMinusSrcAlpha
        Cull Off 
        ZWrite Off

        Pass
        {
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            struct Attributes { float4 positionOS : POSITION; };
            struct Varyings { 
                float4 positionCS : SV_POSITION; 
                float3 localPos : TEXCOORD0; 
                float3 viewDirOS : TEXCOORD1; 
            };

            CBUFFER_START(UnityPerMaterial)
                float4 _RingColor, _OuterRingColor, _MidRingColor, _InnerRingColor, _PupilColor;
                float _Scale, _RingCount, _Radius, _Spacing, _RingThickness, _RingWidth, _RingGloss, _LensGloss;
                float _EyeStyle, _EyeCount, _EyeScale, _DomeHeight, _Speed;
            CBUFFER_END

            float2x2 rot(float a) {
                float s = sin(a), c = cos(a);
                return float2x2(c, -s, s, c);
            }

            float sdRibbon(float3 p, float radius, float thickness, float width) {
                float2 d = float2(abs(length(p.xz) - radius) - width, abs(p.y) - thickness);
                return min(max(d.x, d.y), 0.0) + length(max(d, 0.0));
            }

            // Функция маппинга теперь объединяет кольцо и реальный выпуклый купол линзы
            float map(float3 p, out float4 lensLayers, out float ringDistOut) {
                float3 q = p / _Scale;
                float time = _Time.y * _Speed;
                
                float minDst = 1000.0;
                float4 currentLayers = 0.0;
                
                for(int i = 0; i < 7; i++) {
                    if (i >= (int)_RingCount) break;
                    
                    float3 lp = q;
                    float phase = float(i) * 2.1415;
                    float speedMult = 1.0 + float(i) * 0.3;
                    
                    lp.xy = mul(rot(time * 0.7 * speedMult + phase), lp.xy);
                    lp.xz = mul(rot(time * 1.1 * speedMult - phase), lp.xz);
                    lp.yz = mul(rot(time * 0.9 * speedMult + phase * 0.5), lp.yz);
                    
                    float rad = _Radius - float(i) * _Spacing;
                    float ringDist = sdRibbon(lp, rad, _RingThickness, _RingWidth);
                    
                    float angle = atan2(lp.z, lp.x);
                    float segmentAngle = 6.2831853 / max(_EyeCount, 1.0);
                    float localAngle = (frac(angle / segmentAngle + 0.5) - 0.5) * segmentAngle;
                    float distAlongRing = localAngle * rad;
                    float distVert = lp.y;
                    
                    float4 layers = 0.0;
                    float finalElementDist = ringDist;

                    if (_EyeStyle > 0.5) {
                        float2 eyePos = float2(distAlongRing, distVert);
                        float r = length(eyePos);
                        
                        // Проверяем попадание в зону глаза
                        if (r < _EyeScale) {
                            // Создаем физическую выпуклость (купол) поверх кольца
                            // Считаем высоту сферы в этой точке
                            float sphereH = sqrt(max(0.0, _EyeScale * _EyeScale - r * r)) * (_DomeHeight / _EyeScale);
                            
                            // Отодвигаем поверхность ближе к камере (выпуклый купол)
                            // Координата Y кольца минус высота купола
                            float domeDist = abs(lp.y) - (_RingThickness + sphereH);
                            
                            // Объединяем геометрию кольца и купола линзы
                            finalElementDist = min(ringDist, domeDist);
                            
                            // Текстура/слои линзы по радиусу
                            float normR = r / _EyeScale;
                            float c1 = smoothstep(1.0, 0.85, normR);
                            float c2 = smoothstep(0.7,  0.55, normR);
                            float c3 = smoothstep(0.4,  0.25, normR);
                            float c4 = smoothstep(0.15, 0.05, normR);
                            
                            layers = float4(c1*(1.0-c2), c2*(1.0-c3), c3*(1.0-c4), c4);
                        }
                    } else {
                        float eyes = sin(angle * _EyeCount - time * 3.0);
                        float vMask = smoothstep(_RingThickness * 2.0, _RingThickness * 0.5, abs(lp.y));
                        layers = float4(0.0, 0.0, 0.0, smoothstep(0.85, 0.95, eyes) * vMask);
                    }
                    
                    if (finalElementDist < minDst) {
                        minDst = finalElementDist;
                        currentLayers = layers;
                    }
                }

                lensLayers = currentLayers;
                ringDistOut = minDst;
                return minDst * _Scale;
            }

            float3 calcNormal(float3 p) {
                float2 e = float2(0.002, 0.0);
                float4 dummyL; float dummyD;
                return normalize(float3(
                    map(p + e.xyy, dummyL, dummyD) - map(p - e.xyy, dummyL, dummyD),
                    map(p + e.yxy, dummyL, dummyD) - map(p - e.yxy, dummyL, dummyD),
                    map(p + e.yyx, dummyL, dummyD) - map(p - e.yyx, dummyL, dummyD)
                ));
            }

            Varyings vert(Attributes input) {
                Varyings output;
                output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
                output.localPos = input.positionOS.xyz;
                output.viewDirOS = normalize(input.positionOS.xyz - TransformWorldToObject(GetCameraPositionWS()));
                return output;
            }

            float4 frag(Varyings input) : SV_Target {
                float3 ro = input.localPos;
                float3 rd = input.viewDirOS;
                float t = 0.0;
                float4 lensLayers = 0.0;
                float finalDist = 0.0;
                bool hit = false;
                
                for (int i = 0; i < 80; i++) {
                    float3 p = ro + rd * t;
                    float d = map(p, lensLayers, finalDist);
                    if (d < 0.001) { hit = true; break; }
                    t += d; 
                    if (t > 15.0) break;
                }

                if (!hit) discard;

                float3 p = ro + rd * t;
                float3 n = calcNormal(p); // Нормаль теперь учитывает реальную выпуклость купола!
                
                float3 lightDir = normalize(float3(1.0, 1.0, -1.0));
                float3 halfDir = normalize(lightDir - rd);

                // 1. Освещение металла колец
                float metalSpec = pow(max(dot(n, halfDir), 0.0), _RingGloss);
                float3 baseMetal = _RingColor.rgb * 0.6 + metalSpec;

                // 2. Освещение линзы с учетом объемного преломления/блика по выпуклой форме
                float lensSpec = pow(max(dot(n, halfDir), 0.0), _LensGloss);
                float3 lensColorBase = (lensLayers.x * _OuterRingColor.rgb) 
                                     + (lensLayers.y * _MidRingColor.rgb) 
                                     + (lensLayers.z * _InnerRingColor.rgb) 
                                     + (lensLayers.w * _PupilColor.rgb);
                float3 lensFinal = lensColorBase + lensSpec * 3.0;

                // 3. Смешивание
                float totalMask = saturate(lensLayers.x + lensLayers.y + lensLayers.z + lensLayers.w);
                float3 finalColor = lerp(baseMetal, lensFinal, totalMask);

                return float4(finalColor, 0.95);
            }
            ENDHLSL
        }
    }
}