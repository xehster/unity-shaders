using UnityEditor;
using UnityEditorInternal;
using UnityEngine;

/// <summary>
/// Shooting at the thing in the Scene view. Click for a round, hold Shift for a swing,
/// and the drag direction is what a swing is aimed along.
///
/// Registered globally rather than through OnSceneGUI, so it keeps working while the
/// component is being shown through the gallery rig's panel and the object itself is not
/// what's selected.
/// </summary>
[CustomEditor(typeof(ImpactSurface))]
public class ImpactSurfaceEditor : Editor
{
    static ImpactSurface _firing;
    static Vector2 _pressedAt;

    public override void OnInspectorGUI()
    {
        var surface = (ImpactSurface)target;

        DrawDefaultInspector();
        EditorGUILayout.Space(4f);

        if (!surface.Ready)
        {
            EditorGUILayout.HelpBox(
                "The material on this object does not take marks. Custom/Impact Marks does.",
                MessageType.Warning);
            return;
        }

        if (surface.GetComponent<Collider>() == null)
        {
            EditorGUILayout.HelpBox("Aiming needs a collider on this object.", MessageType.Info);
            return;
        }

        bool on = _firing == surface;
        var bg = GUI.backgroundColor;
        if (on) GUI.backgroundColor = new Color(0.55f, 0.85f, 1f);

        if (GUILayout.Button(on ? "Shooting - click here or press Esc to stop" : "Shoot it by hand",
                GUILayout.Height(24f)))
            SetFiring(on ? null : surface);

        GUI.backgroundColor = bg;

        if (on)
            EditorGUILayout.LabelField("Click it in the Scene view. Shift-drag swings.",
                EditorStyles.miniLabel);

        using (new EditorGUILayout.HorizontalScope())
        {
            if (GUILayout.Button("One round")) surface.HitSomewhere();
            if (GUILayout.Button("Clear")) surface.Clear();
        }

        EditorGUILayout.LabelField(surface.Landed + " of " + surface.keep + " marks on it",
            EditorStyles.miniLabel);
    }

    static void SetFiring(ImpactSurface surface)
    {
        SceneView.duringSceneGui -= OnScene;
        _firing = surface;

        if (_firing != null) SceneView.duringSceneGui += OnScene;
        SceneView.RepaintAll();
    }

    static void OnScene(SceneView view)
    {
        if (_firing == null) { SetFiring(null); return; }

        var e = Event.current;

        int id = GUIUtility.GetControlID(FocusType.Passive);
        if (e.type == EventType.Layout) { HandleUtility.AddDefaultControl(id); return; }

        Handles.BeginGUI();
        GUI.Label(new Rect(8f, 8f, 380f, 20f),
            "Shooting " + _firing.name + " - Shift-drag to swing, Esc to stop");
        Handles.EndGUI();

        if (e.type == EventType.KeyDown && e.keyCode == KeyCode.Escape)
        {
            SetFiring(null);
            e.Use();
            return;
        }

        if (e.button != 0 || e.alt) return;

        if (e.type == EventType.MouseDown)
        {
            _pressedAt = e.mousePosition;
            if (!e.shift) Fire(view, e.mousePosition, ImpactSurface.Kind.Bullet, Vector2.zero);
            e.Use();
            return;
        }

        if (e.type != EventType.MouseUp || !e.shift) return;

        // a swing is aimed, so it waits for the mouse to come up and uses the drag
        Fire(view, _pressedAt, ImpactSurface.Kind.Melee, e.mousePosition - _pressedAt);
        e.Use();
    }

    static void Fire(SceneView view, Vector2 mouse, ImpactSurface.Kind kind, Vector2 drag)
    {
        var ray = HandleUtility.GUIPointToWorldRay(mouse);

        // screen drag turned back into a direction in the world, so the mark lies the way
        // the mouse was pulled. A click with no drag swings along the camera's up.
        var cam = view.camera;
        Vector3 swing = drag.sqrMagnitude > 4f
            ? (cam.transform.right * drag.x - cam.transform.up * drag.y).normalized
            : cam.transform.up;

        if (!_firing.HitAlong(ray, kind, swing)) return;

        // the Game view is where the shot is framed, and it is not a SceneView
        InternalEditorUtility.RepaintAllViews();
    }
}
