Shader "Custom/CyberRibbons_ComplexShell"
{
    Properties
    {
        [Header(Colors and Materials)]
        _ArmorColor ("Armor Base Color", Color) = (0.08, 0.1, 0.14, 1.0)
        _PulseColor ("Pulse Energy Color", Color) = (1.0, 0.3, 0.0, 1.0)
        
        [Header(Complex Form)]
        _Scale ("Entity Size", Range(0.1, 3.0)) = 1.0
        _RibbonCount ("Number of Ribbons", Range(2, 12)) = 6.0
        _OpenProgress ("Armor Expansion", Range(0.0, 2.0)) = 0.2
        _TwistForce ("Twist Amount", Range(0.0, 3.0)) = 1.5
        
        [Header(Thickness and Sharpness)]
        _RibbonWidth ("Ribbon Width", Range(0.01, 0.3)) = 0.15
        _BaseThickness ("Base Thickness", Range(0.005, 0.15)) = 0.03
        _TipSharpness ("Tip Sharpness", Range(0.0, 1.0)) = 0.8
        _ThicknessPulse ("Thickness Pulsation", Range(0.0, 1.0)) = 0.8
        
        [Header(Dynamics)]
        _Speed ("Animation Speed", Range(0.0, 3.0)) = 1.0
        _PulseSpeed ("Energy Pulse Speed", Range(0.0, 10.0)) = 2.0
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
                float4 _ArmorColor, _PulseColor;
                float _Scale, _RibbonCount, _OpenProgress, _TwistForce;
                float _RibbonWidth, _BaseThickness, _TipSharpness, _ThicknessPulse;
                float _Speed, _PulseSpeed;
            CBUFFER_END

            float2x2 rot(float a) {
                float s = sin(a), c = cos(a);
                return float2x2(c, -s, s, c);
            }

            // Математика сложной закрученной оболочки
            float map(float3 p, out float energyNode) {
                float time = _Time.y * _Speed;
                float pulseTime = _Time.y * _PulseSpeed;
                float3 q = p / _Scale;

                // 1. ПРОСТРАНСТВЕННОЕ СКРУЧИВАНИЕ (эффект "закрытия в себя")
                // Чем выше/ниже точка, тем сильнее закручивается лента + анимация
                float twist = q.y * _TwistForce - time * 0.5;
                q.xz = mul(rot(twist), q.xz);

                // 2. ПОЛЯРНОЕ РАЗМНОЖЕНИЕ (Polar Repetition)
                // Превращаем пространство в N секторов по кругу
                float angle = atan2(q.z, q.x);
                float radius = length(q.xz);
                float sector = 6.2831853 / floor(_RibbonCount);
                
                // Центрируем каждый сегмент
                angle = (frac(angle / sector + 0.5) - 0.5) * sector;
                
                // Возвращаем в декартовы координаты локально для одной ленты
                float3 tp = q;
                tp.x = radius * cos(angle);
                tp.z = radius * sin(angle);

                // 3. ФОРМИРОВАНИЕ СФЕРИЧЕСКОГО КАРКАСА
                // Ленты огибают центр. cos(tp.y) сужает их к полюсам
                float poleTaper = cos(clamp(tp.y * 0.7, -1.57, 1.57)); 
                float currentRadius = (1.0 + _OpenProgress * abs(tp.y)) * poleTaper;

                // 4. ПУЛЬСАЦИЯ УЗЛОВ (Энергия)
                float wave = max(0.0, sin(tp.y * 8.0 - pulseTime * 4.0) * cos(tp.z * 15.0 + pulseTime * 2.0));
                float localNode = pow(wave, 3.0); 
                energyNode = localNode; // Отдаем для раскраски
                
                float bulgeAmount = localNode * _ThicknessPulse * _BaseThickness * 2.0;

                // 5. ЗАТОЧКА КРАЕВ (Taper)
                float tipTaper = lerp(1.0, smoothstep(1.6, 0.2, abs(tp.y)), _TipSharpness);
                tipTaper = max(tipTaper, 0.02);

                // 6. ГЕОМЕТРИЯ САМОЙ ЛЕНТЫ (Плоская изогнутая пластина)
                // Смещаем пластину на радиус каркаса
                float2 ribbonPos = float2(tp.x - currentRadius, tp.z);
                
                float currentThickness = (_BaseThickness + bulgeAmount) * tipTaper;
                float currentWidth = _RibbonWidth * tipTaper;
                
                // Функция Box SDF (Прямоугольник со скругленными краями)
                float2 d = abs(ribbonPos) - float2(currentThickness, currentWidth);
                float ribbons = length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - 0.01;

                // Обрезаем макушки, чтобы не слипались в острую точку (если не нужно)
                ribbons = max(ribbons, abs(tp.y) - 1.6); 

                return ribbons * _Scale;
            }

            float3 calcNormal(float3 p) {
                float2 e = float2(0.002, 0.0);
                float dummy;
                return normalize(float3(
                    map(p + e.xyy, dummy) - map(p - e.xyy, dummy),
                    map(p + e.yxy, dummy) - map(p - e.yxy, dummy),
                    map(p + e.yyx, dummy) - map(p - e.yyx, dummy)
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
                float energyMask = 0.0;
                bool hit = false;
                
                // РЕЙ-МАРЧИНГ
                for (int i = 0; i < 90; i++) {
                    float3 p = ro + rd * t;
                    
                    if (abs(p.x) > 3.0 || abs(p.y) > 3.0 || abs(p.z) > 3.0) break;
                    
                    float d = map(p, energyMask);
                    
                    if (d < 0.001) {
                        hit = true;
                        break;
                    }
                    t += d * 0.7; // Сниженный шаг для сложных изгибов (избегает артефактов)
                }

                if (!hit) discard;

                float3 p = ro + rd * t;
                float3 n = calcNormal(p);

                // --- МАТЕРИАЛ И СВЕТ ---
                float fresnel = pow(1.0 - max(dot(-rd, n), 0.0), 2.5);
                
                float3 lightDir = normalize(float3(1.0, 1.5, -1.0));
                float spec = pow(max(dot(reflect(-lightDir, n), -rd), 0.0), 32.0) * 0.6;

                float3 baseMetal = _ArmorColor.rgb + (fresnel * 0.7) + spec;
                float3 glow = _PulseColor.rgb * energyMask * 4.0;
                
                float3 finalColor = baseMetal + glow;

                return float4(finalColor, 0.95);
            }
            ENDHLSL
        }
    }
}