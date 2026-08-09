Shader "Custom/Droplets"
{
    // Cartoon droplets that merge into one shape with one shared outline.
    //
    // An outline cannot be drawn per droplet, because merging needs to know about the
    // neighbours and a lone billboard does not. So every droplet instead lays down a soft
    // bump of a field, the bumps add up, and the shape is the line where that sum crosses
    // a threshold. Two droplets near each other grow a neck on their own.
    //
    // The Droplets component projects them to the screen and hands the whole set over in
    // _Drops as (x, y, radius, eye depth), x and y measured in heights so circles stay
    // round. One quad covering their screen bounds does the rest.
    //
    // The same field gives the shading for free: its gradient is a surface direction, and
    // from that come the bulge, the highlight, the rim and the refraction. Turn those to
    // zero and an empty outline is left; turn them up and it is water.
    Properties
    {
        _Threshold ("Merge Threshold", Range(0.05, 2)) = 0.45
        _Profile ("Profile", Range(1.4, 4)) = 2.7

        _OutlineColor ("Outline Colour", Color) = (0.45, 0.80, 1.0, 1)
        _Outline ("Outline Width", Range(0, 10)) = 2.2
        [Toggle] _RelativeOutline ("Outline Follows Distance", Float) = 0

        _FillColor ("Fill Colour", Color) = (0.55, 0.85, 1.0, 1)
        _Fill ("Fill Alpha", Range(0, 1)) = 0.10

        _Bulge ("Bulge", Range(0.05, 4)) = 1.2
        _Refraction ("Refraction", Range(0, 1)) = 0
        _Rim ("Rim", Range(0, 2)) = 0

        _Highlight ("Highlight", Range(0, 4)) = 0
        _HighlightSize ("Highlight Size", Range(0.05, 1)) = 0.3
        _HighlightColor ("Highlight Colour", Color) = (1, 1, 1, 1)

        _DepthBias ("Depth Bias", Range(0, 0.5)) = 0.06
    }

    SubShader
    {
        Tags { "RenderType"="Transparent" "Queue"="Transparent+50" "RenderPipeline"="UniversalPipeline" }

        // premultiplied: the fill can sit at any opacity while the outline stays solid
        Blend One OneMinusSrcAlpha
        ZWrite Off
        ZTest Always
        Cull Off

        Pass
        {
            Name "Droplets"
            Tags { "LightMode"="UniversalForward" }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareOpaqueTexture.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float _Threshold;
                float _Profile;
                half4 _OutlineColor;
                float _Outline;
                float _RelativeOutline;
                half4 _FillColor;
                float _Fill;
                float _Bulge;
                float _Refraction;
                float _Rim;
                float _Highlight;
                float _HighlightSize;
                half4 _HighlightColor;
                float _DepthBias;
            CBUFFER_END

            #define MAX_DROPS 32
            float4 _Drops[MAX_DROPS];     // x, y, radius, eye depth
            float4 _DropAxis[MAX_DROPS];  // stretch direction xy, how much in z
            float _DropCount;

            struct Attributes { float4 positionOS : POSITION; };
            struct Varyings   { float4 positionCS : SV_POSITION; };

            Varyings vert (Attributes IN)
            {
                Varyings OUT;
                OUT.positionCS = TransformObjectToHClip(IN.positionOS.xyz);
                return OUT;
            }

            half4 frag (Varyings IN) : SV_Target
            {
                float2 screen = IN.positionCS.xy / _ScaledScreenParams.xy;
                float aspect = _ScaledScreenParams.x / max(_ScaledScreenParams.y, 1.0);

                // measure everything in screen heights, or the circles come out as ovals
                float2 p = float2(screen.x * aspect, screen.y);

                float field = 0;
                float2 grad = 0;
                float sparkle = 0;
                float depth = 0;
                float thickness = 0;
                float weight = 0;

                int count = (int)_DropCount;
                [loop]
                for (int i = 0; i < count; i++)
                {
                    float4 drop = _Drops[i];
                    float2 offset = p - drop.xy;
                    float inv = 1.0 / max(drop.z, 1e-5);

                    // A rolling droplet is drawn out along its path, so the bump is an
                    // ellipse rather than a circle. Stretching one way and squeezing the
                    // other by the same factor keeps the area, which is what stops a
                    // stretched droplet from also looking like a bigger one.
                    float2 axis = _DropAxis[i].xy;
                    float2 across = float2(-axis.y, axis.x);
                    float stretch = max(_DropAxis[i].z, 0.05);
                    float along = drop.z * stretch;
                    float wide = drop.z / stretch;

                    float2 e = float2(dot(offset, axis) / along, dot(offset, across) / wide);

                    // Profile decides what the bump's outline actually is. At 2 it is an
                    // ellipse, and a long ellipse reads as a circle somebody pulled on.
                    // Above that the sides flatten and the ends tighten into a lozenge,
                    // which is elongated without looking stretched.
                    float n = _Profile;
                    float2 a = abs(e);
                    float m = max(pow(a.x, n) + pow(a.y, n), 1e-6);
                    float reach = pow(m, 2.0 / n);

                    // a smooth bump that reaches exactly one radius and no further, so a
                    // droplet stops costing anything once it is far from the pixel
                    float q = saturate(1.0 - reach);
                    if (q <= 0) continue;

                    field += q * q;

                    float2 slopeE = 2.0 * pow(m, 2.0 / n - 1.0)
                                  * float2(pow(a.x, n - 1.0) * sign(e.x), pow(a.y, n - 1.0) * sign(e.y));
                    grad += -2.0 * q * (slopeE.x / along * axis + slopeE.y / wide * across);

                    depth += drop.w * q * q;
                    thickness += drop.z * q * q;
                    weight += q * q;

                    // Cartoon highlight: its own small bump, offset up and to the left.
                    // It rides each droplet rather than the merged shape, so the bodies
                    // fuse while the specks stay separate, the way they are drawn by hand.
                    float2 spot = offset + float2(0.34, -0.34) * drop.z;
                    float s = saturate(1.0 - dot(spot, spot) * inv * inv / (_HighlightSize * _HighlightSize));
                    sparkle += s * s;
                }

                if (field <= 0.0001) discard;
                depth /= max(weight, 1e-5);
                thickness /= max(weight, 1e-5);

                // Distance to the outline in pixels. The gradient turns the field into a
                // real distance, which keeps the line the same weight everywhere instead
                // of fattening wherever the field happens to be flat.
                float slope = max(length(grad), 1e-5);
                float pixels = (field - _Threshold) / slope * _ScaledScreenParams.y;

                // An outline measured in pixels stays the same weight however far away the
                // droplet is, which is how it is drawn by hand. Tie it to the droplet's
                // own size on screen instead and the line shrinks with it, the way a real
                // rim would. The 0.025 is picked so the two agree at a middling size and
                // only part company as the camera moves.
                float width = _RelativeOutline > 0.5
                    ? _Outline * thickness * _ScaledScreenParams.y * 0.025
                    : _Outline;

                float inside = saturate(pixels + 0.5);
                float edge = 1.0 - saturate((abs(pixels) - width * 0.5) + 0.5);
                if (inside <= 0 && edge <= 0) discard;

                // let the scene in front of the droplets cover them
                float sceneDepth = LinearEyeDepth(SampleSceneDepth(screen), _ZBufferParams);
                if (sceneDepth < depth - _DepthBias) discard;

                // the field's gradient read as a surface: flat when Bulge is low, domed
                // when it is high, which is the whole difference between a disc and a drop
                float3 n = normalize(float3(-grad / slope, _Bulge));

                half3 colour = 0;
                float coverage = 0;

                if (inside > 0)
                {
                    half3 body = _FillColor.rgb;
                    float alpha = _Fill;

                    if (_Refraction > 0)
                    {
                        float2 bent = screen + n.xy * _Refraction * 0.06;
                        body = lerp(body, SampleSceneColor(bent) * _FillColor.rgb, saturate(_Refraction));
                        alpha = max(alpha, _Refraction);
                    }

                    if (_Rim > 0)
                    {
                        // thin where the drop is deep, bright where it thins out to nothing
                        float rim = pow(1.0 - saturate(n.z), 3.0) * _Rim;
                        body += _OutlineColor.rgb * rim;
                        alpha = saturate(alpha + rim * 0.5);
                    }

                    if (_Highlight > 0)
                    {
                        Light main = GetMainLight();
                        float3 h = normalize(main.direction + float3(0, 0, 1));
                        float spec = pow(saturate(dot(n, h)), 24.0);
                        float lit = saturate(spec + saturate(sparkle));
                        body += _HighlightColor.rgb * lit * _Highlight;
                        alpha = saturate(alpha + lit * _Highlight * 0.5);
                    }

                    colour += body * alpha * inside;
                    coverage += alpha * inside;
                }

                // the outline is opaque, so premultiplied means its colour goes in at full
                colour = lerp(colour, _OutlineColor.rgb, edge);
                coverage = lerp(coverage, 1.0, edge);

                return half4(colour, coverage);
            }
            ENDHLSL
        }
    }
}
