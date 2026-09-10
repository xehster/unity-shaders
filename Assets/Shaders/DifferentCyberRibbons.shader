Shader "Custom/CyberShell_FractalFold"
{
    Properties
    {
        [Header(Colors)]
        _ArmorColor ("Armor Base Color", Color) = (0.05, 0.08, 0.12, 1.0)
        _GlowColor ("Energy Node Color", Color) = (1.0, 0.3, 0.0, 1.0)
        
        [Header(Fractal Form)]
        _Scale ("Entity Size", Range(0.1, 3.0)) = 1.0
        _Complexity ("Fractal Iterations", Range(2, 6)) = 4.0
        _FoldAngle ("Base Fold Angle", Range(0.0, 3.14)) = 0.5
        _Offset ("Fractal Density", Range(0.05, 0.5)) = 0.2
        _OpenProgress ("Open/Disassemble", Range(0.0, 2.0)) = 0.0
        
        [Header(Shell Bounds)]
        _OuterRadius ("Outer Sphere Limit", Range(0.5, 2.0)) = 1.2
        
        [Toggle] _EnableInnerHollow ("Enable Inner Hollow Cut", Float) = 1.0
        _InnerRadius ("Inner Hollow Size", Range(0.1, 1.5)) = 0.8
        
        _Thickness ("Strut Thickness", Range(0.01, 0.2)) = 0.04
        
        [Header(Dynamics)]
        _Speed ("Animation Speed", Range(0.0, 3.0)) = 1.0
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
                float4 _ArmorColor, _GlowColor;
                float _Scale, _Complexity, _FoldAngle, _Offset, _OpenProgress;
                float _OuterRadius, _InnerRadius, _Thickness, _Speed;
                float _EnableInnerHollow;
            CBUFFER_END

            float2x2 rot(float a) {
                float s = sin(a), c = cos(a);
                return float2x2(c, -s, s, c);
            }

            float map(float3 p, out float nodeGlow) {
                float3 q = p / _Scale;
                float time = _Time.y * _Speed;

                // Базовое вращение всей скорлупы
                q.xy = mul(rot(time * 0.15), q.xy);
                q.xz = mul(rot(time * 0.2), q.xz);

                float scaleAccumulator = 1.0;
                
                // --- ФРАКТАЛ ---
                for (int i = 0; i < (int)_Complexity; i++) {
                    q = abs(q) - (_Offset + _OpenProgress * 0.2); 
                    
                    q.xy = mul(rot(_FoldAngle + time * 0.2), q.xy);
                    q.yz = mul(rot(_FoldAngle * 0.7 - time * 0.15), q.yz);
                    
                    q *= 1.3;
                    scaleAccumulator *= 1.3;
                }

                float fractalForm = (length(q.xz) - _Thickness * scaleAccumulator) / scaleAccumulator;

                // --- ГРАНИЦЫ ОБОЛОЧКИ ---
                float outerBound = length(p / _Scale) - _OuterRadius;
                
                // Ограничиваем фрактал снаружи
                float shell = max(fractalForm, outerBound); 
                
                // Опциональный вырез внутри (пустота для ядра)
                if (_EnableInnerHollow > 0.5) {
                    float innerBound = length(p / _Scale) - _InnerRadius;
                    shell = max(shell, -innerBound); 
                }

                nodeGlow = smoothstep(0.02, 0.0, fractalForm * scaleAccumulator);

                return shell * _Scale;
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
                float glowMask = 0.0;
                bool hit = false;
                
                for (int i = 0; i < 90; i++) {
                    float3 p = ro + rd * t;
                    
                    if (abs(p.x) > 4.0 || abs(p.y) > 4.0 || abs(p.z) > 4.0) break;
                    
                    float d = map(p, glowMask);
                    
                    if (d < 0.001) { hit = true; break; }
                    t += d * 0.6; 
                }

                if (!hit) discard;

                float3 p = ro + rd * t;
                float3 n = calcNormal(p);

                float fresnel = pow(1.0 - max(dot(-rd, n), 0.0), 2.0);
                float3 lightDir = normalize(float3(1.0, 1.0, -1.0));
                float spec = pow(max(dot(reflect(-lightDir, n), -rd), 0.0), 32.0) * 0.7;

                float3 baseMetal = _ArmorColor.rgb + (fresnel * 0.6) + spec;
                float3 glow = _GlowColor.rgb * glowMask * 3.0;
                
                return float4(baseMetal + glow, 0.95);
            }
            ENDHLSL
        }
    }
}