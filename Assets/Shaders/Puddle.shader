Shader "Purrfield/Puddle"
{
    // Flyingcrying's tear puddle as real water (playtest 2026-10-06: the flat blue disc read as one more
    // "get out" circle — the player dodged every circle on the floor). Drawn on the puddle's flat cylinder:
    // object-space xz is the disc (radius 0.5), so no UVs are needed.
    //  • ragged outline — the round disc is cut inward by world-space noise, no crisp edge (a crisp edge is
    //    the strike telegraph's language);
    //  • a wet dark rim fading into the floor, a thin water body inside;
    //  • the sky / reflection probe reflected with Fresnel — tinted and capped, so at a low third-person angle
    //    the puddle stays dark wet water instead of a pale sky-coloured decal (2026-10-06) — the sun glinting
    //    off the ripples;
    //  • ripples from whoever walks in it (ElementalSurfaceView feeds up to 8 sources: world xz, age, strength) —
    //    analytic rings, no render texture, nothing sent over the network;
    //  • _Ripen 0..1: the puddle turning into a bug portal — darkens and swirls.
    Properties
    {
        _WaterColor ("Water (deep)", Color) = (0.05, 0.12, 0.2, 1)
        _ShallowColor ("Water (shallow, at the rim)", Color) = (0.2, 0.4, 0.55, 1)
        _WetColor ("Wet rim (darkens the floor)", Color) = (0.02, 0.03, 0.05, 1)
        _WaterAlpha ("Water Opacity", Range(0, 1)) = 0.85
        _WetAlpha ("Wet Rim Opacity", Range(0, 1)) = 0.45
        _RimWidth ("Wet Rim Width (share of radius)", Range(0, 0.5)) = 0.18
        _EdgeNoiseScale ("Outline Noise Scale (per m)", Range(0.05, 3)) = 0.7
        _EdgeNoise ("Outline Raggedness", Range(0, 0.6)) = 0.3
        _ReflectStrength ("Reflection", Range(0, 2)) = 1
        _ReflectTint ("Reflection Tint (water colours the sky it mirrors)", Color) = (0.5, 0.6, 0.7, 1)
        _ReflectBase ("Reflection Looking Straight Down", Range(0, 1)) = 0.04
        _ReflectMax ("Reflection Cap (grazing)", Range(0, 1)) = 0.45
        _FresnelPower ("Fresnel Power", Range(0.5, 8)) = 4
        _Gloss ("Sun Glint Sharpness", Range(8, 512)) = 180
        _GlintStrength ("Sun Glint", Range(0, 4)) = 1.5
        _RippleSpeed ("Ripple Speed (m/s)", Range(0.2, 4)) = 1.1
        _RippleWavelength ("Ripple Wavelength (m)", Range(0.05, 1)) = 0.22
        _RippleLife ("Ripple Life (s)", Range(0.2, 4)) = 1.6
        _RippleBump ("Ripple Bump", Range(0, 2)) = 0.6
        _IdleBump ("Idle Wobble", Range(0, 0.3)) = 0.04
        [HDR] _PortalColor ("Portal", Color) = (0.12, 0.05, 0.25, 1)
        _Ripen ("Ripen (script)", Range(0, 1)) = 0
        _Charge ("Charge (script)", Range(0, 1)) = 0
    }

    SubShader
    {
        Tags { "RenderType"="Transparent" "Queue"="Transparent-10" "RenderPipeline"="UniversalPipeline" "IgnoreProjector"="True" }

        Pass
        {
            Name "Puddle"
            Tags { "LightMode"="UniversalForward" }
            Blend SrcAlpha OneMinusSrcAlpha
            ZWrite Off
            Cull Back

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile_fog
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include_with_pragmas "Packages/com.unity.render-pipelines.universal/ShaderLibrary/ProbeVolumeVariants.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "PurrGI.hlsl"

            CBUFFER_START(UnityPerMaterial)
                half4 _WaterColor, _ShallowColor, _WetColor;
                half _WaterAlpha, _WetAlpha, _RimWidth;
                half _EdgeNoiseScale, _EdgeNoise;
                half _ReflectStrength, _FresnelPower, _Gloss, _GlintStrength;
                half4 _ReflectTint;
                half _ReflectBase, _ReflectMax;
                half _RippleSpeed, _RippleWavelength, _RippleLife, _RippleBump, _IdleBump;
                half4 _PortalColor;
                half _Ripen, _Charge;
            CBUFFER_END

            #include "SurfaceShape.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 positionWS : TEXCOORD0;
                float2 disc       : TEXCOORD1;   // object xz × 2: -1..1 across the disc
                half   fogCoord   : TEXCOORD2;
            };

            Varyings vert (Attributes IN)
            {
                Varyings OUT;
                VertexPositionInputs p = GetVertexPositionInputs(IN.positionOS.xyz);
                OUT.positionCS = p.positionCS;
                OUT.positionWS = p.positionWS;
                OUT.disc = IN.positionOS.xz * 2.0;
                OUT.fogCoord = ComputeFogFactor(p.positionCS.z);
                return OUT;
            }

            half4 frag (Varyings IN) : SV_Target
            {
                float2 xz = IN.positionWS.xz;

                // portal swirl: twist the sample coordinates, harder towards the centre
                float r0 = length(IN.disc);
                float twist = _Ripen * (1.0 - saturate(r0)) * 6.0 + _Ripen * _Time.y * 2.0;
                float2 cs = float2(cos(twist), sin(twist));
                float2 swirled = float2(IN.disc.x * cs.x - IN.disc.y * cs.y, IN.disc.x * cs.y + IN.disc.y * cs.x);

                // ragged outline: the disc's own edge (r = 1) minus noise, so the cut is always inside the mesh
                float rr, outer;
                float wetMask = SurfaceOutline(IN.disc, xz, _EdgeNoiseScale, _EdgeNoise, rr, outer);
                if (wetMask <= 0.001) discard;
                float inner = outer - _RimWidth;
                float waterMask = 1.0 - smoothstep(inner - 0.06, inner + 0.02, r0);

                // ripple normal from the height field (finite differences, ~2 cm)
                const float e = 0.02;
                float h0 = RippleHeight(xz);
                float hx = RippleHeight(xz + float2(e, 0));
                float hz = RippleHeight(xz + float2(0, e));
                float bump = _RippleBump * waterMask;
                half3 n = normalize(half3(-(hx - h0) / e * bump * 0.05, 1.0, -(hz - h0) / e * bump * 0.05));

                half3 viewDir = GetWorldSpaceNormalizeViewDir(IN.positionWS);
                Light main = GetMainLight(TransformWorldToShadowCoord(IN.positionWS));
                half3 ambient = PurrProbeGI(IN.positionWS, half3(0, 1, 0), IN.positionCS);

                // body: deep in the middle, shallower towards the rim
                half depth = saturate(1.0 - r0 / max(inner, 0.05));
                half3 body = lerp(_ShallowColor.rgb, _WaterColor.rgb, depth);
                body *= ambient + main.color * main.shadowAttenuation * 0.25;

                // reflection: the probe / sky, mostly at grazing angles
                half fresnel = pow(1.0 - saturate(dot(n, viewDir)), _FresnelPower);
                half3 refl = GlossyEnvironmentReflection(reflect(-viewDir, n), 0.05h, 1.0h);
                refl = refl / (1.0h + Luminance(refl));   // the HDR sky probe compressed: a sheen, not a bright mirror
                refl *= _ReflectStrength * _ReflectTint.rgb;

                // the sun glinting off the rings
                half3 hv = normalize(main.direction + viewDir);
                half glint = pow(saturate(dot(n, hv)), _Gloss) * _GlintStrength * main.shadowAttenuation;

                half3 water = lerp(body, refl, min(_ReflectBase + fresnel, _ReflectMax)) + main.color * glint;

                // portal: darkening swirl
                half swirlBands = Noise(swirled * 3.0) * 0.6 + 0.4;
                // fully over the reflection: a ripe portal is a dark hole, not a tinted mirror
                water = lerp(water, _PortalColor.rgb * swirlBands, saturate(_Ripen * 1.15));

                half3 col = lerp(_WetColor.rgb * ambient, water, waterMask);
                half alpha = lerp(_WetAlpha, _WaterAlpha, waterMask) * wetMask;
                // the wet rim fades out into the floor rather than stopping
                alpha *= lerp(smoothstep(outer, inner, r0) * 0.8 + 0.2, 1.0, waterMask);

                // charged: bright veins crawling over the water
                float veinN = Fbm(xz * 1.6 + float2(_Time.y * 1.3, -_Time.y * 0.9));
                half veins = pow(saturate(1.0 - abs(veinN - 0.5) * 10.0), 3.0) * (0.55 + 0.45 * Noise(float2(_Time.y * 18.0, xz.x)));
                col += half3(0.75, 0.6, 1.6) * veins * _Charge * waterMask;
                col = MixFog(col, IN.fogCoord);   // same haze as the floor under it, or the puddle pops out as a decal
                return half4(col, alpha);
            }
            ENDHLSL
        }
    }
}
