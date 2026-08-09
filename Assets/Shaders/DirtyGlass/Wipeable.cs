using UnityEngine;
#if UNITY_EDITOR
using UnityEditor;
#endif

/// <summary>
/// Keeps the mask that says which parts of a surface have been rubbed clean, and paints
/// into it wherever it is told to.
///
/// The mask is one channel in UV space, black everywhere to start with, meaning nothing
/// has been touched. Custom/Dirty Glass reads it and lifts its dirt where the mask is
/// bright. Nothing here knows what dirt looks like, so any shader with a mask property
/// can be wiped the same way.
///
/// Finding where a click landed needs a MeshCollider, because that is the only collider
/// that can say which UV was hit. One gets added if there isn't one.
/// </summary>
[ExecuteAlways]
[AddComponentMenu("Shader Gallery/Wipeable")]
public class Wipeable : MonoBehaviour
{
    [Tooltip("Shader property the mask is handed to.")]
    public string maskProperty = "_WipeMask";

    [Tooltip("Mask size. 512 is plenty for a hand-sized smear; go up for fine scrubbing.")]
    public int resolution = 512;

    [Header("Brush")]
    [Tooltip("How wide one dab is, as a share of the whole UV sheet.")]
    [Range(0.005f, 0.3f)] public float radius = 0.07f;

    [Tooltip("How much of the dab is wiped right through. The rest is a soft rim.")]
    [Range(0f, 1f)] public float core = 0.3f;

    [Tooltip("How much one dab lifts. Low values mean you have to go over a spot twice.")]
    [Range(0.02f, 1f)] public float strength = 0.35f;

    [Header("Behaviour")]
    [Tooltip("Drag with the left mouse button to wipe while the game is running.")]
    public bool wipeWithMouse = true;

    [Tooltip("Camera the mouse looks through. Empty means the main one.")]
    public Camera through;

    [Tooltip("How fast the dirt creeps back over what was cleaned. 0 leaves it clean.")]
    [Range(0f, 1f)] public float creepBack = 0f;

    RenderTexture _mask;
    Material _brush;
    MaterialPropertyBlock _block;
    float _lastTick;

    public RenderTexture Mask { get { return _mask; } }

    void OnEnable()
    {
        Build();
#if UNITY_EDITOR
        EditorApplication.update += EditorTick;
#endif
    }

    void OnDisable()
    {
#if UNITY_EDITOR
        EditorApplication.update -= EditorTick;
#endif
        Release();
    }

    void OnValidate()
    {
        resolution = Mathf.Clamp(Mathf.ClosestPowerOfTwo(resolution), 64, 2048);
        if (_mask != null && _mask.width != resolution) Build();
    }

    void Update()
    {
        if (!Application.isPlaying) return;

        Creep(Time.deltaTime);
        if (wipeWithMouse && Input.GetMouseButton(0)) WipeAt(Input.mousePosition);
    }

#if UNITY_EDITOR
    void EditorTick()
    {
        if (Application.isPlaying || this == null) return;

        float now = (float)EditorApplication.timeSinceStartup;
        float dt = Mathf.Clamp(now - _lastTick, 0f, 0.1f);
        _lastTick = now;

        if (creepBack > 0f) Creep(dt);
    }
#endif

    // --- the mask ------------------------------------------------------------

    void Build()
    {
        Release();

        // one channel is all a wipe needs, and 0..1 clamping is what stops repeated
        // strokes from running away past spotless
        _mask = new RenderTexture(resolution, resolution, 0, RenderTextureFormat.R8)
        {
            name = name + " wipe mask",
            wrapMode = TextureWrapMode.Repeat,
            filterMode = FilterMode.Bilinear,
            hideFlags = HideFlags.DontSave
        };
        _mask.Create();

        var shader = Shader.Find("Hidden/Gallery/WipeBrush");
        if (shader != null) _brush = new Material(shader) { hideFlags = HideFlags.DontSave };

        DirtyAgain();
    }

    void Release()
    {
        if (_mask != null) { _mask.Release(); DestroyImmediate(_mask); _mask = null; }
        if (_brush != null) { DestroyImmediate(_brush); _brush = null; }
    }

    /// <summary>Hand the mask to the renderers, without touching the material asset.</summary>
    void Push()
    {
        if (_mask == null) return;
        if (_block == null) _block = new MaterialPropertyBlock();

        foreach (var renderer in GetComponentsInChildren<Renderer>(true))
        {
            if (renderer.sharedMaterial == null) continue;
            if (!renderer.sharedMaterial.HasProperty(maskProperty)) continue;

            renderer.GetPropertyBlock(_block);
            _block.SetTexture(maskProperty, _mask);
            renderer.SetPropertyBlock(_block);
        }
    }

    /// <summary>Everything dirty again.</summary>
    public void DirtyAgain() { Fill(Color.black); }

    /// <summary>Everything clean, for a look at the surface underneath.</summary>
    public void WashAll() { Fill(Color.white); }

    void Fill(Color c)
    {
        if (_mask == null) Build();
        if (_mask == null) return;

        var prev = RenderTexture.active;
        RenderTexture.active = _mask;
        GL.Clear(false, true, c);
        RenderTexture.active = prev;
        Push();
    }

    void Creep(float dt)
    {
        if (creepBack <= 0f || _mask == null || _brush == null) return;

        // multiplying the mask down is what walks a cleaned patch back to dirty, and it
        // does it fastest where the wipe was thinnest, so the edges go first
        float keep = Mathf.Clamp01(1f - creepBack * dt * 0.6f);
        _brush.SetColor("_Ink", new Color(keep, keep, keep, 1f));
        Draw(1, new Vector2(0.5f, 0.5f), 1f);
        Push();
    }

    // --- wiping --------------------------------------------------------------

    /// <summary>Wipe at a UV, using the brush settings.</summary>
    public void Wipe(Vector2 uv) { Wipe(uv, radius, strength); }

    public void Wipe(Vector2 uv, float brushRadius, float brushStrength)
    {
        if (_mask == null) Build();
        if (_mask == null || _brush == null) return;

        _brush.SetColor("_Ink", new Color(brushStrength, brushStrength, brushStrength, 1f));
        _brush.SetFloat("_Core", core);

        // a dab near the seam has to land on both sides of it, or wiping down the back of
        // a sphere leaves a hard line where u wraps
        Draw(0, uv, brushRadius);
        if (uv.x < brushRadius) Draw(0, uv + Vector2.right, brushRadius);
        if (uv.x > 1f - brushRadius) Draw(0, uv - Vector2.right, brushRadius);

        Push();
    }

    void Draw(int pass, Vector2 centre, float r)
    {
        var prev = RenderTexture.active;
        RenderTexture.active = _mask;

        GL.PushMatrix();
        GL.LoadOrtho();
        _brush.SetPass(pass);

        GL.Begin(GL.QUADS);
        GL.TexCoord2(0f, 0f); GL.Vertex3(centre.x - r, centre.y - r, 0f);
        GL.TexCoord2(1f, 0f); GL.Vertex3(centre.x + r, centre.y - r, 0f);
        GL.TexCoord2(1f, 1f); GL.Vertex3(centre.x + r, centre.y + r, 0f);
        GL.TexCoord2(0f, 1f); GL.Vertex3(centre.x - r, centre.y + r, 0f);
        GL.End();

        GL.PopMatrix();
        RenderTexture.active = prev;
    }

    /// <summary>Wipe wherever a screen point lands on this object, if it lands on it.</summary>
    public bool WipeAt(Vector3 screenPoint)
    {
        var cam = through != null ? through : Camera.main;
        if (cam == null) return false;

        Vector2 uv;
        if (!Raycast(cam.ScreenPointToRay(screenPoint), out uv)) return false;

        Wipe(uv);
        return true;
    }

    /// <summary>
    /// Where a ray meets this object, in UV. Every hit along the ray is looked at, not
    /// just the first: a primitive comes with its own collider, that one is usually in
    /// front, and only a MeshCollider can name a UV.
    /// </summary>
    public bool Raycast(Ray ray, out Vector2 uv)
    {
        uv = Vector2.zero;

        // Whoever moved this object last moved the transform, not the collider: outside
        // play mode nothing pushes that across on its own, so a spinning subject ends up
        // being clicked in the pose it held when physics last looked. The stroke then
        // lands on the far side of the object and nothing appears to happen.
        Physics.SyncTransforms();

        var hits = Physics.RaycastAll(ray, 5000f);
        float best = float.MaxValue;
        bool found = false;

        foreach (var hit in hits)
        {
            var mesh = hit.collider as MeshCollider;
            if (mesh == null || !mesh.transform.IsChildOf(transform)) continue;
            if (hit.distance >= best) continue;

            best = hit.distance;
            uv = hit.textureCoord;
            found = true;
        }

        return found;
    }

    /// <summary>
    /// A MeshCollider is the price of knowing which UV was clicked. A primitive brings a
    /// rounder one along, which would take the hit first, so that one steps aside.
    /// </summary>
    public void FitCollider()
    {
        var filter = GetComponent<MeshFilter>();
        if (filter == null || filter.sharedMesh == null) return;

        foreach (var other in GetComponents<Collider>())
        {
            var mesh = other as MeshCollider;
            if (mesh == null) other.enabled = false;
            else mesh.sharedMesh = filter.sharedMesh;
        }

        if (GetComponent<MeshCollider>() != null) return;

        var added = gameObject.AddComponent<MeshCollider>();
        added.sharedMesh = filter.sharedMesh;
    }

    public bool Ready
    {
        get
        {
            var renderer = GetComponent<Renderer>();
            return renderer != null && renderer.sharedMaterial != null
                && renderer.sharedMaterial.HasProperty(maskProperty);
        }
    }
}
