// Shared lit pass for Purrfield/PS1 Lit Chromatic.
// CHROMA_SIGN: 0 = main pass (no shift), +1 = red fringe, -1 = blue fringe.
// Expects Core.hlsl + the UnityPerMaterial cbuffer + snap/shift helpers from
// the shader's HLSLINCLUDE block.

#pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
#pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
#pragma multi_compile_fragment _ _ADDITIONAL_LIGHT_SHADOWS
#pragma multi_compile_fragment _ _SHADOWS_SOFT _SHADOWS_SOFT_LOW _SHADOWS_SOFT_MEDIUM _SHADOWS_SOFT_HIGH
#pragma multi_compile_fragment _ _SCREEN_SPACE_OCCLUSION
#pragma multi_compile _ _FORWARD_PLUS
#pragma multi_compile_fog

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

TEXTURE2D(_BaseMap);
SAMPLER(sampler_BaseMap);
TEXTURE2D(_EmissionMap);
SAMPLER(sampler_EmissionMap);

struct Attributes
{
    float4 positionOS : POSITION;
    float3 normalOS : NORMAL;
    float2 uv : TEXCOORD0;
};

struct Varyings
{
    float4 positionCS : SV_POSITION;
    float2 uv : TEXCOORD0;
    noperspective float2 uvAffine : TEXCOORD1;
    float3 positionWS : TEXCOORD2;
    half3 normalWS : TEXCOORD3;
    half fogFactor : TEXCOORD4;
};

Varyings vert(Attributes v)
{
    Varyings o;
    o.positionWS = TransformObjectToWorld(v.positionOS.xyz);
    o.normalWS = TransformObjectToWorldNormal(v.normalOS);
    float4 positionCS = ApplyVertexSnap(TransformWorldToHClip(o.positionWS));
#if defined(CHROMA_SIGN)
    #if CHROMA_SIGN != 0
        positionCS = ApplyChromaShift(positionCS, CHROMA_SIGN);
    #endif
#endif
    o.positionCS = positionCS;
    o.uv = TRANSFORM_TEX(v.uv, _BaseMap);
    o.uvAffine = o.uv;
    o.fogFactor = ComputeFogFactor(o.positionCS.z);
    return o;
}

half4 frag(Varyings i) : SV_Target
{
    float2 uv = lerp(i.uv, i.uvAffine, _AffineAmount);

    half4 albedo = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, uv) * _BaseColor;
    half3 emission = SAMPLE_TEXTURE2D(_EmissionMap, sampler_EmissionMap, uv).rgb * _EmissionColor.rgb;

    InputData inputData = (InputData)0;
    inputData.positionWS = i.positionWS;
    inputData.positionCS = i.positionCS;
    inputData.normalWS = normalize(i.normalWS);
    inputData.viewDirectionWS = GetWorldSpaceNormalizeViewDir(i.positionWS);
    inputData.shadowCoord = TransformWorldToShadowCoord(i.positionWS);
    inputData.fogCoord = i.fogFactor;
    inputData.bakedGI = SampleSH(inputData.normalWS);
    inputData.normalizedScreenSpaceUV = GetNormalizedScreenSpaceUV(i.positionCS);
    inputData.shadowMask = half4(1, 1, 1, 1);

    SurfaceData surfaceData = (SurfaceData)0;
    surfaceData.albedo = albedo.rgb;
    surfaceData.alpha = 1;
    surfaceData.emission = emission;
    surfaceData.specular = half3(0, 0, 0);
    surfaceData.smoothness = 0;
    surfaceData.occlusion = 1;

    half4 color = UniversalFragmentBlinnPhong(inputData, surfaceData);
    color.rgb = MixFog(color.rgb, inputData.fogCoord);
    return half4(color.rgb, 1);
}
