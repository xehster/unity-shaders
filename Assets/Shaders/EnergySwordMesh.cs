namespace Purrfield {

using System.Collections.Generic;
using UnityEngine;

/// <summary>
/// The energy sword's cross (EnergySword_Plan.md) built in code: grip, cross-guard and a tapering blade, three boxes
/// with the uv layout the EnergyBlade shader reveals in stages (uv = across −1..1 / along 0..1 inside the part;
/// uv2 = part id 0 grip, 1 guard, 2 blade / position along the whole cross from the pommel). Origin = the right fist
/// on the grip, +Y up the blade, X across its flat, Z its thickness.
/// </summary>
public static class EnergySwordMesh
{
    public const float GuardOffset = 0.06f;

    public static Mesh Build(float grip, float guardWidth, float blade, float bladeWidth, float thickness)
    {
        var v = new List<Vector3>(); var n = new List<Vector3>(); var uv = new List<Vector2>(); var uv2 = new List<Vector2>(); var tri = new List<int>();
        float bottom = GuardOffset - grip, top = GuardOffset + blade, total = top - bottom;
        float gripW = thickness * 1.6f, guardH = thickness * 2.2f;

        // grip: along = up the grip
        Box(v, n, uv, uv2, tri, 0, new Vector3(0, (bottom + GuardOffset) * 0.5f, 0), new Vector3(gripW, grip, gripW), 1f, bottom, total);
        // guard: along = up its height; across = sideways (the shader opens it from the centre by |across|)
        Box(v, n, uv, uv2, tri, 1, new Vector3(0, GuardOffset, 0), new Vector3(guardWidth, guardH, thickness * 1.4f), 1f, bottom, total);
        // blade: from the guard to a point
        Box(v, n, uv, uv2, tri, 2, new Vector3(0, GuardOffset + blade * 0.5f, 0), new Vector3(bladeWidth, blade, thickness), 0.05f, bottom, total);

        var m = new Mesh { name = "EnergySwordCross" };
        m.SetVertices(v); m.SetNormals(n); m.SetUVs(0, uv); m.SetUVs(1, uv2); m.SetTriangles(tri, 0);
        m.RecalculateBounds();
        return m;
    }

    /// <summary>A box centred at <paramref name="c"/> with size <paramref name="s"/>; the top face is scaled across by
    /// <paramref name="topScale"/> (the blade's point). Each face gets its own verts (flat normals).</summary>
    static void Box(List<Vector3> v, List<Vector3> n, List<Vector2> uv, List<Vector2> uv2, List<int> tri, int part,
        Vector3 c, Vector3 s, float topScale, float bottom, float total)
    {
        Vector3 h = s * 0.5f;
        Vector3 P(float x, float y, float z) { float k = y > 0 ? topScale : 1f; return c + new Vector3(x * h.x * k, y * h.y, z * h.z * k); }
        // 8 corners in unit space
        var corners = new[] { new Vector3(-1,-1,-1), new Vector3(1,-1,-1), new Vector3(1,1,-1), new Vector3(-1,1,-1),
                              new Vector3(-1,-1, 1), new Vector3(1,-1, 1), new Vector3(1,1, 1), new Vector3(-1,1, 1) };
        int[][] faces = { new[]{0,3,2,1}, new[]{4,5,6,7}, new[]{0,4,7,3}, new[]{1,2,6,5}, new[]{3,7,6,2}, new[]{0,1,5,4} };
        foreach (var f in faces)
        {
            int start = v.Count;
            var p0 = P(corners[f[0]].x, corners[f[0]].y, corners[f[0]].z);
            var p1 = P(corners[f[1]].x, corners[f[1]].y, corners[f[1]].z);
            var p2 = P(corners[f[2]].x, corners[f[2]].y, corners[f[2]].z);
            var normal = Vector3.Cross(p1 - p0, p2 - p0).normalized;
            for (int k = 0; k < 4; k++)
            {
                var u = corners[f[k]];
                var p = P(u.x, u.y, u.z);
                v.Add(p); n.Add(normal);
                uv.Add(new Vector2(u.x, (u.y + 1f) * 0.5f));                    // across −1..1, along 0..1 in the part
                uv2.Add(new Vector2(part, total > 0f ? (p.y - bottom) / total : 0f));
            }
            tri.Add(start); tri.Add(start + 1); tri.Add(start + 2);
            tri.Add(start); tri.Add(start + 2); tri.Add(start + 3);
        }
    }
}

} // namespace Purrfield
