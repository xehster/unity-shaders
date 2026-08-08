Shader "Custom/Force Field"
{
    // Energy shield: fresnel rim, a honeycomb that drifts, and rings that spread from
    // impact points. Impacts come in through a MaterialPropertyBlock as positions with
    // a birth time, so one material can serve every shield in a scene.
    //
    // The honeycomb is built on the surface instead of being projected onto it, so the
    // cells keep their shape everywhere and there is nothing to blend and no seam. See
    // CellEdge below for how.
    Properties
    {
        [HDR] _Color ("Colour", Color) = (0.20, 0.55, 1.0, 1)
        _Alpha ("Base Opacity", Range(0, 1)) = 0.03
        _FresnelPower ("Fresnel Power", Range(0.5, 8)) = 3
        _FresnelBoost ("Fresnel Boost", Range(0, 4)) = 1.1

        _HexDensity ("Hex Density", Range(1, 8)) = 4
        _HexWidth ("Hex Line Width", Range(0.02, 0.5)) = 0.14
        _HexDrift ("Hex Drift Speed", Range(0, 2)) = 0.12

        _RippleSpeed ("Impact Speed", Range(0.05, 3)) = 0.45
        _RippleWidth ("Impact Width", Range(0.01, 1)) = 0.12
        _RippleLife ("Impact Life", Range(0.1, 5)) = 1.6

        // marker: anything with this property takes hits through _Hits
        [HideInInspector] _AcceptsImpacts ("Accepts Impacts", Float) = 1
    }

    SubShader
    {
        Tags { "RenderType"="Transparent" "Queue"="Transparent" "RenderPipeline"="UniversalPipeline" }

        // premultiplied alpha: straight additive blows out to white over anything
        // bright, and a shield standing in daylight shouldn't turn into a lamp
        Blend One OneMinusSrcAlpha
        ZWrite Off

        HLSLINCLUDE
        #pragma vertex vert
        #pragma fragment frag
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

        CBUFFER_START(UnityPerMaterial)
            half4 _Color;
            float _Alpha;
            float _FresnelPower;
            float _FresnelBoost;
            float _HexDensity;
            float _HexWidth;
            float _HexDrift;
            float _RippleSpeed;
            float _RippleWidth;
            float _RippleLife;
        CBUFFER_END

        // set per renderer: xyz is the hit in object space, w is its age in
        // seconds. C# keeps the age current, because _Time in Edit Mode runs on
        // its own clock and the two would drift apart.
        #define MAX_HITS 4
        float4 _Hits[MAX_HITS];

        #define PHI 1.6180340
        #define ICO_NORM 0.5257311   // 1 / sqrt(1 + PHI * PHI)
        #define ICO_EDGE 1.0514622   // edge length at circumradius 1

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
            float3 viewWS     : TEXCOORD2;
        };

        Varyings vert (Attributes IN)
        {
            Varyings OUT;
            VertexPositionInputs p = GetVertexPositionInputs(IN.positionOS.xyz);
            OUT.positionCS = p.positionCS;
            OUT.positionOS = IN.positionOS.xyz;
            OUT.normalWS = GetVertexNormalInputs(IN.normalOS).normalWS;
            OUT.viewWS = GetWorldSpaceNormalizeViewDir(p.positionWS);
            return OUT;
        }

        // The twelve corners of an icosahedron: (0, +-1, +-PHI) and its two rotations.
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

        float3 SpinY (float3 d, float a)
        {
            float s = sin(a);
            float c = cos(a);
            return float3(c * d.x + s * d.z, d.y, c * d.z - s * d.x);
        }

        // Distance from a surface direction to the nearest cell wall.
        //
        // A sphere cannot be paved with hexagons alone, but a subdivided icosahedron
        // comes as close as geometry allows: every cell is a hexagon except twelve
        // pentagons at the original corners. The cell centres are the subdivision points
        // and the walls are the bisectors between them, so neighbouring faces agree
        // along their shared edge on their own and no seam can appear.
        float CellEdge (float3 dir, float density)
        {
            // The three nearest corners are the ones spanning the face this direction
            // falls in, which saves carrying a face table around.
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

            // Where the direction sits in that face, as a share of each corner. The
            // cross products are the adjugate of the corner matrix, which is all the
            // inverse we need once the three are scaled back to sum to one.
            float3 bary = float3(dot(dir, cross(b, c)),
                                 dot(dir, cross(c, a)),
                                 dot(dir, cross(a, b)));
            bary /= bary.x + bary.y + bary.z;

            // Centres sit on the lattice bary = (i, j, k) / density with i + j + k equal
            // to density, which puts a row of them along every shared edge.
            float3 lattice = bary * density;
            int i0 = (int)round(lattice.x);
            int j0 = (int)round(lattice.y);

            float near1 = 8.0;
            float near2 = 8.0;
            float3 centre1 = 0;
            float3 centre2 = 0;

            [unroll]
            for (int s = 0; s < 25; s++)
            {
                int i = i0 + (s % 5) - 2;
                int j = j0 + (s / 5) - 2;
                int k = (int)density - i - j;
                if (i < 0 || j < 0 || k < 0) continue;

                float3 q = normalize(i * a + j * b + k * c);
                float d = dot(q - dir, q - dir);

                if (d < near1)
                {
                    near2 = near1; centre2 = centre1;
                    near1 = d;     centre1 = q;
                }
                else if (d < near2)
                {
                    near2 = d; centre2 = q;
                }
            }

            // squared distances collapse to the plain distance to the bisector
            return (near2 - near1) / max(2.0 * length(centre2 - centre1), 1e-4);
        }

        float Ripples(float3 positionOS)
        {
            float total = 0;

            for (int i = 0; i < MAX_HITS; i++)
            {
                float age = _Hits[i].w;
                if (age <= 0 || age > _RippleLife) continue;

                float reach = age * _RippleSpeed;
                float band = abs(distance(positionOS, _Hits[i].xyz) - reach);

                // fades as the ring travels, so hits die out instead of hanging around
                float ring = saturate(1.0 - band / _RippleWidth);
                total += ring * ring * saturate(1.0 - age / _RippleLife);
            }

            return total;
        }

        half4 frag (Varyings IN) : SV_Target
        {
            float3 n = normalize(IN.normalWS);
            // abs, or the back faces (normals pointing away) read as pure rim
            // and the shield fills in solid
            float facing = saturate(abs(dot(n, normalize(IN.viewWS))));
            float fresnel = pow(1.0 - facing, _FresnelPower) * _FresnelBoost;

            float density = floor(_HexDensity);
            float3 dir = SpinY(normalize(IN.positionOS), _Time.y * _HexDrift);

            // width follows the cell spacing, so thinning the grid doesn't fatten the lines
            float width = _HexWidth * ICO_EDGE / density;
            float grid = 1.0 - smoothstep(0.0, width, CellEdge(dir, density));

            float glow = _Alpha + fresnel + grid * 0.18 + Ripples(IN.positionOS) * 1.5;
            float coverage = saturate(glow);
            return half4(_Color.rgb * glow, coverage);
        }
        ENDHLSL

        // Two passes instead of Cull Off. With both sides in one pass they come out in
        // mesh order, so the far wall lands on top of the near one at random. Far side
        // first, near side second, and the shield reads as a volume.
        Pass
        {
            Name "ShieldFar"
            Tags { "LightMode"="UniversalForward" }
            Cull Front
            HLSLPROGRAM
            ENDHLSL
        }

        Pass
        {
            Name "ShieldNear"
            Tags { "LightMode"="SRPDefaultUnlit" }
            Cull Back
            HLSLPROGRAM
            ENDHLSL
        }
    }
}
