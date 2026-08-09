using System.Collections.Generic;
using UnityEngine;

/// <summary>
/// Droplets that run off a surface and merge into one another.
///
/// Not a Unity ParticleSystem. Merging has to be drawn from the whole set at once, so the
/// positions have to come back to the CPU every frame anyway; once they do, a plain list
/// is less machinery than a particle system plus GetParticles plus rewriting every
/// position to keep it stuck to a surface.
///
/// It builds its own camera facing quad, sized to whatever the droplets cover on screen,
/// and hands them to the material. Nothing here touches the render pipeline, so the
/// object works anywhere it is dropped.
/// </summary>
[ExecuteAlways]
public class Droplets : MonoBehaviour
{
    public enum Path
    {
        Fall,    // straight down, for anything
        Surface  // rolls down a sphere first, then lets go at the bottom
    }

    const int MaxDrops = 32; // the shader's array is this long

    [Header("Where they come from")]
    [Tooltip("Points to drip from, in this object's space. Empty means the object itself.")]
    public List<Vector3> sources = new List<Vector3>();

    [Tooltip("Seconds between drips from any one source.")]
    [Min(0.05f)] public float interval = 1.6f;

    [Tooltip("How much that interval wanders, so they do not drip in step.")]
    [Range(0f, 1f)] public float scatter = 0.7f;

    [Header("How they move")]
    public Path path = Path.Surface;

    [Tooltip("The sphere they run down. Leave empty to use this object.")]
    public Transform host;

    [Tooltip("How far a droplet gets before it has shrunk to nothing.")]
    [Min(0.01f)] public float travel = 1.2f;

    [Min(0.01f)] public float speed = 0.6f;

    [Header("How they look")]
    [Min(0.001f)] public float size = 0.09f;

    [Tooltip("Size spread between droplets.")]
    [Range(0f, 1f)] public float sizeScatter = 0.35f;

    [Tooltip("How far a droplet draws out along its path while it is running down.")]
    [Range(1f, 3f)] public float rollStretch = 1.45f;

    [Tooltip("How fast it takes that shape on, and lets it go again in free fall.")]
    [Min(0.1f)] public float stretchEase = 5f;

    [Tooltip("How close two droplets get before they start pulling on each other.")]
    [Range(0.3f, 1.6f)] public float mergeAt = 1.1f;

    [Tooltip("How hard they draw together once they have caught each other.")]
    [Min(0f)] public float mergePull = 2.2f;

    [Header("Gathering")]
    [Tooltip("Seconds a tear waits at its source before it starts running down.")]
    [Min(0f)] public float hold = 1.4f;

    [Tooltip("Sideways scatter at the source, in droplet radii. Small keeps them one pool.")]
    [Range(0f, 2f)] public float spread = 0.7f;

    [Header("Fading out")]
    [Tooltip("Percent of the droplet's life spent collapsing away at the end.")]
    [Range(5f, 50f)] public float collapseAt = 15f;

    [Tooltip("How much is left by the time that collapse starts. 1 means it barely shrank.")]
    [Range(0.3f, 1f)] public float taper = 0.8f;

    public Material material;

    class Drop
    {
        public Vector3 Direction;  // where it sits on the host, as a unit direction
        public Vector3 World;      // used once it has let go and is falling
        public Vector3 Fall;
        public Vector3 Heading;    // which way it is going, in world, for the stretch
        public bool Loose;
        public float Held;         // seconds still to wait at the source
        public float Age;
        public float Life;
        public float Size;
        public float Stretch = 1f;
    }

    readonly List<Drop> _drops = new List<Drop>();
    readonly Vector4[] _packed = new Vector4[MaxDrops];
    readonly Vector4[] _axes = new Vector4[MaxDrops];
    float _nextDrip;
    float _lastTick;

    Transform _screen;
    MeshRenderer _renderer;
    Mesh _quad;
    MaterialPropertyBlock _block;

    Transform Host { get { return host != null ? host : transform; } }

    float HostRadius
    {
        get
        {
            var s = Host.lossyScale;
            return Mathf.Max(s.x, Mathf.Max(s.y, s.z)) * 0.5f;
        }
    }

    void OnEnable()
    {
        _lastTick = Now;
#if UNITY_EDITOR
        UnityEditor.EditorApplication.update += EditorTick;
#endif
    }

    void OnDisable()
    {
#if UNITY_EDITOR
        UnityEditor.EditorApplication.update -= EditorTick;
#endif
        if (_renderer != null) _renderer.enabled = false;
    }

    static float Now
    {
        get
        {
#if UNITY_EDITOR
            if (!Application.isPlaying) return (float)UnityEditor.EditorApplication.timeSinceStartup;
#endif
            return Time.time;
        }
    }

#if UNITY_EDITOR
    void EditorTick()
    {
        if (Application.isPlaying || this == null) return;
        Tick();
    }
#endif

    void LateUpdate()
    {
        if (Application.isPlaying) Tick();
    }

    void Tick()
    {
        float now = Now;
        float dt = Mathf.Clamp(now - _lastTick, 0f, 0.1f);
        _lastTick = now;
        Step(dt);
        Draw();
    }

    /// <summary>Advance by dt. Public so a recorder can drive it instead of the clock.</summary>
    public void Step(float dt)
    {
        float life = Mathf.Max(travel / Mathf.Max(speed, 0.01f), 0.05f);

        _nextDrip -= dt;
        if (_nextDrip <= 0f)
        {
            Spawn(life);
            float wander = interval * scatter;
            _nextDrip = Mathf.Max(0.02f, interval + Random.Range(-wander, wander)) / Mathf.Max(SourceCount, 1);
        }

        float radius = HostRadius;

        for (int i = _drops.Count - 1; i >= 0; i--)
        {
            var d = _drops[i];

            // Waiting at the source. The clock on its life has not started, so a long
            // gather does not eat into how far it gets to run afterwards.
            if (d.Held > 0f)
            {
                d.Held -= dt;
                d.Stretch = Mathf.Lerp(d.Stretch, 1f, 1f - Mathf.Exp(-stretchEase * dt));
                continue;
            }

            d.Age += dt;
            if (d.Age >= d.Life) { _drops.RemoveAt(i); continue; }

            if (d.Loose)
            {
                d.Fall += Physics.gravity * dt;
                d.World += d.Fall * dt;
                // nothing is dragging on it any more, so it pulls back into a ball
                d.Stretch = Mathf.Lerp(d.Stretch, 1f, 1f - Mathf.Exp(-stretchEase * dt));
                continue;
            }

            // Steepest descent on a sphere is the part of world down that lies along the
            // surface. Near the bottom that part vanishes, which is both a singularity and
            // the moment a real drop would let go, so it lets go.
            Vector3 down = Vector3.down;
            Vector3 outward = Host.TransformDirection(d.Direction).normalized;
            Vector3 along = down - outward * Vector3.Dot(down, outward);

            if (along.sqrMagnitude < 1e-4f)
            {
                d.Loose = true;
                d.World = Host.position + outward * radius;
                d.Fall = Vector3.down * speed;
                continue;
            }

            float radians = speed * dt / Mathf.Max(radius, 0.01f);
            Vector3 moved = Vector3.RotateTowards(outward, along.normalized, radians, 0f);
            d.Direction = Host.InverseTransformDirection(moved).normalized;

            d.Heading = along.normalized;
            d.Stretch = Mathf.Lerp(d.Stretch, rollStretch, 1f - Mathf.Exp(-stretchEase * dt));
        }

        Coalesce(dt);
    }

    /// <summary>
    /// Bring droplets that have caught each other together, and only make them one once
    /// they are all but on top of one another.
    ///
    /// Swapping two touching droplets for a single bigger one straight away is a visible
    /// jolt: the pair is a peanut one frame and a circle the next. So they cling first
    /// and slide into each other over a moment, and the swap happens when the two shapes
    /// are already the same shape. Two droplets sitting on the same spot and one droplet
    /// of the combined volume cross the threshold at nearly the same radius, so nothing
    /// changes on screen at the instant they become one.
    /// </summary>
    void Coalesce(float dt)
    {
        float radius = HostRadius;

        for (int i = 0; i < _drops.Count; i++)
            for (int j = _drops.Count - 1; j > i; j--)
            {
                Drop a = _drops[i];
                Drop b = _drops[j];
                if (a.Loose != b.Loose) continue;

                Vector3 pa = WorldPosition(a);
                Vector3 pb = WorldPosition(b);
                float ra = a.Size * Curve(a);
                float rb = b.Size * Curve(b);
                float reach = (ra + rb) * mergeAt;

                float gap = Vector3.Distance(pa, pb);
                if (gap > reach) continue;

                float va = a.Size * a.Size * a.Size;
                float vb = b.Size * b.Size * b.Size;
                float total = Mathf.Max(va + vb, 1e-6f);

                // near enough to be one shape already: now it is safe to swap them
                if (gap < (ra + rb) * 0.12f)
                {
                    float share = vb / total;
                    a.Size = Mathf.Pow(total, 1f / 3f);
                    a.Age = Mathf.Lerp(a.Age, b.Age, share);
                    a.Life = Mathf.Lerp(a.Life, b.Life, share);
                    a.Held = Mathf.Lerp(a.Held, b.Held, share);
                    a.Direction = Vector3.Slerp(a.Direction, b.Direction, share).normalized;
                    a.World = Vector3.Lerp(a.World, b.World, share);
                    a.Fall = Vector3.Lerp(a.Fall, b.Fall, share);
                    _drops.RemoveAt(j);
                    continue;
                }

                // Closing speed grows as they overlap more, and each is dragged in
                // proportion to how little of the pair it is, so a small tear runs into
                // a big one rather than the two meeting halfway.
                float grip = 1f - gap / Mathf.Max(reach, 1e-5f);
                float closing = mergePull * (ra + rb) * grip * dt;

                Slide(a, pa, pb, closing * (vb / total), radius);
                Slide(b, pb, pa, closing * (va / total), radius);
            }
    }

    /// <summary>Move one droplet the given distance towards a point, along the host.</summary>
    void Slide(Drop d, Vector3 from, Vector3 towards, float distance, float radius)
    {
        if (distance <= 0f) return;

        if (d.Loose)
        {
            Vector3 step = towards - from;
            if (step.sqrMagnitude < 1e-8f) return;
            d.World += step.normalized * distance;
            return;
        }

        Vector3 here = Host.TransformDirection(d.Direction).normalized;
        Vector3 there = (towards - Host.position).normalized;
        Vector3 moved = Vector3.RotateTowards(here, there, distance / Mathf.Max(radius, 0.01f), 0f);
        d.Direction = Host.InverseTransformDirection(moved).normalized;
    }

    int SourceCount { get { return sources.Count > 0 ? sources.Count : 1; } }

    void Spawn(float life)
    {
        if (_drops.Count >= MaxDrops) return;

        Vector3 local = sources.Count > 0 ? sources[Random.Range(0, sources.Count)] : Vector3.up;
        Vector3 dir = local.sqrMagnitude > 1e-6f ? local.normalized : Vector3.up;

        // Nudge sideways so tears gathering at one eye sit next to each other instead of
        // stacking on the same spot. Along the surface, across the way they will run, and
        // small enough that they still read as one pool rather than a row of tears.
        Vector3 outward = Host.TransformDirection(dir).normalized;
        Vector3 downhill = Vector3.down - outward * Vector3.Dot(Vector3.down, outward);
        if (spread > 0f && downhill.sqrMagnitude > 1e-6f)
        {
            Vector3 sideways = Vector3.Cross(outward, downhill.normalized).normalized;
            float step = Random.Range(-spread, spread) * size / Mathf.Max(HostRadius, 0.01f);
            dir = Host.InverseTransformDirection(
                Vector3.RotateTowards(outward, sideways, step, 0f)).normalized;
        }

        _drops.Add(new Drop
        {
            Direction = dir,
            World = Host.TransformPoint(dir),
            Loose = path == Path.Fall,
            Held = path == Path.Fall ? 0f : hold,
            Fall = Vector3.zero,
            Heading = Vector3.down,
            Stretch = 1f,
            Age = 0f,
            Life = life,
            Size = size * (1f + Random.Range(-sizeScatter, sizeScatter))
        });
    }

    Vector3 WorldPosition(Drop d)
    {
        if (d.Loose) return d.World;
        return Host.position + Host.TransformDirection(d.Direction).normalized * HostRadius;
    }

    void Draw()
    {
        var cam = Camera.main;
#if UNITY_EDITOR
        if (cam == null && UnityEditor.SceneView.lastActiveSceneView != null)
            cam = UnityEditor.SceneView.lastActiveSceneView.camera;
#endif
        EnsureScreen();

        if (cam == null || material == null || _drops.Count == 0)
        {
            if (_renderer != null) _renderer.enabled = false;
            return;
        }

        float aspect = cam.aspect;
        int count = 0;
        Vector2 min = new Vector2(float.MaxValue, float.MaxValue);
        Vector2 max = new Vector2(float.MinValue, float.MinValue);

        for (int i = 0; i < _drops.Count && count < MaxDrops; i++)
        {
            var d = _drops[i];
            Vector3 world = WorldPosition(d);
            Vector3 view = cam.WorldToViewportPoint(world);
            if (view.z <= 0f) continue;

            // A droplet on the far side of the host is hidden by the depth test, but at
            // the silhouette the host's depth changes faster than the droplet's, so half
            // of it passes and the other half does not and it gets sliced. Shrink it away
            // as it turns from the camera and it is gone before it reaches that edge.
            float turned = Facing(d, world, cam);
            if (turned <= 0f) continue;

            // radius in the same units the shader works in: fractions of screen height
            Vector3 edge = cam.WorldToViewportPoint(world + cam.transform.up * d.Size * Curve(d) * turned);
            float r = Mathf.Abs(edge.y - view.y);
            if (r < 1e-5f) continue;

            // the stretch axis has to reach the shader in screen terms, so the heading
            // gets projected the same way the position did
            Vector3 tip = cam.WorldToViewportPoint(world + d.Heading * d.Size);
            Vector2 axis = new Vector2((tip.x - view.x) * aspect, tip.y - view.y);
            axis = axis.sqrMagnitude > 1e-10f ? axis.normalized : Vector2.up;

            _packed[count] = new Vector4(view.x * aspect, view.y, r, view.z);
            _axes[count] = new Vector4(axis.x, axis.y, Mathf.Max(d.Stretch, 0.05f), 0f);

            float span = r * Mathf.Max(d.Stretch, 1f / Mathf.Max(d.Stretch, 0.05f));
            min = Vector2.Min(min, new Vector2(view.x - span / aspect, view.y - span));
            max = Vector2.Max(max, new Vector2(view.x + span / aspect, view.y + span));
            count++;
        }

        if (count == 0)
        {
            _renderer.enabled = false;
            return;
        }

        // a little slack so the outline is not clipped by the edge of the quad
        min -= Vector2.one * 0.02f;
        max += Vector2.one * 0.02f;

        FitQuad(cam, min, max);

        _renderer.enabled = true;
        if (_block == null) _block = new MaterialPropertyBlock();
        _renderer.GetPropertyBlock(_block);
        _block.SetVectorArray("_Drops", _packed);
        _block.SetVectorArray("_DropAxis", _axes);
        _block.SetFloat("_DropCount", count);
        _renderer.SetPropertyBlock(_block);
    }

    /// <summary>1 while the droplet faces the camera, easing to 0 as it turns away.</summary>
    float Facing(Drop d, Vector3 world, Camera cam)
    {
        if (d.Loose) return 1f;
        Vector3 outward = Host.TransformDirection(d.Direction).normalized;
        Vector3 toCamera = (cam.transform.position - world).normalized;
        return Mathf.SmoothStep(0f, 1f, Mathf.InverseLerp(0.05f, 0.4f, Vector3.Dot(outward, toCamera)));
    }

    /// <summary>
    /// How much of its size a droplet still has. It barely changes for most of the run
    /// and then goes at the end, because a tear that shrinks evenly the whole way reads
    /// as slowly evaporating rather than as running out.
    /// </summary>
    float Curve(Drop d)
    {
        float t = Mathf.Clamp01(d.Age / Mathf.Max(d.Life, 0.01f));
        float collapse = Mathf.Clamp(collapseAt * 0.01f, 0.02f, 0.9f);
        float knee = 1f - collapse;

        if (t <= knee) return Mathf.Lerp(1f, taper, t / Mathf.Max(knee, 1e-4f));

        // squared, so the collapse is unhurried where it starts and quickest right at
        // the end instead of dropping off a cliff the moment the knee is passed
        float u = (t - knee) / collapse;
        return taper * Mathf.Max(0f, 1f - u * u);
    }

    /// <summary>Park a quad in front of the camera covering the given viewport rectangle.</summary>
    void FitQuad(Camera cam, Vector2 min, Vector2 max)
    {
        float depth = cam.nearClipPlane + 0.05f;
        Vector3 a = cam.ViewportToWorldPoint(new Vector3(min.x, min.y, depth));
        Vector3 b = cam.ViewportToWorldPoint(new Vector3(max.x, min.y, depth));
        Vector3 c = cam.ViewportToWorldPoint(new Vector3(min.x, max.y, depth));

        _screen.position = (a + b + c + (b + c - a)) * 0.25f;
        _screen.rotation = cam.transform.rotation;
        _screen.localScale = new Vector3((b - a).magnitude, (c - a).magnitude, 1f);
    }

    void EnsureScreen()
    {
        if (_screen != null && _renderer != null) return;

        var found = transform.Find("Droplet Screen");
        if (found == null)
        {
            var go = new GameObject("Droplet Screen");
            go.hideFlags = HideFlags.DontSave;
            go.transform.SetParent(transform, false);
            found = go.transform;
        }

        _screen = found;
        var filter = _screen.GetComponent<MeshFilter>();
        if (filter == null) filter = _screen.gameObject.AddComponent<MeshFilter>();
        _renderer = _screen.GetComponent<MeshRenderer>();
        if (_renderer == null) _renderer = _screen.gameObject.AddComponent<MeshRenderer>();

        if (_quad == null)
        {
            _quad = new Mesh { name = "Droplet Quad", hideFlags = HideFlags.DontSave };
            _quad.vertices = new[]
            {
                new Vector3(-0.5f, -0.5f, 0f), new Vector3(0.5f, -0.5f, 0f),
                new Vector3(-0.5f,  0.5f, 0f), new Vector3(0.5f,  0.5f, 0f)
            };
            _quad.triangles = new[] { 0, 2, 1, 2, 3, 1 };
            // never cull it: the quad sits at the near plane and its own bounds mean nothing
            _quad.bounds = new Bounds(Vector3.zero, Vector3.one * 1e5f);
        }

        filter.sharedMesh = _quad;
        _renderer.sharedMaterial = material;
        _renderer.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
        _renderer.receiveShadows = false;
    }
}
