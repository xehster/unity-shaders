Shader "Custom/Palette Swap"
{
    // Indexed colour, the way sprites got their team colours before shaders existed.
    // Every pixel is a slot number rather than a colour, and the palette texture holds
    // the colours: one row per palette, one column per slot. Point sample both, look one
    // up with the other, and the whole image recolours by changing a single number.
    //
    // The slot can come from a purpose-made index map or from the brightness of an
    // ordinary texture, which is what lets a plain checker work here.
    Properties
    {
        [NoScaleOffset] _MainTex ("Source", 2D) = "white" {}
        [NoScaleOffset] _Palette ("Palettes", 2D) = "white" {}
        [Toggle] _Indexed ("Source Is An Index Map", Float) = 0

        _PaletteRow ("Palette", Range(0, 1)) = 0
        _PaletteSpeed ("Palette Cycle", Range(0, 4)) = 0

        _ShadeSteps ("Shade Steps", Range(0, 4)) = 2
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "Queue"="Geometry" "RenderPipeline"="UniversalPipeline" }

        Pass
        {
            Name "Palette"
            Tags { "LightMode"="UniversalForward" }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            TEXTURE2D(_MainTex);   SAMPLER(sampler_MainTex);
            TEXTURE2D(_Palette);   SAMPLER(sampler_Palette);

            CBUFFER_START(UnityPerMaterial)
                float4 _Palette_TexelSize;
                float _Indexed;
                float _PaletteRow;
                float _PaletteSpeed;
                float _ShadeSteps;
            CBUFFER_END

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                float2 uv         : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv         : TEXCOORD0;
                float3 normalWS   : TEXCOORD1;
            };

            Varyings vert (Attributes IN)
            {
                Varyings OUT;
                OUT.positionCS = GetVertexPositionInputs(IN.positionOS.xyz).positionCS;
                OUT.uv = IN.uv;
                OUT.normalWS = GetVertexNormalInputs(IN.normalOS).normalWS;
                return OUT;
            }

            half4 frag (Varyings IN) : SV_Target
            {
                // zw of _TexelSize is the size in pixels, so the palette says how many
                // slots and how many palettes it has and nothing needs counting by hand
                float slots = _Palette_TexelSize.z;
                float rows = _Palette_TexelSize.w;

                half3 source = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv).rgb;
                float level = _Indexed > 0.5 ? source.r : Luminance(source);

                // Indexed art shades by walking up the palette, not by darkening the
                // colour, so the light picks a slot too. Leave the steps at zero and the
                // formula collapses to a plain index lookup with nothing added.
                float steps = floor(_ShadeSteps);
                Light main = GetMainLight();
                float lambert = saturate(dot(normalize(IN.normalWS), main.direction));

                float lit = min(floor(lambert * (steps + 1.0)), steps);
                float slot = clamp(floor(level * max(slots - steps, 1.0)) + lit, 0.0, slots - 1.0);

                float row = fmod(_PaletteRow * (rows - 1) + _Time.y * _PaletteSpeed, rows);

                float2 lookup = float2((slot + 0.5) / slots, (floor(row) + 0.5) / rows);
                half3 colour = SAMPLE_TEXTURE2D(_Palette, sampler_Palette, lookup).rgb;

                return half4(colour, 1.0);
            }
            ENDHLSL
        }
    }
}
