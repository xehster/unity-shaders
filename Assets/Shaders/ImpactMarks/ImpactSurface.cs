using UnityEngine;
#if UNITY_EDITOR
using UnityEditor;
#endif

/// <summary>
/// Feeds hits to Custom/Impact Marks: where they landed, how old they are, and what put
/// them there.
///
/// Hits live in a ring buffer rather than a painted mask, which is what keeps each one
/// alive: it can still be spreading, and it can still be told to retract when its time is
/// up. The cost is a ceiling on how many can be on screen at once. A surface that needs
/// hundreds wants the marks stamped into a mask instead, and then they stop moving.
///
/// The shader reads the array the way ForceField does, so anything already pushing _Hits
/// works without this. What this adds is the second kind of hit, aiming, and ageing.
/// </summary>
[ExecuteAlways]
[AddComponentMenu("Shader Gallery/Impact Surface")]
public class ImpactSurface : MonoBehaviour
{
    public enum Kind { Bullet, Melee }

    /// Has to match MAX_HITS in the shader.
    public const int Slots = 32;

    [Tooltip("Landing on a full surface recycles the oldest mark.")]
    [Range(1, Slots)] public int keep = 16;

    [Header("Firing on its own")]
    [Tooltip("Keep hitting it, so the effect shows without anyone clicking.")]
    public bool autoFire = false;

    [Tooltip("Seconds between hits.")]
    [Range(0.05f, 5f)] public float interval = 0.9f;

    [Tooltip("How often a hit is a swing rather than a round.")]
    [Range(0f, 1f)] public float meleeShare = 0.3f;

    [Header("By hand")]
    [Tooltip("Click to shoot it while the game is running.")]
    public bool fireWithMouse = true;

    [Tooltip("Camera the mouse looks through. Empty means the main one.")]
    public Camera through;

    [Tooltip("Spread in size between one hit and the next.")]
    [Range(0f, 1f)] public float sizeScatter = 0.35f;

    readonly Vector4[] _hits = new Vector4[Slots];
    readonly Vector4[] _style = new Vector4[Slots];
    MaterialPropertyBlock _block;
    int _cursor;
    float _nextShot;
    float _lastTick;

    void OnEnable()
    {
#if UNITY_EDITOR
        EditorApplication.update += EditorTick;
#endif
        Push();
    }

    void OnDisable()
    {
#if UNITY_EDITOR
        EditorApplication.update -= EditorTick;
#endif
    }

    void Update()
    {
        if (!Application.isPlaying) return;

        Step(Time.deltaTime);
        if (fireWithMouse && Input.GetMouseButtonDown(0))
            HitAt(Input.mousePosition, Input.GetKey(KeyCode.LeftShift) ? Kind.Melee : Kind.Bullet);
    }

#if UNITY_EDITOR
    void EditorTick()
    {
        if (Application.isPlaying || this == null) return;

        float now = (float)EditorApplication.timeSinceStartup;
        float dt = Mathf.Clamp(now - _lastTick, 0f, 0.1f);
        _lastTick = now;

        if (!Alive()) return;

        Step(dt);
        SceneView.RepaintAll();
    }

    /// <summary>Nothing is changing, so leave the editor alone.</summary>
    bool Alive()
    {
        if (autoFire) return true;
        for (int i = 0; i < Slots; i++) if (_hits[i].w > 0f) return true;
        return false;
    }
#endif

    public void Step(float dt)
    {
        float life = Life();

        for (int i = 0; i < Slots; i++)
        {
            if (_hits[i].w <= 0f) continue;

            _hits[i].w += dt;
            if (life > 0f && _hits[i].w > life) _hits[i] = Vector4.zero;
        }

        if (autoFire)
        {
            _nextShot -= dt;
            if (_nextShot <= 0f)
            {
                _nextShot = Mathf.Max(0.05f, interval) * Random.Range(0.7f, 1.3f);
                HitSomewhere();
            }
        }

        Push();
    }

    /// <summary>Lifetime as the material has it, so the two can't drift apart.</summary>
    float Life()
    {
        var renderer = GetComponent<Renderer>();
        var mat = renderer != null ? renderer.sharedMaterial : null;
        return mat != null && mat.HasProperty("_Life") ? mat.GetFloat("_Life") : 0f;
    }

    // --- landing a hit -------------------------------------------------------

    /// <summary>Put a mark at a point on the surface, in world space.</summary>
    public void Hit(Vector3 point, Vector3 normal, Kind kind, Vector3 swing)
    {
        Vector3 local = transform.InverseTransformPoint(point);
        Vector3 n = transform.InverseTransformDirection(normal).normalized;

        // Size varies per hit here rather than in the shader, because the shader can only
        // vary it by a hash of the position and two rounds through the same spot would
        // then come out identical.
        float size = 1f + Random.Range(-sizeScatter, sizeScatter);

        _hits[_cursor] = new Vector4(local.x, local.y, local.z, 0.001f);
        _style[_cursor] = new Vector4(kind == Kind.Melee ? 1f : 0f, Mathf.Max(0.05f, size),
            SwingAngle(n, transform.InverseTransformDirection(swing)), 0f);

        _cursor = (_cursor + 1) % Mathf.Clamp(keep, 1, Slots);
        Push();
    }

    /// <summary>Fire at whatever a screen point is pointing at, if it is this object.</summary>
    public bool HitAt(Vector3 screenPoint, Kind kind)
    {
        var cam = through != null ? through : Camera.main;
        if (cam == null) return false;

        return HitAlong(cam.ScreenPointToRay(screenPoint), kind, cam.transform.up);
    }

    public bool HitAlong(Ray ray, Kind kind, Vector3 swing)
    {
        // Whoever moved this object last moved the transform, not the collider, and
        // outside play mode nothing pushes that across on its own. Without this a hit on
        // a turning object lands where the object used to be.
        Physics.SyncTransforms();

        var hits = Physics.RaycastAll(ray, 5000f);
        float best = float.MaxValue;
        bool found = false;
        Vector3 point = Vector3.zero, normal = Vector3.up;

        foreach (var hit in hits)
        {
            if (!hit.collider.transform.IsChildOf(transform)) continue;
            if (hit.distance >= best) continue;

            best = hit.distance;
            point = hit.point;
            normal = hit.normal;
            found = true;
        }

        if (found) Hit(point, normal, kind, swing);
        return found;
    }

    /// <summary>A hit from a random direction, for the ones this fires at itself.</summary>
    public void HitSomewhere()
    {
        var renderer = GetComponent<Renderer>();
        if (renderer == null) return;

        var bounds = renderer.bounds;
        Vector3 from = bounds.center + Random.onUnitSphere * bounds.extents.magnitude * 2f;
        var ray = new Ray(from, (bounds.center - from).normalized);

        Kind kind = Random.value < meleeShare ? Kind.Melee : Kind.Bullet;
        HitAlong(ray, kind, Random.onUnitSphere);
    }

    public void Clear()
    {
        System.Array.Clear(_hits, 0, Slots);
        System.Array.Clear(_style, 0, Slots);
        _cursor = 0;
        Push();
    }

    public int Landed
    {
        get
        {
            int n = 0;
            for (int i = 0; i < Slots; i++) if (_hits[i].w > 0f) n++;
            return n;
        }
    }

    // --- plumbing ------------------------------------------------------------

    void Push()
    {
        var renderer = GetComponent<Renderer>();
        if (renderer == null || renderer.sharedMaterial == null) return;
        if (!renderer.sharedMaterial.HasProperty("_TakesMarks")) return;

        if (_block == null) _block = new MaterialPropertyBlock();
        renderer.GetPropertyBlock(_block);
        _block.SetVectorArray("_Hits", _hits);
        _block.SetVectorArray("_Style", _style);
        renderer.SetPropertyBlock(_block);
    }

    /// <summary>
    /// The swing direction as an angle in the surface frame. The shader builds that frame
    /// per fragment from the same two lines; change one and the other has to follow, or
    /// every swing mark points somewhere else.
    /// </summary>
    static float SwingAngle(Vector3 n, Vector3 swing)
    {
        Vector3 up = Mathf.Abs(n.z) < 0.9f ? new Vector3(0f, 0f, 1f) : new Vector3(1f, 0f, 0f);
        Vector3 t = Vector3.Cross(n, up).normalized;
        Vector3 b = Vector3.Cross(n, t);

        Vector3 flat = swing - n * Vector3.Dot(swing, n);
        if (flat.sqrMagnitude < 1e-6f) return 0f;

        return Mathf.Atan2(Vector3.Dot(flat, b), Vector3.Dot(flat, t));
    }

    public bool Ready
    {
        get
        {
            var renderer = GetComponent<Renderer>();
            return renderer != null && renderer.sharedMaterial != null
                && renderer.sharedMaterial.HasProperty("_TakesMarks");
        }
    }
}
