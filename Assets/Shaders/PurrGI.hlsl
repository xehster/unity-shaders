#ifndef PURR_GI_INCLUDED
#define PURR_GI_INCLUDED

// Baked indirect light for our hand-written lit shaders, Adaptive Probe Volume aware.
//
// With APV on (URP asset → Light Probe System = Adaptive Probe Volumes) the ambient no longer comes
// from the old spherical-harmonics probe (SampleSH / SAMPLE_GI with three arguments): URP's own
// shaders read the baked probe volume per pixel instead, and a shader that keeps calling SampleSH
// only gets the flat sky colour — no occlusion in alleys, no bounce. So:
//  • in the forward pass, next to the other multi_compiles:
//      #include_with_pragmas "Packages/com.unity.render-pipelines.universal/ShaderLibrary/ProbeVolumeVariants.hlsl"
//  • include this file after Lighting.hlsl;
//  • PurrProbeGI(positionWS, normalWS, positionCS) in place of SampleSH(normalWS), or
//    PURR_SAMPLE_GI(lightmapUV, vertexSH, positionWS, normalWS, positionCS) in place of
//    SAMPLE_GI(lightmapUV, vertexSH, normalWS) in shaders that declare DECLARE_LIGHTMAP_OR_SH.
// Without APV it falls back to exactly what the shader did before.

// Per-pixel, always (the shaders here have no per-vertex GI path worth keeping).
half3 PurrProbeGI(float3 positionWS, half3 normalWS, float4 positionCS)
{
#if defined(PROBE_VOLUMES_L1) || defined(PROBE_VOLUMES_L2)
    half3 gi;
    float4 probeOcclusion;
    if (_EnableProbeVolumes)
        EvaluateAdaptiveProbeVolume(GetAbsolutePositionWS(positionWS), normalWS,
            GetWorldSpaceNormalizeViewDir(positionWS), positionCS.xy, GetMeshRenderingLayer(),
            gi, probeOcclusion);
    else
        gi = EvaluateAmbientProbe(normalWS);
    return gi;
#else
    return SampleSH(normalWS);
#endif
}

// ── Lamp lightmaps ─────────────────────────────────────────────────────────────────────────────
// Static house geometry is lightmapped, but the lightmaps hold ONLY the interior lamps' light
// (baked with the environment multiplier at 0 — see LampLightmapBaker). The sky / sun indirect keeps
// coming from the APV above, which follows the day-night cycle; lightmaps can't. LampLightmapSync
// scales the baked lamp light by the lamps' live day-curve factor and nudges it towards their
// current colour, so a dimmed or recoloured lamp dims / recolours its own bounce too.
// Both globals read 0 when nothing sets them → lightmap at full strength, baked colour.
float _PurrLampLightmapDim;       // 0 = full, 1 = off
float3 _PurrLampLightmapTint;     // added to white; 0 = the colour it was baked with

// A lit shader wanting lightmaps needs, in its forward pass:
//      #pragma multi_compile _ LIGHTMAP_ON
//      #pragma multi_compile _ DIRLIGHTMAP_COMBINED
// a TEXCOORD1 lightmap UV transformed by unity_LightmapST in the vertex stage, and a Meta pass.
half3 PurrLampLightmap(float2 lightmapUV, half3 normalWS)
{
#if defined(LIGHTMAP_ON)
    return SampleLightmap(lightmapUV, normalWS) * (1.0 - _PurrLampLightmapDim) * (1.0 + _PurrLampLightmapTint);
#else
    return 0;
#endif
}

// Everything baked a surface gets: sky/sun from the probes + lamp light from its lightmap.
half3 PurrBakedGI(float2 lightmapUV, float3 positionWS, half3 normalWS, float4 positionCS)
{
    return PurrProbeGI(positionWS, normalWS, positionCS) + PurrLampLightmap(lightmapUV, normalWS);
}

#if defined(LIGHTMAP_ON)
    #define PURR_SAMPLE_GI(lightmapUV, vertexSH, positionWS, normalWS, positionCS) PurrBakedGI(lightmapUV, positionWS, normalWS, positionCS)
#elif defined(PROBE_VOLUMES_L1) || defined(PROBE_VOLUMES_L2)
    #define PURR_SAMPLE_GI(lightmapUV, vertexSH, positionWS, normalWS, positionCS) PurrProbeGI(positionWS, normalWS, positionCS)
#else
    #define PURR_SAMPLE_GI(lightmapUV, vertexSH, positionWS, normalWS, positionCS) SAMPLE_GI(lightmapUV, vertexSH, normalWS)
#endif

#endif // PURR_GI_INCLUDED
