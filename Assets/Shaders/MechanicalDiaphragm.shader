Shader "Custom/CyberEntity_OriginalMaterial"
{
    Properties
    {
        _ArmorColor ("Armor Material", Color) = (0.05, 0.08, 0.12, 1.0)
        _InnerColor ("Inner Mechanism", Color) = (0.3, 0.3, 0.3, 1.0)
        _GlowColor ("Core Energy", Color) = (1.0, 0.3, 0.0, 1.0)
        
        _Scale ("Entity Size", Range(0.1, 2.0)) = 1.0
        _CoreSize ("Core Size", Range(0.02, 0.5)) = 0.12
        _SphereSize ("Outer Sphere Size", Range(0.5, 1.5)) = 0.9
        
        [Toggle] _InvertHoles ("Invert to Patches", Float) = 0
        _HoleSize ("Hole Expansion", Range(-0.5, 0.5)) = 0.0
        
        _Complexity ("Inner Complexity", Range(2, 6)) = 4.0
        _Speed ("Animation Speed", Range(0.0, 3.0)) = 1.0
    }
    SubShader
    {
        Tags { "RenderType"="Transparent" "Queue"="Transparent" }
        Blend SrcAlpha OneMinusSrcAlpha
        Cull Off ZWrite Off

        Pass
        {
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            struct Attributes { float4 positionOS : POSITION; };
            struct Varyings { float4 positionCS : SV_POSITION; float3 localPos : TEXCOORD0; float3 viewDir : TEXCOORD1; };

            CBUFFER_START(UnityPerMaterial)
                float4 _ArmorColor, _InnerColor, _GlowColor;
                float _Scale, _CoreSize, _SphereSize, _InvertHoles, _HoleSize, _Complexity, _Speed;
            CBUFFER_END

            float2x2 rot(float a) { float s = sin(a), c = cos(a); return float2x2(c, -s, s, c); }

            float map(float3 p, out int id) {
                float3 q = p / _Scale;
                float time = _Time.y * _Speed;

                // 1. ЯДРО
                float core = length(q) - _CoreSize;
                id = 2;

                // 2. ВНУТРЕННИЙ МЕХАНИЗМ (Тот самый сложный объемный фрактал)
                float3 fp = q;
                for(int i = 0; i < (int)_Complexity; i++) {
                    fp = abs(fp) - 0.18;
                    fp.xy = mul(rot(0.5 + time * 0.3), fp.xy);
                    fp.xz = mul(rot(0.7 - time * 0.2), fp.xz);
                    fp *= 1.3;
                }
                float inner = length(fp.xz) - 0.03;
                if (inner < core) { core = inner; id = 1; }

                // 3. СФЕРА С ОСТРЫМИ ДЫРКАМИ
                float outerShell = abs(length(q) - _SphereSize) - 0.03;
                float3 hq = q;
                hq.xy = mul(rot(time * 0.2), hq.xy);
                hq.yz = mul(rot(time * 0.15), hq.yz);
                
                float holes = sin(hq.x * 5.0 + time) * cos(hq.y * 5.0 - time) * sin(hq.z * 5.0 + time * 0.5);
                float sharpHoles = step(0.1 + _HoleSize, holes);
                
                if (_InvertHoles > 0.5) outerShell = max(outerShell, sharpHoles - 0.5);
                else outerShell = max(outerShell, -sharpHoles + 0.5);

                if (outerShell < core) { core = outerShell; id = 0; }
                return core * _Scale;
            }

            Varyings vert(Attributes input) {
                Varyings output;
                output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
                output.localPos = input.positionOS.xyz;
                output.viewDir = normalize(input.positionOS.xyz - TransformWorldToObject(GetCameraPositionWS()));
                return output;
            }

            float4 frag(Varyings input) : SV_Target {
                float3 ro = input.localPos;
                float3 rd = input.viewDir;
                float t = 0.0;
                int id = -1;
                
                for(int i = 0; i < 80; i++) {
                    float3 p = ro + rd * t;
                    int curId;
                    float d = map(p, curId);
                    if (d < 0.001) { id = curId; break; }
                    t += d * 0.8;
                    if (t > 2.5) discard;
                }
                
                if (id == -1) discard;

                // Возвращаем оригинальные материалы для каждого слоя
                if (id == 2) {
                    return float4(_GlowColor.rgb * 6.0, 1.0); // Ядро
                }
                if (id == 1) {
                    return float4(_InnerColor.rgb * 1.5, 1.0); // Тот самый крутой внутренний механизм
                }
                
                return float4(_ArmorColor.rgb, 0.9); // Внешняя броня
            }
            ENDHLSL
        }
    }
}