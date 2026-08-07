Shader "DIVA/gmap"
{
    // Gradient-map recolour for UGUI Images (task U-082).
    // Luminance -> colour-ramp recolour.
    // Reads the base sprite's luminance and remaps it between a shadow colour and a
    // light colour, so the artist's form shading is preserved but the hue is fully
    // replaced. Much cleaner than a flat multiply tint, especially for deep tones.
    // Based on Unity's built-in UI-Default shader (works for Overlay + Camera canvases).
    Properties
    {
        [PerRendererData] _MainTex ("Sprite Texture", 2D) = "white" {}
        _Color ("Tint", Color) = (1,1,1,1)
        _ShadowColor ("Shadow Colour", Color) = (0.40,0.24,0.18,1)
        _LightColor  ("Light Colour",  Color) = (1.0,0.86,0.74,1)
        _Lo ("Luminance Lo", Range(0,1)) = 0.42
        _Hi ("Luminance Hi", Range(0,1)) = 0.96
        _Strength ("Strength", Range(0,1)) = 1

        // Black-outline preservation: dark + desaturated base pixels stay original.
        _KeepInk ("Keep Outline", Range(0,1)) = 1
        _InkVal  ("Ink Value Threshold", Range(0,1)) = 0.01
        _InkSoft ("Ink Value Softness", Range(0,0.3)) = 0.10
        _InkSat  ("Ink Max Saturation", Range(0,1)) = 0.35

        _StencilComp ("Stencil Comparison", Float) = 8
        _Stencil ("Stencil ID", Float) = 0
        _StencilOp ("Stencil Operation", Float) = 0
        _StencilWriteMask ("Stencil Write Mask", Float) = 255
        _StencilReadMask ("Stencil Read Mask", Float) = 255
        _ColorMask ("Color Mask", Float) = 15
        [Toggle(UNITY_UI_ALPHACLIP)] _UseUIAlphaClip ("Use Alpha Clip", Float) = 0
    }

    SubShader
    {
        Tags
        {
            "Queue"="Transparent"
            "IgnoreProjector"="True"
            "RenderType"="Transparent"
            "PreviewType"="Plane"
            "CanUseSpriteAtlas"="True"
        }

        Stencil
        {
            Ref [_Stencil]
            Comp [_StencilComp]
            Pass [_StencilOp]
            ReadMask [_StencilReadMask]
            WriteMask [_StencilWriteMask]
        }

        Cull Off
        Lighting Off
        ZWrite Off
        ZTest [unity_GUIZTestMode]
        Blend SrcAlpha OneMinusSrcAlpha
        ColorMask [_ColorMask]

        Pass
        {
            Name "Default"
        CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma target 2.0

            #include "UnityCG.cginc"
            #include "UnityUI.cginc"

            #pragma multi_compile_local _ UNITY_UI_CLIP_RECT
            #pragma multi_compile_local _ UNITY_UI_ALPHACLIP

            struct appdata_t
            {
                float4 vertex   : POSITION;
                float4 color    : COLOR;
                float2 texcoord : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct v2f
            {
                float4 vertex        : SV_POSITION;
                fixed4 color         : COLOR;
                float2 texcoord      : TEXCOORD0;
                float4 worldPosition : TEXCOORD1;
                UNITY_VERTEX_OUTPUT_STEREO
            };

            sampler2D _MainTex;
            fixed4 _Color;
            fixed4 _TextureSampleAdd;
            float4 _ClipRect;
            float4 _MainTex_ST;
            fixed4 _ShadowColor;
            fixed4 _LightColor;
            float _Lo;
            float _Hi;
            float _Strength;
            float _KeepInk;
            float _InkVal;
            float _InkSoft;
            float _InkSat;

            v2f vert(appdata_t v)
            {
                v2f OUT;
                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(OUT);
                OUT.worldPosition = v.vertex;
                OUT.vertex = UnityObjectToClipPos(OUT.worldPosition);
                OUT.texcoord = TRANSFORM_TEX(v.texcoord, _MainTex);
                OUT.color = v.color * _Color;
                return OUT;
            }

            fixed4 frag(v2f IN) : SV_Target
            {
                half4 tex = (tex2D(_MainTex, IN.texcoord) + _TextureSampleAdd);

                // Luminance of the base skin pixel, remapped into the ramp range.
                float lum = dot(tex.rgb, float3(0.299, 0.587, 0.114));
                float t = saturate((lum - _Lo) / max(0.0001, (_Hi - _Lo)));
                float3 ramp = lerp(_ShadowColor.rgb, _LightColor.rgb, t);

                // Blend between original and recoloured by strength (1 = full recolour).
                float3 rgb = lerp(tex.rgb, ramp, _Strength);

                // Keep the black ink outline: dark + desaturated base pixels stay original,
                // so the recolour only touches the actual skin. Soft thresholds preserve AA.
                float val = max(tex.r, max(tex.g, tex.b));
                float mn  = min(tex.r, min(tex.g, tex.b));
                float sat = val > 1e-4 ? (val - mn) / val : 0.0;
                float darkMask = 1.0 - smoothstep(_InkVal, _InkVal + _InkSoft, val);
                float satMask  = 1.0 - smoothstep(_InkSat, _InkSat + 0.15, sat);
                float ink = darkMask * satMask * _KeepInk;
                rgb = lerp(rgb, tex.rgb, ink);

                half4 color = half4(rgb, tex.a) * IN.color;

                #ifdef UNITY_UI_CLIP_RECT
                color.a *= UnityGet2DClipping(IN.worldPosition.xy, _ClipRect);
                #endif

                #ifdef UNITY_UI_ALPHACLIP
                clip (color.a - 0.001);
                #endif

                return color;
            }
        ENDCG
        }
    }
}
