Shader "Purrfield/UI State Tint (Variant of GradientMap and PaletteSwapUI)"
{
    // Recolours a uGUI graphic by state, for the ability buttons: desaturated and dark while
    // recovering or blocked, LIT while the ability is running.
    //
    // A plain colour tint cannot do this: multiplying an icon by grey keeps its hues, it only makes
    // them muddy. Going properly black-and-white needs the luminance computed per pixel, which is a
    // shader's job. Written for icons that do not exist yet, so it has to work on any artwork.
    //
    // The lit state is a gradient map, not a translucent green disc laid on top (Eva, 2026-09-20).
    // A disc covers the artwork by definition - the more "on" it looks, the less of the icon is
    // left. A gradient map instead drives the pixel's OWN luminance towards a light green: the
    // bright strokes of the icon become the brightest part of the lit button rather than the thing
    // being hidden, and the dark plate takes a wash of the same green so the plate reads as lit too.
    // One knob (_Active) does both ends, so the breathing pulse stays a single number to animate.
    //
    // Everything else about it is Unity's stock UI shader - stencil/mask support included, because
    // dropping that quietly breaks any graphic placed inside a Mask.
    Properties
    {
        [PerRendererData] _MainTex ("Sprite Texture", 2D) = "white" {}
        _Color ("Tint", Color) = (1,1,1,1)

        _Saturation ("Saturation", Range(0, 1)) = 1
        _Brightness ("Brightness", Range(0, 2)) = 1

        _ActiveColor ("Active Lift Colour", Color) = (0.6, 1, 0.35, 1)
        _Active ("Active Lift", Range(0, 1)) = 0
        // 2026-09-22: recolour the black-and-white parts of the artwork from the UI palette
        // (global _UIPaletteRamp, see UIPalette.cs). Coloured parts (chroma) are left alone.
        [ToggleUI] _PaletteMap ("Palette Map", Float) = 0

        // Cuts the graphic to the plate's silhouette. Left as plain white it does nothing, which is
        // what every graphic that is already plate-shaped wants; the icons use it to be cropped to
        // the button instead of being drawn on transparent background (Eva, 2026-09-20). A texture
        // rather than a Mask component on purpose: uGUI masking costs a stencil pass per button and
        // the shape is already a texture this panel generates for the plate itself.
        _ShapeTex ("Shape Mask (alpha)", 2D) = "white" {}

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
                float4 vertex   : SV_POSITION;
                fixed4 color    : COLOR;
                float2 texcoord : TEXCOORD0;
                float4 worldPosition : TEXCOORD1;
                UNITY_VERTEX_OUTPUT_STEREO
            };

            sampler2D _MainTex;
            fixed4 _Color;
            fixed4 _TextureSampleAdd;
            float4 _ClipRect;
            float4 _MainTex_ST;
            float _Saturation;
            float _Brightness;
            fixed4 _ActiveColor;
            float _Active;
            float _PaletteMap;
            sampler2D _ShapeTex;
            sampler2D _UIPaletteRamp;

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
                half4 color = (tex2D(_MainTex, IN.texcoord) + _TextureSampleAdd) * IN.color;

                // Rec. 709 luma - the standard weighting, because the eye is far more sensitive to
                // green than to blue and a flat average turns a green icon into a pale mess.
                half luma = dot(color.rgb, half3(0.2126, 0.7152, 0.0722));

                // Palette: grey pixels take the palette colour for their luminance (ready row, or
                // the lit row as _Active rises). Pixels that carry their own hue (the red / green
                // rings on the coil icons) keep it. Riding _Saturation means a recovering button
                // still goes back to plain black and white.
                if (_PaletteMap > 0.5)
                {
                    half chroma = max(color.r, max(color.g, color.b)) - min(color.r, min(color.g, color.b));
                    half grey = 1 - smoothstep(0.10, 0.28, chroma);
                    // the ramp's stops are laid out on perceived brightness, so index it in gamma
                    half index = luma;
                    #ifndef UNITY_COLORSPACE_GAMMA
                    index = LinearToGammaSpaceExact(luma);
                    #endif
                    half3 ready = tex2D(_UIPaletteRamp, float2(index, 0.25)).rgb;
                    half3 lit = tex2D(_UIPaletteRamp, float2(index, 0.75)).rgb;
                    color.rgb = lerp(color.rgb, lerp(ready, lit, saturate(_Active)), grey * _Saturation);
                    luma = dot(color.rgb, half3(0.2126, 0.7152, 0.0722));
                }

                color.rgb = lerp(half3(luma, luma, luma), color.rgb, _Saturation) * _Brightness;

                // The lit state: a three-part gradient map, all of it riding one knob.
                //
                // The icon is ALREADY roughly this green, so a plain "pull everything towards the
                // colour" does almost nothing to the artwork while it lifts the plate a lot - which
                // is contrast thrown away, the icon drowning in a brighter plate. Hence three
                // separate ends, each doing the thing that part of the image needs:
                //   wash - the dark plate takes a little of the green so it reads as lit;
                //   pull  - midtones move towards it, but only partway;
                //   hot   - a CUBED key, so only the brightest strokes (the drawing itself) get an
                //           overbright core. That is what keeps the icon the brightest thing on a
                //           lit button instead of the first thing to disappear.
                // Clamped at the end: both additive terms plus the breathing pulse overshoot 1.
                if (_Active > 0.0001 && _PaletteMap < 0.5)
                {
                    half key = saturate(luma * 1.2);
                    color.rgb += _ActiveColor.rgb * (0.20 * _Active) * (1 - key);
                    color.rgb = lerp(color.rgb, _ActiveColor.rgb, key * _Active * 0.6);
                    color.rgb += _ActiveColor.rgb * (key * key * key) * _Active * 0.55;
                    color.rgb = saturate(color.rgb);
                }

                // Crop to the plate silhouette. The mask is sampled with the graphic's OWN uv, so
                // it lines up with whatever rect this graphic covers - which is why the icon that
                // uses it is stretched to the full plate rect rather than inset.
                color.a *= tex2D(_ShapeTex, IN.texcoord).a;

                #ifdef UNITY_UI_CLIP_RECT
                color.a *= UnityGet2DClipping(IN.worldPosition.xy, _ClipRect);
                #endif

                #ifdef UNITY_UI_ALPHACLIP
                clip(color.a - 0.001);
                #endif

                return color;
            }
            ENDCG
        }
    }
}
