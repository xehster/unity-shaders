Shader "Purrfield/FireGround"
{
    // A fire burning on the floor (an ElementalSurface of kind FireGround). Same disc + ragged outline as the
    // puddle (SurfaceShape.hlsl) so the two read as one family; premultiplied glow over a scorched floor,
    // hot in the middle, embers drifting through, cracks flickering. _Plasma / _Flare / _Amount come from ElementalSurfaceView.
    Properties
    {
        [HDR] _HotColor ("Hot", Color) = (3, 1.1, 0.25, 1)
        [HDR] _CoolColor ("Cool (embers at the rim)", Color) = (0.35, 0.05, 0.02, 1)
        [HDR] _PlasmaColor ("Plasma", Color) = (2.4, 0.55, 2.1, 1)
        _EdgeNoiseScale ("Outline Noise Scale (per m)", Range(0.05, 3)) = 0.7
        _EdgeNoise ("Outline Raggedness", Range(0, 0.6)) = 0.3
        _Plasma ("Plasma (script)", Range(0, 1)) = 0
        _Flare ("Flare (script)", Range(0, 1)) = 0
        _Amount ("Amount (script)", Range(0, 1)) = 1
    }

    SubShader
    {
        Tags { "RenderType"="Transparent" "Queue"="Transparent-10" "RenderPipeline"="UniversalPipeline" "IgnoreProjector"="True" }

        Pass
        {
            Name "FireGround"
            Tags { "LightMode"="UniversalForward" }
            Blend One OneMinusSrcAlpha
            ZWrite Off
            Cull Back

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include_with_pragmas "Packages/com.unity.render-pipelines.universal/ShaderLibrary/ProbeVolumeVariants.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "PurrGI.hlsl"

            CBUFFER_START(UnityPerMaterial)
                half4 _HotColor, _CoolColor, _PlasmaColor;
                half _EdgeNoiseScale, _EdgeNoise;
                half _Plasma, _Flare, _Amount;
            CBUFFER_END

            #define SURFACE_SHAPE_NO_RIPPLES
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
            };

            Varyings vert (Attributes IN)
            {
                Varyings OUT;
                VertexPositionInputs p = GetVertexPositionInputs(IN.positionOS.xyz);
                OUT.positionCS = p.positionCS;
                OUT.positionWS = p.positionWS;
                OUT.disc = IN.positionOS.xz * 2.0;
                return OUT;
            }

            half4 frag (Varyings IN) : SV_Target
            {
                float2 xz = IN.positionWS.xz;
                float r, outer;
                float mask = SurfaceOutline(IN.disc, xz, _EdgeNoiseScale, _EdgeNoise, r, outer);
                if (mask <= 0.001) discard;
                float embers = Fbm(xz * 1.7 + float2(0, -_Time.y * 0.8));
                float heat = saturate(1.0 - r / outer) * 0.6 + embers * 0.7;
                // glowing cracks crawling through the embers, flickering
                float crackN = Fbm(xz * 1.1 + float2(_Time.y * 0.15, 0));
                half cracks = pow(saturate(1.0 - abs(crackN - 0.5) * 8.0), 3.0) * (0.7 + 0.3 * Noise(xz * 4.0 + _Time.y * 6.0));
                half3 col = lerp(_CoolColor.rgb, _HotColor.rgb, saturate(heat));
                col = lerp(col, _PlasmaColor.rgb * (0.8 + embers), _Plasma);
                col *= 1.0 + _Flare * 1.5;
                // no crisp edge: glow and scorch both fade out over the outer third of the disc
                half rimFade = smoothstep(outer, outer * 0.6, r);
                half glow = (smoothstep(0.3, 1.0, heat) * 0.8 + cracks * 0.9) * rimFade;
                // premultiplied: rgb adds the glow, alpha darkens the floor under it (scorch)
                half scorch = (0.25 + 0.45 * rimFade) * mask;
                return half4(col * glow * mask * _Amount, scorch * _Amount);
            }
            ENDHLSL
        }
    }
}
