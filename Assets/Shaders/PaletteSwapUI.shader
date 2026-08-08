Shader "Custom/Palette Swap (UI)"
{
    // The UI half of Custom/Palette Swap. Same idea, same palette texture, but wearing
    // the scaffolding a UGUI Image expects: stencil block, clip rect, GUI z-test,
    // vertex colours. Built on Unity's UI-Default, like the rest of the UI shaders here.
    //
    // No lighting in a canvas, so there is nothing to shade with. The slot comes from
    // the sprite alone, which is what you want when recolouring flat art anyway.
    Properties
    {
        [PerRendererData] _MainTex ("Sprite Texture", 2D) = "white" {}
        _Color ("Tint", Color) = (1,1,1,1)

        [NoScaleOffset] _Palette ("Palettes", 2D) = "white" {}
        [Toggle] _Indexed ("Source Is An Index Map", Float) = 0

        _PaletteRow ("Palette", Range(0, 1)) = 0
        _PaletteSpeed ("Palette Cycle", Range(0, 4)) = 0

        // which slice of the sprite's brightness gets spread across the palette
        _Lo ("Luminance Lo", Range(0, 1)) = 0
        _Hi ("Luminance Hi", Range(0, 1)) = 1

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
            float4 _MainTex_ST;
            fixed4 _Color;
            fixed4 _TextureSampleAdd;
            float4 _ClipRect;

            sampler2D _Palette;
            float4 _Palette_TexelSize;
            float _Indexed;
            float _PaletteRow;
            float _PaletteSpeed;
            float _Lo;
            float _Hi;

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
                half4 tex = tex2D(_MainTex, IN.texcoord) + _TextureSampleAdd;

                // zw of _TexelSize is the size in pixels, so the palette texture itself
                // says how many slots and how many palettes it holds
                float slots = _Palette_TexelSize.z;
                float rows = _Palette_TexelSize.w;

                float lum = dot(tex.rgb, float3(0.299, 0.587, 0.114));
                float level = _Indexed > 0.5
                    ? tex.r
                    : saturate((lum - _Lo) / max(0.0001, _Hi - _Lo));

                float slot = min(floor(level * slots), slots - 1.0);
                float row = fmod(_PaletteRow * (rows - 1) + _Time.y * _PaletteSpeed, rows);

                float2 lookup = float2((slot + 0.5) / slots, (floor(row) + 0.5) / rows);
                fixed3 rgb = tex2D(_Palette, lookup).rgb;

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
