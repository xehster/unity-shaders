// Full-resolution retro pass: PS1-style color crush (posterize per channel)
// + 4x4 Bayer ordered dithering. Runs as a FullScreenPassRendererFeature after
// post-processing, so the film grade gets crushed too. No downscaling.
Shader "Purrfield/Retro Dither"
{
    Properties
    {
        _ColorLevels ("Color Levels per Channel", Range(4, 64)) = 32
        _DitherStrength ("Dither Strength", Range(0, 2)) = 1
    }

    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" }
        ZWrite Off
        Cull Off
        ZTest Always

        Pass
        {
            Name "RetroDither"

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Color.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"

            float _ColorLevels;
            float _DitherStrength;

            static const float bayer4[16] =
            {
                 0.0,  8.0,  2.0, 10.0,
                12.0,  4.0, 14.0,  6.0,
                 3.0, 11.0,  1.0,  9.0,
                15.0,  7.0, 13.0,  5.0
            };

            half4 frag(Varyings input) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);

                half3 col = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_PointClamp, input.texcoord).rgb;

                // quantize in gamma space so the bands distribute perceptually
                col = LinearToSRGB(saturate(col));

                int2 p = int2(input.positionCS.xy) % 4;
                float threshold = (bayer4[p.y * 4 + p.x] + 0.5) / 16.0 - 0.5; // -0.5 .. 0.5

                float steps = max(_ColorLevels, 2.0) - 1.0;
                col = floor(col * steps + 0.5 + threshold * _DitherStrength) / steps;

                col = SRGBToLinear(saturate(col));
                return half4(col, 1);
            }
            ENDHLSL
        }
    }
}
