using System.Collections.Generic;
using UnityEngine;

/// <summary>
/// Fills a Droplets component with one source per eye of Custom/Flying Crying.
///
/// The eyes sit on the same subdivided icosahedron the shader lays them out on, so the
/// centres have to be worked out the same way here: the twelve corners, the twenty faces
/// they form, and the lattice of points inside each face. Points on a shared edge belong
/// to two faces, so the list is de-duplicated at the end.
///
/// Kept apart from Droplets on purpose. Droplets knows nothing about eyes and works on
/// anything; this is the piece that ties it to one particular shader.
/// </summary>
[ExecuteAlways]
[RequireComponent(typeof(Droplets))]
public class EyeSources : MonoBehaviour
{
    [Tooltip("The renderer wearing the eye material. Leave empty to look on this object.")]
    public Renderer eyes;

    [Tooltip("Recount the eyes every frame, in case the density slider is being dragged.")]
    public bool keepInStep = true;

    [Tooltip("How far below the pupil a tear starts, as a share of the eye's own radius.")]
    [Range(0f, 1f)] public float below = 0.55f;

    int _lastDensity = -1;
    float _lastBelow = -1f;

    void OnEnable() { Rebuild(); }
    void OnValidate() { _lastDensity = -1; }

    void LateUpdate()
    {
        if (keepInStep) Rebuild();
    }

    public void Rebuild()
    {
        var target = eyes != null ? eyes : GetComponent<Renderer>();
        if (target == null || target.sharedMaterial == null) return;
        if (!target.sharedMaterial.HasProperty("_Density")) return;

        int density = Mathf.Max(1, Mathf.FloorToInt(target.sharedMaterial.GetFloat("_Density")));
        if (density == _lastDensity && Mathf.Approximately(below, _lastBelow)) return;
        _lastDensity = density;
        _lastBelow = below;

        var centres = CellCentres(density);

        // A tear does not come off the middle of an eye, it gathers on the lower lid, so
        // each source slides down the sphere from the pupil. The cells are about one
        // icosahedron edge apart, which is what sets how far down "the lid" is.
        const float icoEdge = 1.0514622f;
        float step = icoEdge / density * 0.5f * below;

        for (int i = 0; i < centres.Count; i++)
        {
            Vector3 c = centres[i];
            Vector3 downhill = Vector3.down - c * Vector3.Dot(Vector3.down, c);
            if (downhill.sqrMagnitude < 1e-6f) continue; // an eye at the very bottom has no lower
            centres[i] = Vector3.RotateTowards(c, downhill.normalized, step, 0f).normalized;
        }

        var drops = GetComponent<Droplets>();
        drops.sources = centres;
    }

    /// <summary>Every cell centre of an icosahedron subdivided this many times.</summary>
    public static List<Vector3> CellCentres(int density)
    {
        var corners = Corners();
        var centres = new List<Vector3>();
        var seen = new HashSet<Vector3Int>();

        foreach (var face in Faces(corners))
            for (int i = 0; i <= density; i++)
                for (int j = 0; j <= density - i; j++)
                {
                    int k = density - i - j;
                    Vector3 c = (corners[face.x] * i + corners[face.y] * j + corners[face.z] * k).normalized;

                    // an edge point turns up from both faces, and rounding is what makes
                    // the two float-identical answers land in the same bucket
                    var key = new Vector3Int(
                        Mathf.RoundToInt(c.x * 4096f),
                        Mathf.RoundToInt(c.y * 4096f),
                        Mathf.RoundToInt(c.z * 4096f));

                    if (seen.Add(key)) centres.Add(c);
                }

        return centres;
    }

    static Vector3[] Corners()
    {
        const float phi = 1.6180340f;
        var corners = new Vector3[12];
        for (int v = 0; v < 12; v++)
        {
            float a = (v & 1) != 0 ? 1f : -1f;
            float b = (v & 2) != 0 ? phi : -phi;
            int axis = v >> 2;
            Vector3 p = axis == 0 ? new Vector3(0, a, b)
                      : axis == 1 ? new Vector3(a, b, 0)
                                  : new Vector3(b, 0, a);
            corners[v] = p.normalized;
        }
        return corners;
    }

    /// <summary>The twenty faces, found as the triples whose corners are all neighbours.</summary>
    static List<Vector3Int> Faces(Vector3[] corners)
    {
        // on a unit icosahedron every edge is the same length, and it is the shortest
        // distance between any two corners
        float edge = float.MaxValue;
        for (int a = 0; a < 12; a++)
            for (int b = a + 1; b < 12; b++)
                edge = Mathf.Min(edge, Vector3.Distance(corners[a], corners[b]));

        float slack = edge * 1.1f;
        var faces = new List<Vector3Int>();

        for (int a = 0; a < 12; a++)
            for (int b = a + 1; b < 12; b++)
            {
                if (Vector3.Distance(corners[a], corners[b]) > slack) continue;
                for (int c = b + 1; c < 12; c++)
                {
                    if (Vector3.Distance(corners[a], corners[c]) > slack) continue;
                    if (Vector3.Distance(corners[b], corners[c]) > slack) continue;
                    faces.Add(new Vector3Int(a, b, c));
                }
            }

        return faces;
    }
}
