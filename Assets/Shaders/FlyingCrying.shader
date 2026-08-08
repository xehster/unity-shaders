Shader "Custom/Flying Crying"
{
    // A surface covered in eyes that blink on their own and follow something.
    //
    // Named after a monster from KOTEK, my first game, where it was hand drawn in 2D and
    // went by the working name flyingcrying, because it flew and it cried.
    //
    // The eyes are laid out on the same geodesic cells as Custom/Force Field: every cell
    // gets one eye, the spacing is even everywhere and there is no seam to hide. Each eye
    // draws from one packed texture, baked by Shader Gallery > Bake Eye Mask:
    //
    //   R  how far open the lid must be before this pixel shows
    //   G  the eye white
    //   B  the pupil, read again at a shifted uv so it can look around
    Properties
    {
        [NoScaleOffset] _EyeMask ("Eye Mask (RGB packed)", 2D) = "black" {}

        _SkinColor ("Skin", Color) = (0.03, 0.03, 0.04, 1)
        _ScleraColor ("Eye White", Color) = (0.95, 0.95, 0.93, 1)
        _PupilColor ("Pupil", Color) = (1.0, 0.02, 0.55, 1)

        _Density ("Eyes", Range(1, 8)) = 3
        _EyeSize ("Eye Size", Range(0.2, 2)) = 1.15

        _BlinkRate ("Blinks Per Second", Range(0, 3)) = 0.4
        _BlinkLength ("Blink Length", Range(0.02, 0.5)) = 0.12
        _Sync ("Blink Sync", Range(0, 1)) = 0

        _Tracking ("Pupil Tracking", Range(0, 1)) = 1
        _PupilRange ("Pupil Range", Range(0, 0.5)) = 0.14
        // xyz is the point to watch, w at 0 means watch the camera instead
        _LookAt ("Look At", Vector) = (0, 0, 0, 0)

        _Shading ("Shading", Range(0, 1)) = 0.55
        _Ambient ("Ambient", Range(0, 1)) = 0.35
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "Queue"="Geometry" "RenderPipeline"="UniversalPipeline" }

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

        CBUFFER_START(UnityPerMaterial)
            half4 _SkinColor;
            half4 _ScleraColor;
            half4 _PupilColor;
            float _Density;
            float _EyeSize;
            float _BlinkRate;
            float _BlinkLength;
            float _Sync;
            float _Tracking;
            float _PupilRange;
            float4 _LookAt;
            float _Shading;
            float _Ambient;
        CBUFFER_END

        #define PHI 1.6180340
        #define ICO_NORM 0.5257311   // 1 / sqrt(1 + PHI * PHI)
        #define ICO_EDGE 1.0514622   // edge length at circumradius 1
        ENDHLSL

        Pass
        {
            Name "Eyes"
            Tags { "LightMode"="UniversalForward" }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            TEXTURE2D(_EyeMask);
            SAMPLER(sampler_EyeMask);

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 positionOS : TEXCOORD0;
                float3 normalWS   : TEXCOORD1;
            };

            Varyings vert (Attributes IN)
            {
                Varyings OUT;
                OUT.positionCS = GetVertexPositionInputs(IN.positionOS.xyz).positionCS;
                OUT.positionOS = IN.positionOS.xyz;
                OUT.normalWS = GetVertexNormalInputs(IN.normalOS).normalWS;
                return OUT;
            }

            float3 IcoVertex (int v)
            {
                float a = (v & 1) ? 1.0 : -1.0;
                float b = (v & 2) ? PHI : -PHI;
                int axis = v >> 2;
                float3 p = axis == 0 ? float3(0, a, b)
                         : axis == 1 ? float3(a, b, 0)
                                     : float3(b, 0, a);
                return p * ICO_NORM;
            }

            // The centre of the cell this direction belongs to. Same subdivided
            // icosahedron the shield uses: the three nearest corners span the face, the
            // lattice inside it holds the centres, and neighbouring faces agree along
            // their shared edge because the points there come from the same two corners.
            float3 NearestCell (float3 dir, float density)
            {
                float3 a = 0, b = 0, c = 0;
                float ka = -2, kb = -2, kc = -2;

                [unroll]
                for (int v = 0; v < 12; v++)
                {
                    float3 p = IcoVertex(v);
                    float t = dot(p, dir);
                    if (t > ka)      { kc = kb; c = b; kb = ka; b = a; ka = t; a = p; }
                    else if (t > kb) { kc = kb; c = b; kb = t; b = p; }
                    else if (t > kc) { kc = t; c = p; }
                }

                float3 bary = float3(dot(dir, cross(b, c)),
                                     dot(dir, cross(c, a)),
                                     dot(dir, cross(a, b)));
                bary /= bary.x + bary.y + bary.z;

                float3 lattice = bary * density;
                int i0 = (int)round(lattice.x);
                int j0 = (int)round(lattice.y);

                float best = 8.0;
                float3 centre = dir;

                [unroll]
                for (int s = 0; s < 25; s++)
                {
                    int i = i0 + (s % 5) - 2;
                    int j = j0 + (s / 5) - 2;
                    int k = (int)density - i - j;
                    if (i < 0 || j < 0 || k < 0) continue;

                    float3 q = normalize(i * a + j * b + k * c);
                    float d = dot(q - dir, q - dir);
                    if (d < best) { best = d; centre = q; }
                }

                return centre;
            }

            // A number that belongs to this cell. Deliberately smooth in the direction it
            // is given rather than a hash: an eye on a shared edge is reached from two
            // faces whose centres agree only to within float error, and a hash would turn
            // that error into two halves blinking out of step.
            float CellSeed (float3 centre)
            {
                return frac(dot(centre, float3(17.13, 31.07, 11.71)) * 4.0 + 0.37);
            }

            half4 frag (Varyings IN) : SV_Target
            {
                float3 dir = normalize(IN.positionOS);
                float density = floor(_Density);

                float3 centre = NearestCell(dir, density);
                float seed = CellSeed(centre);

                // Upright relative to the object, so the eyes all sit the same way up.
                // Straight above the poles that projection collapses, hence the swap.
                float3 up = abs(centre.y) > 0.99 ? float3(0, 0, 1) : float3(0, 1, 0);
                float3 tx = normalize(cross(up, centre));
                float3 ty = cross(centre, tx);

                float spacing = ICO_EDGE / density * _EyeSize;
                float3 rel = dir - centre;
                float2 uv = float2(dot(rel, tx), dot(rel, ty)) / spacing + 0.5;

                // The uv jumps at every cell border, so the automatic derivatives blow up
                // there and pick a garbage mip, which shows as a blurred ring around each
                // eye. Inside a cell the uv is a plain linear function of the direction,
                // so run the direction's own derivatives through the same frame instead.
                float3 ddirx = ddx(dir);
                float3 ddiry = ddy(dir);
                float2 duvx = float2(dot(ddirx, tx), dot(ddirx, ty)) / spacing;
                float2 duvy = float2(dot(ddiry, tx), dot(ddiry, ty)) / spacing;

                half3 skin = _SkinColor.rgb;

                if (any(uv < 0.0) || any(uv > 1.0))
                {
                    // between the eyes there is only skin
                    Light bare = GetMainLight();
                    float bareLambert = saturate(dot(normalize(IN.normalWS), bare.direction));
                    return half4(skin * lerp(1.0, lerp(_Ambient, 1.0, bareLambert), _Shading), 1);
                }

                // Its own rhythm, unless Sync pulls every eye onto the same clock.
                float rate = _BlinkRate * lerp(0.6 + seed * 0.8, 1.0, _Sync);
                float phase = lerp(seed * 7.0, 0.0, _Sync);
                float cycle = frac(_Time.y * rate + phase);
                float shut = cycle < _BlinkLength ? sin(cycle / _BlinkLength * PI) : 0.0;
                float openness = 1.0 - shut;

                // Where the pupil looks. Straight at the camera unless a point is given.
                float3 target = _LookAt.w > 0.5 ? _LookAt.xyz : _WorldSpaceCameraPos;
                float3 toTarget = normalize(TransformWorldToObject(target) - centre * 0.5);
                float2 aim = float2(dot(toTarget, tx), dot(toTarget, ty));
                // clamped, so an eye facing away strains to its limit instead of wrapping
                float reach = length(aim);
                if (reach > 1.0) aim /= reach;
                float2 pupilUV = uv - aim * _PupilRange * _Tracking;

                half3 mask = SAMPLE_TEXTURE2D_GRAD(_EyeMask, sampler_EyeMask, uv, duvx, duvy).rgb;
                float openAt = mask.r;
                float white = mask.g;
                float pupil = SAMPLE_TEXTURE2D_GRAD(_EyeMask, sampler_EyeMask, pupilUV, duvx, duvy).b;

                float lid = smoothstep(openAt, openAt + 0.02, openness);
                float eye = white * lid;

                half3 iris = lerp(_ScleraColor.rgb, _PupilColor.rgb, saturate(pupil));
                half3 col = lerp(skin, iris, eye);

                Light main = GetMainLight();
                float lambert = saturate(dot(normalize(IN.normalWS), main.direction));
                col *= lerp(1.0, lerp(_Ambient, 1.0, lambert), _Shading);

                return half4(col, 1);
            }
            ENDHLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode"="ShadowCaster" }
            ZWrite On
            ColorMask 0

            HLSLPROGRAM
            #pragma vertex ShadowVert
            #pragma fragment ShadowFrag
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

            float3 _LightDirection;
            float3 _LightPosition;

            float4 ShadowVert (float4 positionOS : POSITION, float3 normalOS : NORMAL) : SV_POSITION
            {
                float3 positionWS = TransformObjectToWorld(positionOS.xyz);
                float3 normalWS = TransformObjectToWorldNormal(normalOS);

                #if _CASTING_PUNCTUAL_LIGHT_SHADOW
                    float3 toLight = normalize(_LightPosition - positionWS);
                #else
                    float3 toLight = _LightDirection;
                #endif

                float4 positionCS = TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, toLight));
                #if UNITY_REVERSED_Z
                    positionCS.z = min(positionCS.z, UNITY_NEAR_CLIP_VALUE);
                #else
                    positionCS.z = max(positionCS.z, UNITY_NEAR_CLIP_VALUE);
                #endif
                return positionCS;
            }

            half4 ShadowFrag () : SV_Target { return 0; }
            ENDHLSL
        }

        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode"="DepthOnly" }
            ZWrite On
            ColorMask 0

            HLSLPROGRAM
            #pragma vertex DepthVert
            #pragma fragment DepthFrag

            float4 DepthVert (float4 positionOS : POSITION) : SV_POSITION
            {
                return TransformObjectToHClip(positionOS.xyz);
            }

            half4 DepthFrag () : SV_Target { return 0; }
            ENDHLSL
        }

        Pass
        {
            Name "DepthNormals"
            Tags { "LightMode"="DepthNormals" }
            ZWrite On

            HLSLPROGRAM
            #pragma vertex NormalsVert
            #pragma fragment NormalsFrag

            struct NormalsVaryings
            {
                float4 positionCS : SV_POSITION;
                float3 normalWS   : TEXCOORD0;
            };

            NormalsVaryings NormalsVert (float4 positionOS : POSITION, float3 normalOS : NORMAL)
            {
                NormalsVaryings OUT;
                OUT.positionCS = TransformObjectToHClip(positionOS.xyz);
                OUT.normalWS = TransformObjectToWorldNormal(normalOS);
                return OUT;
            }

            half4 NormalsFrag (NormalsVaryings IN) : SV_Target
            {
                return half4(normalize(IN.normalWS) * 0.5 + 0.5, 0);
            }
            ENDHLSL
        }
    }
}
