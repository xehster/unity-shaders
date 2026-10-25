#ifndef PURR_META_PASS_INCLUDED
#define PURR_META_PASS_INCLUDED

// Meta pass for our hand-written lit shaders — only the lightmapper runs it, to learn a surface's
// albedo (how much bounce it reflects) and emission (so glowing windows / bulbs light the room in
// the bake). Without this pass a lightmapped surface bakes as plain grey and never emits.
//
// Usage in a shader:
//      Pass { Name "Meta"  Tags { "LightMode"="Meta" }  Cull Off
//          HLSLPROGRAM
//          #pragma vertex PurrMetaVertex
//          #pragma fragment <yours>
//          #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
//          <the shader's own textures + UnityPerMaterial CBUFFER, identical to the forward pass>
//          #define PURR_META_ST _BaseMap_ST
//          #include "PurrMetaPass.hlsl"
//          half4 <yours>(PurrMetaVaryings i) : SV_Target { return PurrMetaOut(albedo, emission); }
//          ENDHLSL }

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/MetaInput.hlsl"

#ifndef PURR_META_ST
    #define PURR_META_ST float4(1, 1, 0, 0)
#endif

struct PurrMetaAttributes
{
    float4 positionOS : POSITION;
    float3 normalOS   : NORMAL;
    float2 uv0        : TEXCOORD0;
    float2 uv1        : TEXCOORD1;   // static lightmap UV — where the texel lands
    float2 uv2        : TEXCOORD2;   // realtime GI UV
};

struct PurrMetaVaryings
{
    float4 positionCS : SV_POSITION;
    float2 uv         : TEXCOORD0;
    float3 positionWS : TEXCOORD1;   // for shaders whose albedo is world-projected (triplanar)
    float3 normalWS   : TEXCOORD2;
};

PurrMetaVaryings PurrMetaVertex(PurrMetaAttributes v)
{
    PurrMetaVaryings o;
    o.positionCS = UnityMetaVertexPosition(v.positionOS.xyz, v.uv1, v.uv2);
    o.uv = v.uv0 * PURR_META_ST.xy + PURR_META_ST.zw;
    o.positionWS = TransformObjectToWorld(v.positionOS.xyz);
    o.normalWS = TransformObjectToWorldNormal(v.normalOS);
    return o;
}

half4 PurrMetaOut(half3 albedo, half3 emission)
{
    MetaInput meta = (MetaInput)0;
    meta.Albedo = albedo;
    meta.Emission = emission;
    return UnityMetaFragment(meta);
}

#endif // PURR_META_PASS_INCLUDED
