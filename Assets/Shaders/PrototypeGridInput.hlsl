#ifndef PURRFIELD_PROTOTYPE_GRID_INPUT_INCLUDED
#define PURRFIELD_PROTOTYPE_GRID_INPUT_INCLUDED

// Shared by every pass of PrototypeGrid.shader. Kept in one file for the same reason
// ConcreteTriplanarInput.hlsl is: the depth and shadow passes have to snap vertices exactly the
// way the lit pass does, or the object's depth and its shading disagree by a pixel and the edges
// crawl.

CBUFFER_START(UnityPerMaterial)
    float  _CellSize;
    float  _MajorEvery;
    float  _FineDivisions;
    float  _LineWidth;
    float  _MajorWidth;
    float  _FineWidth;
    float4 _BaseColor;
    float4 _LineColor;
    float4 _MajorColor;
    float4 _FineColor;
    float  _Smoothness;
    float  _Metallic;
    float  _Sharpness;
    float  _VertexSnapPixels;
CBUFFER_END

/// The transform's own scale, read back out of the object-to-world matrix: the length of each of
/// its basis vectors is how far one unit of object space travels in the world along that axis.
/// Rotation does not change a basis vector's length, so this survives any rotation.
float3 ObjectScale()
{
    float4x4 m = GetObjectToWorldMatrix();
    return float3(length(float3(m._m00, m._m10, m._m20)),
                  length(float3(m._m01, m._m11, m._m21)),
                  length(float3(m._m02, m._m12, m._m22)));
}

/// Where cell zero sits, in world space.
///
/// Without this the grid is anchored to the world origin, so where a cell boundary lands on a given
/// object is an accident of where that object happens to stand - the lines almost never agree with
/// its edges, and reading a size off it means eyeballing two partial cells at the ends.
///
/// Corner anchors to the renderer's world bounding box minimum, which for the axis-aligned boxes a
/// blockout is made of IS the object's lowest corner: three of its faces then land exactly on
/// lines, and whatever is left over at the far end is the fractional part of its size, which is the
/// number you actually want to see. `unity_RendererBounds_Min` is a built-in per-draw value, so
/// this costs nothing and needs no script feeding the material anything.
///
/// Note it is an AXIS-ALIGNED box: on a rotated object its corner is not the mesh's corner, and
/// Pivot is the honest choice there.
float3 GridAnchorWS()
{
    #if defined(_ANCHOR_CORNER)
        return unity_RendererBounds_Min.xyz;
    #elif defined(_ANCHOR_PIVOT)
        return GetObjectToWorldMatrix()._m03_m13_m23;
    #else
        return float3(0.0, 0.0, 0.0);
    #endif
}

/// The project's PS1 vertex snap, same maths as the other materials so a blockout piece jitters
/// in step with the world around it rather than sliding smoothly through jittering geometry.
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

#endif
