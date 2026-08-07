Shader "Custom/ConcreteTriplanar"
{
    // Триплanar (box-проекция) PBR-шейдер для URP.
    // Повторяет материал из Blender: BaseColor*AO -> Lerp к белому, Roughness->Smoothness, Normal.
    // Текстуру кладёт по мировым координатам, развёртка (UV) не нужна — работает на любых boolean-мешах.
    Properties
    {
        [MainTexture] _BaseColorMap ("Base Color", 2D) = "white" {}
        _NormalMap   ("Normal (sRGB OFF)", 2D) = "bump" {}
        _RoughnessMap("Roughness (sRGB OFF)", 2D) = "gray" {}
        _AOMap       ("AO (sRGB OFF)", 2D) = "white" {}

        _Tiling         ("Tiling (как Blender Scale)", Float) = 0.3
        _WhiteMix       ("White Mix", Range(0,1)) = 0.45
        _NormalStrength ("Normal Strength", Float) = 1.8
        _Sharpness      ("Triplanar Sharpness", Range(1,16)) = 4.0
        _Tint           ("Tint", Color) = (1,1,1,1)
        _VertexSnapPixels ("Vertex Grid Height (0 = off)", Float) = 240

        // Object-space режим: текстура «приклеена» к мешу и вращается вместе с ним.
        // Для статичной геометрии не нужен (мировая проекция бесшовна между объектами),
        // но для вращающихся предметов только так видно, что они крутятся.
        [Toggle(_OBJECT_SPACE_TRIPLANAR)] _ObjectSpaceTriplanar ("Project in Object Space", Float) = 0
        _ObjectTiling   ("Tiling in Object Space", Float) = 6.0
    }

    // PS1-стиль: снап вершин к виртуальной пиксельной сетке (см. Purrfield/PS1 Lit).
    // Текстуры триплanarные (мировые координаты), поэтому не "плывут" — дрожит только силуэт.

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        // ---------------- Forward Lit ----------------
        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForward" }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            // освещение/тени URP
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile_fragment _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile_fragment _ _SHADOWS_SOFT
            #pragma multi_compile _ _SCREEN_SPACE_OCCLUSION
            #pragma multi_compile _ _FORWARD_PLUS
            #pragma multi_compile _ LIGHTMAP_ON
            #pragma multi_compile _ DIRLIGHTMAP_COMBINED
            #pragma multi_compile_fog
            #pragma shader_feature_local _OBJECT_SPACE_TRIPLANAR

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            TEXTURE2D(_BaseColorMap); SAMPLER(sampler_BaseColorMap);
            TEXTURE2D(_NormalMap);    SAMPLER(sampler_NormalMap);
            TEXTURE2D(_RoughnessMap); SAMPLER(sampler_RoughnessMap);
            TEXTURE2D(_AOMap);        SAMPLER(sampler_AOMap);

            CBUFFER_START(UnityPerMaterial)
                float _Tiling;
                float _WhiteMix;
                float _NormalStrength;
                float _Sharpness;
                float4 _Tint;
                float _VertexSnapPixels;
                float _ObjectTiling;
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
                float3 normalOS   : NORMAL;
                float2 uv         : TEXCOORD0;
                float2 lightmapUV : TEXCOORD1;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 positionWS : TEXCOORD0;
                float3 normalWS   : TEXCOORD1;
                float  fogFactor  : TEXCOORD2;
                DECLARE_LIGHTMAP_OR_SH(lightmapUV, vertexSH, 3);
                #if defined(_OBJECT_SPACE_TRIPLANAR)
                    float3 positionOS : TEXCOORD4;
                    float3 normalOS   : TEXCOORD5;
                #endif
            };

            Varyings vert (Attributes IN)
            {
                Varyings OUT = (Varyings)0;
                VertexPositionInputs p = GetVertexPositionInputs(IN.positionOS.xyz);
                VertexNormalInputs   n = GetVertexNormalInputs(IN.normalOS);
                OUT.positionCS = ApplyVertexSnap(p.positionCS);
                OUT.positionWS = p.positionWS;
                OUT.normalWS   = n.normalWS;
                #if defined(_OBJECT_SPACE_TRIPLANAR)
                    OUT.positionOS = IN.positionOS.xyz;
                    OUT.normalOS   = IN.normalOS;
                #endif
                OUT.fogFactor  = ComputeFogFactor(p.positionCS.z);
                OUTPUT_LIGHTMAP_UV(IN.lightmapUV, unity_LightmapST, OUT.lightmapUV);
                OUTPUT_SH(OUT.normalWS, OUT.vertexSH);
                return OUT;
            }

            // веса блендинга по граням куба
            float3 TriWeights(float3 n)
            {
                float3 w = pow(abs(n), _Sharpness);
                return w / max(w.x + w.y + w.z, 1e-5);
            }

            float3 SampleTriColor(TEXTURE2D_PARAM(tex, smp), float3 wp, float3 w, float tiling)
            {
                float2 uvX = wp.zy * tiling;
                float2 uvY = wp.xz * tiling;
                float2 uvZ = wp.xy * tiling;
                float3 cx = SAMPLE_TEXTURE2D(tex, smp, uvX).rgb;
                float3 cy = SAMPLE_TEXTURE2D(tex, smp, uvY).rgb;
                float3 cz = SAMPLE_TEXTURE2D(tex, smp, uvZ).rgb;
                return cx * w.x + cy * w.y + cz * w.z;
            }

            // триплanar нормаль (whiteout blend)
            float3 SampleTriNormal(float3 wp, float3 geomN, float3 w, float tiling)
            {
                float2 uvX = wp.zy * tiling;
                float2 uvY = wp.xz * tiling;
                float2 uvZ = wp.xy * tiling;
                float3 nx = SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, uvX).rgb * 2.0 - 1.0;
                float3 ny = SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, uvY).rgb * 2.0 - 1.0;
                float3 nz = SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, uvZ).rgb * 2.0 - 1.0;
                nx.xy *= _NormalStrength; ny.xy *= _NormalStrength; nz.xy *= _NormalStrength;
                // переориентируем тангент-нормали в мировые по осям
                float3 wnX = float3(nx.z * sign(geomN.x), nx.y, nx.x);
                float3 wnY = float3(ny.x, ny.z * sign(geomN.y), ny.y);
                float3 wnZ = float3(nz.x, nz.y, nz.z * sign(geomN.z));
                float3 res = normalize(wnX * w.x + wnY * w.y + wnZ * w.z + geomN * 0.001);
                return res;
            }

            half4 frag (Varyings IN) : SV_Target
            {
                float3 wp = IN.positionWS;
                float3 geomN = normalize(IN.normalWS);

                // В object-space режиме проецируем по координатам меша: текстура «прибита»
                // к поверхности и вращается вместе с объектом.
                #if defined(_OBJECT_SPACE_TRIPLANAR)
                    float3 projP = IN.positionOS;
                    float3 projN = normalize(IN.normalOS);
                    float  tiling = _ObjectTiling;
                #else
                    float3 projP = wp;
                    float3 projN = geomN;
                    float  tiling = _Tiling;
                #endif

                float3 w = TriWeights(projN);

                float3 baseCol = SampleTriColor(TEXTURE2D_ARGS(_BaseColorMap, sampler_BaseColorMap), projP, w, tiling);
                float3 ao3     = SampleTriColor(TEXTURE2D_ARGS(_AOMap, sampler_AOMap), projP, w, tiling);
                float  rough   = SampleTriColor(TEXTURE2D_ARGS(_RoughnessMap, sampler_RoughnessMap), projP, w, tiling).r;
                float  ao      = ao3.r;

                // как в Blender: base*AO -> подмешать белый
                float3 albedo = baseCol * lerp(1.0, ao, 0.7);
                albedo = lerp(albedo, float3(1,1,1), _WhiteMix) * _Tint.rgb;

                float3 triNormal = SampleTriNormal(projP, projN, w, tiling);
                #if defined(_OBJECT_SPACE_TRIPLANAR)
                    // нормаль собрана в объектном пространстве — вернём её в мировое
                    float3 normalWS = normalize(TransformObjectToWorldNormal(triNormal));
                #else
                    float3 normalWS = triNormal;
                #endif

                SurfaceData s = (SurfaceData)0;
                s.albedo     = albedo;
                s.metallic   = 0.0;
                s.smoothness = saturate(1.0 - rough);
                s.occlusion  = ao;
                s.alpha      = 1.0;

                InputData inp = (InputData)0;
                inp.positionWS = wp;
                inp.normalWS   = normalWS;
                inp.viewDirectionWS = GetWorldSpaceNormalizeViewDir(wp);
                inp.shadowCoord = TransformWorldToShadowCoord(wp);
                inp.fogCoord    = IN.fogFactor;
                inp.bakedGI     = SAMPLE_GI(IN.lightmapUV, IN.vertexSH, normalWS);
                inp.normalizedScreenSpaceUV = GetNormalizedScreenSpaceUV(IN.positionCS);
                inp.shadowMask  = unity_ProbesOcclusion;

                half4 color = UniversalFragmentPBR(inp, s);
                color.rgb = MixFog(color.rgb, IN.fogFactor);
                return color;
            }
            ENDHLSL
        }

        // ---------------- Тени ----------------
        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode"="ShadowCaster" }
            ZWrite On ColorMask 0
            HLSLPROGRAM
            #pragma vertex vertS
            #pragma fragment fragS
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            CBUFFER_START(UnityPerMaterial)
                float _Tiling;
                float _WhiteMix;
                float _NormalStrength;
                float _Sharpness;
                float4 _Tint;
                float _VertexSnapPixels;
                float _ObjectTiling;
            CBUFFER_END
            float3 _LightDirection;
            float3 _LightPosition;
            struct A { float4 positionOS:POSITION; float3 normalOS:NORMAL; };
            struct V { float4 positionCS:SV_POSITION; };
            V vertS (A IN)
            {
                V o;
                float3 wp = TransformObjectToWorld(IN.positionOS.xyz);
                float3 wn = TransformObjectToWorldNormal(IN.normalOS);
                #if defined(_CASTING_PUNCTUAL_LIGHT_SHADOW)
                    float3 lightDir = normalize(_LightPosition - wp);
                #else
                    float3 lightDir = _LightDirection;
                #endif
                o.positionCS = TransformWorldToHClip(ApplyShadowBias(wp, wn, lightDir));
                #if UNITY_REVERSED_Z
                    o.positionCS.z = min(o.positionCS.z, UNITY_NEAR_CLIP_VALUE);
                #else
                    o.positionCS.z = max(o.positionCS.z, UNITY_NEAR_CLIP_VALUE);
                #endif
                return o;
            }
            half4 fragS (V IN):SV_Target { return 0; }
            ENDHLSL
        }

        // ---------------- DepthOnly ----------------
        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode"="DepthOnly" }
            ZWrite On ColorMask 0
            HLSLPROGRAM
            #pragma vertex vertD
            #pragma fragment fragD
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            CBUFFER_START(UnityPerMaterial)
                float _Tiling;
                float _WhiteMix;
                float _NormalStrength;
                float _Sharpness;
                float4 _Tint;
                float _VertexSnapPixels;
                float _ObjectTiling;
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
            struct A { float4 positionOS:POSITION; };
            struct V { float4 positionCS:SV_POSITION; };
            V vertD (A IN){ V o; o.positionCS = ApplyVertexSnap(TransformObjectToHClip(IN.positionOS.xyz)); return o; }
            half4 fragD (V IN):SV_Target { return 0; }
            ENDHLSL
        }

        // ---------------- DepthNormals (для SSAO) ----------------
        Pass
        {
            Name "DepthNormals"
            Tags { "LightMode"="DepthNormals" }
            ZWrite On
            HLSLPROGRAM
            #pragma vertex vertN
            #pragma fragment fragN
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            CBUFFER_START(UnityPerMaterial)
                float _Tiling;
                float _WhiteMix;
                float _NormalStrength;
                float _Sharpness;
                float4 _Tint;
                float _VertexSnapPixels;
                float _ObjectTiling;
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
            struct A { float4 positionOS:POSITION; float3 normalOS:NORMAL; };
            struct V { float4 positionCS:SV_POSITION; float3 normalWS:TEXCOORD0; };
            V vertN (A IN)
            {
                V o;
                o.positionCS = ApplyVertexSnap(TransformObjectToHClip(IN.positionOS.xyz));
                o.normalWS = TransformObjectToWorldNormal(IN.normalOS);
                return o;
            }
            half4 fragN (V IN):SV_Target { return half4(normalize(IN.normalWS) * 0.5 + 0.5, 0); }
            ENDHLSL
        }
    }
    FallBack "Universal Render Pipeline/Lit"
}
