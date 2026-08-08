using System.IO;
using UnityEditor;
using UnityEngine;

/// <summary>
/// Packs the hand drawn eye parts into the one texture the eye shader reads.
///
/// Source art lives in the Source folder next to this script, as RGBA with the shape in
/// the alpha: Lid0..Lid3 are the lids from widest open to shut, where opaque is lid and
/// the hole is what you see through; Sclera is the eye white; Pupil is the pupil. Add
/// more lid frames and the bake picks them up.
///
/// The lids do not become a flipbook. Four frames played in turn would jump between four
/// fixed shapes, so instead every pixel is asked a different question: how far open does
/// the eye have to be before you show? That answer is one number, so the lid edge sweeps
/// smoothly and stays crisp, and it costs one channel rather than two samples.
///
///   R  how far open before this pixel clears the lid
///   G  the eye white
///   B  the pupil, sampled again at a shifted uv so it can look around
/// </summary>
public static class EyeApertureBaker
{
    const int BlurRadius = 5;

    [MenuItem("Shader Gallery/Bake Eye Mask")]
    public static void Bake()
    {
        // Find the art rather than remember where it is: this folder sits in one place in
        // the gallery and another in the shader repo, and a written down path is wrong in
        // one of them the moment the shader travels.
        string source = FindSourceFolder();
        if (source == null)
        {
            Debug.LogError("Eye mask: no Lid0.png anywhere in the project, so there is no eye art to bake");
            return;
        }
        string output = Path.GetDirectoryName(source).Replace('\\', '/') + "/EyeMask.png";

        var lids = new System.Collections.Generic.List<Texture2D>();
        for (int i = 0; ; i++)
        {
            string path = string.Format("{0}/Lid{1}.png", source, i);
            if (!File.Exists(path)) break;
            lids.Add(LoadReadable(path));
        }

        var sclera = LoadReadable(source + "/Sclera.png");
        var pupil = LoadReadable(source + "/Pupil.png");

        if (lids.Count < 2 || sclera == null || pupil == null)
        {
            Debug.LogError("Eye mask: " + source + " needs Lid0, Lid1, Sclera and Pupil at least");
            return;
        }

        int w = sclera.width;
        int h = sclera.height;
        foreach (var t in lids)
        {
            if (t.width == w && t.height == h) continue;
            Debug.LogError("Eye mask: the lid frames are not the same size as the sclera");
            return;
        }
        if (pupil.width != w || pupil.height != h)
        {
            Debug.LogError("Eye mask: the pupil is not the same size as the sclera");
            return;
        }

        var lidPixels = new Color32[lids.Count][];
        for (int i = 0; i < lids.Count; i++) lidPixels[i] = lids[i].GetPixels32();
        var scleraPixels = sclera.GetPixels32();
        var pupilPixels = pupil.GetPixels32();

        // A pixel that is still clear in the tightest frame opens first; one that only
        // clears in the widest frame opens last; one covered in every frame never opens.
        var open = new float[w * h];
        for (int p = 0; p < open.Length; p++)
        {
            int tightest = -1;
            for (int i = 0; i < lids.Count; i++)
                if (lidPixels[i][p].a < 128) tightest = i;

            open[p] = tightest < 0 ? 1f : 1f - (tightest + 1) / (float)lids.Count;
        }

        // soften the steps between drawn frames so the edge slides instead of snapping
        Blur(open, w, h, BlurRadius);

        var packed = new Color32[open.Length];
        for (int p = 0; p < open.Length; p++)
        {
            packed[p] = new Color32(
                (byte)Mathf.RoundToInt(Mathf.Clamp01(open[p]) * 255f),
                scleraPixels[p].a,
                pupilPixels[p].a,
                255);
        }

        var result = new Texture2D(w, h, TextureFormat.RGBA32, false, true);
        result.SetPixels32(packed);
        result.Apply();

        File.WriteAllBytes(output, result.EncodeToPNG());
        Object.DestroyImmediate(result);

        AssetDatabase.ImportAsset(output, ImportAssetOptions.ForceUpdate);

        // three masks, not a picture, so no gamma curve on the way in
        var importer = (TextureImporter)AssetImporter.GetAtPath(output);
        importer.sRGBTexture = false;
        importer.wrapMode = TextureWrapMode.Clamp;
        importer.textureCompression = TextureImporterCompression.Uncompressed;
        importer.alphaSource = TextureImporterAlphaSource.None;
        importer.SaveAndReimport();

        Debug.Log(string.Format("Eye mask: packed {0} lid frames into {1}", lids.Count, output));
    }

    static string FindSourceFolder()
    {
        foreach (var guid in AssetDatabase.FindAssets("Lid0 t:Texture2D"))
        {
            string path = AssetDatabase.GUIDToAssetPath(guid);
            if (path.EndsWith("/Lid0.png"))
                return path.Substring(0, path.Length - "/Lid0.png".Length);
        }
        return null;
    }

    /// <summary>Separable box blur, two passes for a rounder falloff.</summary>
    static void Blur(float[] data, int w, int h, int radius)
    {
        if (radius < 1) return;
        var temp = new float[data.Length];

        for (int pass = 0; pass < 2; pass++)
        {
            for (int y = 0; y < h; y++)
                for (int x = 0; x < w; x++)
                {
                    float sum = 0f;
                    for (int k = -radius; k <= radius; k++)
                        sum += data[y * w + Mathf.Clamp(x + k, 0, w - 1)];
                    temp[y * w + x] = sum / (radius * 2 + 1);
                }

            for (int y = 0; y < h; y++)
                for (int x = 0; x < w; x++)
                {
                    float sum = 0f;
                    for (int k = -radius; k <= radius; k++)
                        sum += temp[Mathf.Clamp(y + k, 0, h - 1) * w + x];
                    data[y * w + x] = sum / (radius * 2 + 1);
                }
        }
    }

    static Texture2D LoadReadable(string path)
    {
        var importer = (TextureImporter)AssetImporter.GetAtPath(path);
        if (importer == null) return null;

        if (!importer.isReadable || importer.textureCompression != TextureImporterCompression.Uncompressed)
        {
            // compression would smear the alpha the shapes are stored in
            importer.isReadable = true;
            importer.textureCompression = TextureImporterCompression.Uncompressed;
            importer.SaveAndReimport();
        }
        return AssetDatabase.LoadAssetAtPath<Texture2D>(path);
    }
}
