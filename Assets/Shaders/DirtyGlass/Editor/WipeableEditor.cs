using UnityEditor;
using UnityEditorInternal;
using UnityEngine;

/// <summary>
/// Turns the Scene view into a cloth. While wipe mode is on, dragging over the object
/// rubs the dirt off it and nothing else takes the click.
///
/// The handler is registered globally rather than through OnSceneGUI, so wiping keeps
/// working when the component is being shown through the gallery rig's panel and the
/// object itself is not what's selected.
/// </summary>
[CustomEditor(typeof(Wipeable))]
public class WipeableEditor : Editor
{
    static Wipeable _painting;

    public override void OnInspectorGUI()
    {
        var wipeable = (Wipeable)target;

        DrawDefaultInspector();
        EditorGUILayout.Space(4f);

        if (!wipeable.Ready)
        {
            EditorGUILayout.HelpBox(
                "The material on this object has no " + wipeable.maskProperty +
                ", so there is nothing to wipe. Custom/Dirty Glass has one.",
                MessageType.Warning);
        }

        if (wipeable.GetComponent<MeshCollider>() == null)
        {
            EditorGUILayout.HelpBox(
                "Wiping needs a MeshCollider: it is the only one that can say which part " +
                "of the texture was clicked.", MessageType.Info);

            if (GUILayout.Button("Add one"))
            {
                Undo.RegisterCompleteObjectUndo(wipeable.gameObject, "Fit collider");
                wipeable.FitCollider();
            }
            return;
        }

        bool on = _painting == wipeable;
        var bg = GUI.backgroundColor;
        if (on) GUI.backgroundColor = new Color(0.55f, 0.85f, 1f);

        if (GUILayout.Button(on ? "Wiping - click here or press Esc to stop" : "Wipe it by hand",
                GUILayout.Height(24f)))
            SetPainting(on ? null : wipeable);

        GUI.backgroundColor = bg;

        if (on)
            EditorGUILayout.LabelField("Drag over it in the Scene view.", EditorStyles.miniLabel);

        using (new EditorGUILayout.HorizontalScope())
        {
            if (GUILayout.Button("Wash it all off")) wipeable.WashAll();
            if (GUILayout.Button("Dirty it up again")) wipeable.DirtyAgain();
        }
    }

    static void SetPainting(Wipeable wipeable)
    {
        SceneView.duringSceneGui -= OnScene;
        _painting = wipeable;

        if (_painting != null) SceneView.duringSceneGui += OnScene;
        SceneView.RepaintAll();
    }

    static void OnScene(SceneView view)
    {
        if (_painting == null) { SetPainting(null); return; }

        var e = Event.current;

        // takes the click before the selection machinery gets to it, so dragging over the
        // object wipes instead of picking whatever is behind it
        int id = GUIUtility.GetControlID(FocusType.Passive);
        if (e.type == EventType.Layout) { HandleUtility.AddDefaultControl(id); return; }

        Handles.BeginGUI();
        GUI.Label(new Rect(8f, 8f, 320f, 20f), "Wiping " + _painting.name + " - Esc to stop");
        Handles.EndGUI();

        if (e.type == EventType.KeyDown && e.keyCode == KeyCode.Escape)
        {
            SetPainting(null);
            e.Use();
            return;
        }

        bool stroke = (e.type == EventType.MouseDown || e.type == EventType.MouseDrag)
            && e.button == 0 && !e.alt;
        if (!stroke) return;

        Vector2 uv;
        if (_painting.Raycast(HandleUtility.GUIPointToWorldRay(e.mousePosition), out uv))
        {
            _painting.Wipe(uv);

            // the Game view is where the shot is framed, and it is not a SceneView, so
            // repainting only the latter leaves the wipe looking like it missed
            InternalEditorUtility.RepaintAllViews();
        }

        e.Use();
    }
}
