// Move-mode outline: classic inverted hull - the mesh is redrawn with front
// faces culled and vertices pushed out along their normals, so only a colored
// rim around the silhouette survives the depth test. Purple = movable machine,
// beam-blue = the one under the crosshair (tinted via MPB _Color by
// MachinePlacer). Keeps the PS1 vertex snap so the rim jitters with the mesh.
Shader "Purrfield/MoveOutline"
{
    Properties
    {
        [HDR] _Color ("Color", Color) = (0.9, 0.25, 1.8, 1)
        _OutlineWidth ("Outline Width (m)", Range(0.001, 0.1)) = 0.025
        _VertexSnapPixels ("Vertex Grid Height (0 = off)", Float) = 240
    }

    SubShader
    {
        Tags
        {
            "RenderType" = "Opaque"
            "Queue" = "Geometry+10"
            "RenderPipeline" = "UniversalPipeline"
        }

        Pass
        {
            Name "InvertedHull"
            Cull Front
            ZWrite On
            ZTest LEqual

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            CBUFFER_START(UnityPerMaterial)
                half4 _Color;
                float _OutlineWidth;
                float _VertexSnapPixels;
            CBUFFER_END

            float4 ApplyVertexSnap(float4 positionCS)
            {
                if (_VertexSnapPixels < 1.0)
                    return positionCS;
                float aspect = _ScreenParams.x / max(_ScreenParams.y, 1.0);
                float2 grid = float2(_VertexSnapPixels * aspect, _VertexSnapPixels);
                float2 ndc = positionCS.xy / positionCS.w;
                ndc = floor(ndc * grid * 0.5) / (grid * 0.5) + 1.0 / grid;
                positionCS.xy = ndc * positionCS.w;
                return positionCS;
            }

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
            };

            Varyings vert(Attributes v)
            {
                Varyings o;
                float3 positionWS = TransformObjectToWorld(v.positionOS.xyz);
                float3 normalWS = normalize(TransformObjectToWorldNormal(v.normalOS));
                positionWS += normalWS * _OutlineWidth;
                o.positionCS = ApplyVertexSnap(TransformWorldToHClip(positionWS));
                return o;
            }

            half4 frag(Varyings i) : SV_Target
            {
                return half4(_Color.rgb, 1.0);
            }
            ENDHLSL
        }
    }
}
