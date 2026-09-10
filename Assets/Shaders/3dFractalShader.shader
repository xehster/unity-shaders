Shader "Custom/3DFractalShader"
{
    Properties
    {
        _MainColor ("Physical Body Color", Color) = (0.02, 0.02, 0.02, 1)
        _GlowColor ("Neon Energy", Color) = (0.3, 0.0, 1.0, 1.0)
        _Scale ("Entity Size (Keep small!)", Range(0.1, 1.0)) = 0.5
        _Speed ("Morph Speed", Range(0.0, 3.0)) = 1.0
        _Fold ("Fractal Folds", Range(1, 5)) = 4
    }
    SubShader
    {
        // Используем AlphaTest, чтобы полностью отрезать пустоту (как у настоящей 3D модели)
        Tags 
        { 
            "RenderType"="TransparentCutout" 
            "Queue"="AlphaTest" 
            "RenderPipeline"="UniversalPipeline"
        }
        Blend SrcAlpha OneMinusSrcAlpha
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
                float _Scale;
                float _Speed;
                float _Fold;
            CBUFFER_END

            float2x2 rot(float a)
            {
                float s = sin(a), c = cos(a);
                return float2x2(c, -s, s, c);
            }

            // Настоящая жесткая физическая 3D форма (SDF)
            float map(float3 p, out float glow)
            {
                float time = _Time.y * _Speed;
                glow = 0.0;

                // 1. Ось симметрии (эффект Роршаха)
                p.x = abs(p.x);

                // Держим объект строго в центре и уменьшаем
                float3 z = p / _Scale;
                float s = 1.0;

                // 2. KIFS Фрактал (сворачивание пространства для создания шипов)
                int iters = (int)_Fold;
                for (int i = 0; i < iters; i++)
                {
                    // Острые складки
                    z = abs(z) - float3(0.3, 0.5, 0.2);
                    
                    // Жесткое 3D вращение
                    z.xy = mul(rot(time * 0.4 + float(i)), z.xy);
                    z.xz = mul(rot(time * 0.3 - float(i)*0.5), z.xz);
                    
                    z *= 1.6;
                    s *= 1.6;
                    
                    // Накапливаем свечение только в глубине складок
                    glow += exp(-length(z) * 0.3);
                }

                // Базовая форма - пересечение кубов (дает механическо-органический вид)
                float3 d = abs(z) - float3(0.5, 1.0, 0.5);
                float dist = (length(max(d, 0.0)) + min(max(d.x, max(d.y, d.z)), 0.0)) / s;
                
                return dist * _Scale;
            }

            // Вычисление 3D нормалей для физического освещения
            float3 calcNormal(float3 p)
            {
                float2 e = float2(0.002, 0.0);
                float dummy;
                return normalize(float3(
                    map(p + e.xyy, dummy) - map(p - e.xyy, dummy),
                    map(p + e.yxy, dummy) - map(p - e.yxy, dummy),
                    map(p + e.yyx, dummy) - map(p - e.yyx, dummy)
                ));
            }

            Varyings vert(Attributes input)
            {
                Varyings output;
                VertexPositionInputs vertexInput = GetVertexPositionInputs(input.positionOS.xyz);
                output.positionCS = vertexInput.positionCS;
                
                // Координаты старта луча (поверхность куба)
                output.localPos = input.positionOS.xyz;
                
                // Вектор от камеры до поверхности куба в локальных координатах
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
                float glow = 0.0;
                int steps = 0;
                int maxSteps = 80;

                // Пускаем луч ВНУТРЬ куба
                for (int i = 0; i < maxSteps; i++)
                {
                    float3 p = ro + rd * t;
                    
                    // Если луч улетел за пределы куба 1х1х1 - прерываем
                    if (abs(p.x) > 1.0 || abs(p.y) > 1.0 || abs(p.z) > 1.0) break;

                    float currentGlow;
                    d = map(p, currentGlow);
                    
                    if (d < 0.002) // Уперлись в твердую поверхность
                    {
                        glow = currentGlow;
                        steps = i;
                        break;
                    }
                    t += d;
                }

                // Если мы ничего не задели внутри куба - делаем пиксель невидимым!
                if (d >= 0.002) discard;

                // --- ФИЗИЧЕСКОЕ ОСВЕЩЕНИЕ ---
                float3 hitPoint = ro + rd * t;
                float3 normal = calcNormal(hitPoint);

                // 1. Направленный свет (как от солнца или фонаря)
                float3 lightDir = normalize(float3(0.8, 1.0, -0.5));
                float diffuse = max(dot(normal, lightDir), 0.0);
                
                // 2. Фейковое Ambient Occlusion (затенение в углублениях на основе количества шагов луча)
                float ao = 1.0 - ((float)steps / (float)maxSteps);
                ao = pow(ao, 2.0);

                // 3. Fresnel (блеск на краях объекта, как у металла/пластика)
                float fresnel = pow(1.0 - max(dot(normal, -rd), 0.0), 3.0);

                // Сборка цвета
                float3 baseRender = _MainColor.rgb * diffuse * ao;
                float3 specular = float3(1,1,1) * fresnel * 0.5;
                
                // Динамическая смена цвета неона (перелив)
                float3 neonTint = lerp(_GlowColor.rgb, float3(0, 1, 0.8), sin(_Time.y * 2.0 - glow) * 0.5 + 0.5);
                float3 emissive = neonTint * smoothstep(1.0, 5.0, glow) * 2.5;

                float3 finalColor = baseRender + specular + emissive;

                return float4(finalColor, 1.0);
            }
            ENDHLSL
        }
    }
}