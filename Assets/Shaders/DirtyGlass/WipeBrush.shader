Shader "Hidden/Gallery/WipeBrush"
{
    // The two marks Wipeable makes on its mask. Nothing else uses this.
    Properties
    {
        _Ink ("Ink", Color) = (1, 1, 1, 1)
        _Core ("Core", Range(0, 1)) = 0.35
    }

    SubShader
    {
        Cull Off
        ZWrite Off
        ZTest Always

        Pass
        {
            Name "Brush"
            Blend One One // strokes pile up, and an R8 target caps them at spotless

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            float4 _Ink;
            float _Core;

            struct Attributes { float4 positionOS : POSITION; float2 uv : TEXCOORD0; };
            struct Varyings   { float4 positionCS : SV_POSITION; float2 uv : TEXCOORD0; };

            Varyings vert (Attributes IN)
            {
                Varyings OUT;
                OUT.positionCS = TransformObjectToHClip(IN.positionOS.xyz);
                OUT.uv = IN.uv;
                return OUT;
            }

            half4 frag (Varyings IN) : SV_Target
            {
                float d = length(IN.uv * 2.0 - 1.0);
                float a = 1.0 - smoothstep(_Core, 1.0, d);
                return half4(_Ink.rgb * a, 1.0);
            }
            ENDHLSL
        }

        Pass
        {
            Name "Fade"
            Blend Zero SrcColor // multiplies what is there, which is how the dirt creeps back

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            float4 _Ink;

            struct Attributes { float4 positionOS : POSITION; float2 uv : TEXCOORD0; };
            struct Varyings   { float4 positionCS : SV_POSITION; float2 uv : TEXCOORD0; };

            Varyings vert (Attributes IN)
            {
                Varyings OUT;
                OUT.positionCS = TransformObjectToHClip(IN.positionOS.xyz);
                OUT.uv = IN.uv;
                return OUT;
            }

            half4 frag (Varyings IN) : SV_Target
            {
                return half4(_Ink.rgb, 1.0);
            }
            ENDHLSL
        }
    }
}
