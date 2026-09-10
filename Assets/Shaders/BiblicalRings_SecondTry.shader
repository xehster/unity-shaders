Shader "Custom/BiblicalRings_CrystalDome"
{
    Properties
    {
        [Header(Ring Base Material)]
        _RingColor ("Ring Base Color", Color) = (0.5, 0.4, 0.2, 1.0)
        _Metallic ("Ring Metallic", Range(0.0, 1.0)) = 0.8
        _Roughness ("Ring Roughness", Range(0.01, 1.0)) = 0.3
        
        [Header(Solid Iris Colors Inside Dome)]
        _OuterRingColor ("1. Outer Ring Color", Color) = (0.0, 0.0, 0.0, 1.0)
        _MidRingColor ("2. Mid Ring Color", Color) = (0.0, 0.5, 0.8, 1.0)
        _InnerRingColor ("3. Inner Ring Color", Color) = (0.2, 0.0, 0.4, 1.0)
        _PupilColor ("4. Pupil Color (Red)", Color) = (1.0, 0.1, 0.1, 1.0)
        
        [Header(Ring Settings)]
        _RingThickness ("Ring Thickness (Radial)", Range(0.01, 0.2)) = 0.05
        _RingDepth ("Ring Depth (Height)", Range(0.01, 0.2)) = 0.02
        _Scale ("Global Scale", Range(0.1, 2.0)) = 1.0
        _RingCount ("Ring Count", Range(1, 6)) = 3
        
        [Header(Eye Visibility Toggles)]
        [Toggle] _ShowOuterEyes ("Show Outer Eyes", Float) = 1.0
        [Toggle] _ShowInnerEyes ("Show Inner Eyes", Float) = 1.0
        
        [Header(Crystal Glass Solid Iris Settings)]
        _EyeCount ("Eyes per Ring", Range(1, 16)) = 6
        _DomeSize ("Glass Dome Size (Radius)", Range(0.01, 0.3)) = 0.08
        _DomeEmbedding ("Dome Embedding Depth", Range(-0.05, 0.05)) = -0.015
        _GlassAlpha ("Glass Surface Tint", Range(0.0, 0.5)) = 0.1
        _GlassGloss ("Glass Specular Intensity", Range(10.0, 128.0)) = 90.0
        _Speed ("Rotation Speed", Range(0, 2)) = 0.5
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

            struct Attributes 
            { 
                float4 positionOS : POSITION; 
            };

            struct Varyings 
            { 
                float4 positionCS : SV_POSITION; 
                float3 localPos : TEXCOORD0; 
                float3 viewDirOS : TEXCOORD1; 
            };

            CBUFFER_START(UnityPerMaterial)
                float4 _RingColor;
                float4 _OuterRingColor;
                float4 _MidRingColor;
                float4 _InnerRingColor;
                float4 _PupilColor;
                float _Metallic;
                float _Roughness;
                float _RingThickness;
                float _RingDepth;
                float _Scale;
                float _RingCount;
                float _ShowOuterEyes;
                float _ShowInnerEyes;
                float _EyeCount;
                float _DomeSize;
                float _DomeEmbedding;
                float _GlassAlpha;
                float _GlassGloss;
                float _Speed;
            CBUFFER_END

            float3 rotateRing(float3 p, float angle, int index) 
            {
                float s = sin(angle);
                float c = cos(angle);
                if(index == 0) return float3(c * p.x - s * p.z, p.y, s * p.x + c * p.z);
                if(index == 1) return float3(p.x, c * p.y - s * p.z, s * p.y + c * p.z);
                if(index == 2) return float3(c * p.x - s * p.y, s * p.x + c * p.y, p.z);
                if(index == 3) return float3(c * p.x - s * p.z, c * p.y - s * p.z, s * p.x + c * p.z);
                return float3(c * p.x - s * p.y, s * p.x + c * p.y, c * p.z);
            }

            float sdFlatRing(float3 p, float radius, float thick, float depth) 
            {
                float2 q = float2(length(p.xz) - radius, p.y);
                float2 b = float2(thick, depth);
                float2 d = abs(q) - b;
                return min(max(d.x, d.y), 0.0) + length(max(d, 0.0));
            }

            void getEyeDetails(float3 lp, float3 domePos, out float3 irisColor)
            {
                float radius = _DomeSize * 0.75;
                float3 rel = lp - domePos;
                float r = length(rel) / max(radius, 0.001);
                
                float pupilMask = 1.0 - smoothstep(0.0, 0.15, r);
                float innerMask = 1.0 - smoothstep(0.15, 0.35, r);
                float midMask   = 1.0 - smoothstep(0.35, 0.65, r);
                float outerMask = 1.0 - smoothstep(0.65, 0.95, r);

                float3 finalCol = _OuterRingColor.rgb * outerMask;
                finalCol = lerp(finalCol, _MidRingColor.rgb, midMask);
                finalCol = lerp(finalCol, _InnerRingColor.rgb, innerMask);
                finalCol = lerp(finalCol, _PupilColor.rgb, pupilMask);

                irisColor = finalCol;
            }

            float mapAndShade(float3 p, bool ignoreGlass, out float3 outColor, out int materialType, out float3 normal) 
            {
                float3 q = p / _Scale;
                float minDst = 10.0;
                outColor = _RingColor.rgb;
                materialType = 0;
                normal = float3(0, 1, 0);
                
                for(int i = 0; i < 6; i++) 
                {
                    if(i >= (int)_RingCount) break;
                    
                    float t = _Time.y * _Speed * (1.0 + float(i) * 0.3);
                    float3 lp = rotateRing(q, t, i);
                    
                    float radius = 1.0 + float(i) * 0.25;
                    float ringDst = sdFlatRing(lp, radius, _RingThickness, _RingDepth);
                    
                    float angle = atan2(lp.z, lp.x);
                    float seg = 6.2831853 / max(_EyeCount, 1.0);
                    float id = floor(angle / seg);
                    float eyeAngle = (id + 0.5) * seg;
                    float2 dir = float2(cos(eyeAngle), sin(eyeAngle));
                    
                    float3 domeOuterPos = float3(dir.x * (radius + _RingThickness + _DomeEmbedding), 0.0, dir.y * (radius + _RingThickness + _DomeEmbedding));
                    float3 domeInnerPos = float3(dir.x * (radius - _RingThickness + _DomeEmbedding), 0.0, dir.y * (radius - _RingThickness + _DomeEmbedding));
                    
                    if(_ShowOuterEyes > 0.5) 
                    {
                        float solidOuter = length(lp - domeOuterPos) - (_DomeSize * 0.75);
                        if(solidOuter < minDst) 
                        {
                            minDst = solidOuter;
                            materialType = 2;
                            normal = normalize(lp - domeOuterPos);
                            getEyeDetails(lp, domeOuterPos, outColor);
                        }
                    }
                    if(_ShowInnerEyes > 0.5) 
                    {
                        float solidInner = length(lp - domeInnerPos) - (_DomeSize * 0.75);
                        if(solidInner < minDst) 
                        {
                            minDst = solidInner;
                            materialType = 2;
                            normal = normalize(lp - domeInnerPos);
                            getEyeDetails(lp, domeInnerPos, outColor);
                        }
                    }

                    if(!ignoreGlass) 
                    {
                        if(_ShowOuterEyes > 0.5) 
                        {
                            float domeOuter = length(lp - domeOuterPos) - _DomeSize;
                            if(domeOuter < minDst) 
                            {
                                minDst = domeOuter;
                                materialType = 3;
                                normal = normalize(lp - domeOuterPos);
                            }
                        }
                        if(_ShowInnerEyes > 0.5) 
                        {
                            float domeInner = length(lp - domeInnerPos) - _DomeSize;
                            if(domeInner < minDst) 
                            {
                                minDst = domeInner;
                                materialType = 3;
                                normal = normalize(lp - domeInnerPos);
                            }
                        }
                    }

                    if(ringDst < minDst) 
                    {
                        minDst = ringDst;
                        materialType = 1; 
                        
                        normal = normalize(float3(lp.x * (length(lp.xz) - radius) / max(length(lp.xz), 0.001), lp.y, lp.z * (length(lp.xz) - radius) / max(length(lp.xz), 0.001)));
                        
                        float3 lightDir = normalize(float3(1.0, 1.0, -1.0));
                        float3 halfDir = normalize(lightDir - normalize(lp));
                        
                        // Конвертируем roughness в степень блеска (shininess)
                        float specularPower = lerp(2.0, 128.0, 1.0 - saturate(_Roughness));
                        float spec = pow(max(dot(normal, halfDir), 0.0), specularPower);
                        
                        float3 metalColor = lerp(_RingColor.rgb, _RingColor.rgb * spec * 4.0 + spec * 2.0, _Metallic);
                        outColor = metalColor;
                    }
                }
                return minDst * _Scale;
            }

            Varyings vert(Attributes v) 
            {
                Varyings o;
                o.positionCS = TransformObjectToHClip(v.positionOS.xyz);
                o.localPos = v.positionOS.xyz;
                o.viewDirOS = normalize(v.positionOS.xyz - TransformWorldToObject(GetCameraPositionWS()));
                return o;
            }

            float4 frag(Varyings i) : SV_Target 
            {
                float3 rd = normalize(i.viewDirOS);
                float3 ro = i.localPos;
                float t = 0.0;
                float4 accumulatedColor = float4(0, 0, 0, 0);
                bool ignoreGlass = false;
                
                for(int stepIndex = 0; stepIndex < 64; stepIndex++) 
                {
                    float3 p = ro + rd * t;
                    float3 col = float3(0,0,0);
                    int matType = 0;
                    float3 n = float3(0,1,0);
                    
                    float d = mapAndShade(p, ignoreGlass, col, matType, n);
                    
                    if(d < 0.001) 
                    {
                        if(matType == 3) 
                        {
                            float3 lightDir = normalize(float3(1.0, 1.0, -1.0));
                            float3 halfDir = normalize(lightDir - rd);
                            float spec = pow(max(dot(n, halfDir), 0.0), _GlassGloss);
                            
                            accumulatedColor.rgb += (float3(1,1,1) * spec * 2.0) * (1.0 - accumulatedColor.a);
                            accumulatedColor.a += _GlassAlpha * (1.0 - accumulatedColor.a);
                            
                            ignoreGlass = true;
                            t += 0.015;
                            continue;
                        }
                        else if(matType == 2 || matType == 1) 
                        {
                            accumulatedColor.rgb += col * (1.0 - accumulatedColor.a);
                            accumulatedColor.a = 1.0;
                            break;
                        }
                    }
                    
                    t += d;
                    if(t > 5.0 || accumulatedColor.a >= 0.99) break;
                }
                return accumulatedColor;
            }
            ENDHLSL
        }
    }
}