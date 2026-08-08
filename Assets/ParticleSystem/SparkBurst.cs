using UnityEngine;

/// <summary>
/// A sparkler that lives at one point: hit something, it crackles for a moment and dies.
/// Wraps the particle system so the settings that matter for an impact are five fields
/// instead of six modules, and keeps them in step whenever one is edited.
///
/// Colour and brightness are not here, they belong to the material: the gallery already
/// draws material properties in its own panel, and a property block set from here would
/// quietly override what you set there. Per instance tint still works through the
/// particle system's own Start Color, which the shader multiplies in.
/// </summary>
[ExecuteAlways]
[RequireComponent(typeof(ParticleSystem))]
public class SparkBurst : MonoBehaviour
{
    [Tooltip("How fast sparks leave the middle. They slow to a stop over their life.")]
    [Min(0f)] public float sparkSpeed = 7f;

    [Tooltip("How far the furthest spark gets before it stops.")]
    [Min(0f)] public float radius = 1.1f;

    [Tooltip("Seconds of crackling. Zero means it never sparks.")]
    [Min(0f)] public float duration = 0.35f;

    [Tooltip("Keep sparking forever instead of stopping after Duration.")]
    public bool neverStops;

    [Tooltip("Sparks per second while it is going.")]
    [Min(0f)] public float density = 220f;

    [Tooltip("Sparks thrown in the first instant, the flash of the hit itself.")]
    [Min(0)] public int flash = 30;

    [Tooltip("How much of the middle the sparks are born in. Zero is a single point.")]
    [Min(0f)] public float sourceRadius = 0.03f;

    ParticleSystem _system;

    ParticleSystem System
    {
        get
        {
            if (_system == null) _system = GetComponent<ParticleSystem>();
            return _system;
        }
    }

    void OnEnable() { Apply(); }

#if UNITY_EDITOR
    void OnValidate()
    {
        // OnValidate lands mid serialisation, when touching the system is not allowed,
        // so hand the work to the next editor tick
        if (!isActiveAndEnabled) return;
        UnityEditor.EditorApplication.delayCall += () => { if (this != null) Apply(); };
    }
#endif

    /// <summary>Throw one burst, for the moment something gets hit.</summary>
    public void Fire()
    {
        Apply();
        System.Clear(true);
        System.Play(true);
    }

    /// <summary>Push the fields into the modules they each belong to.</summary>
    public void Apply()
    {
        var ps = System;
        if (ps == null) return;

        // Speed ramps to zero over the life, so the average is half of the start and a
        // spark covers speed * life / 2. Turn that around to get the life from a radius.
        float life = sparkSpeed > 0.01f ? Mathf.Max(2f * radius / sparkSpeed, 0.02f) : 0.5f;

        var main = ps.main;
        main.loop = neverStops;
        main.startLifetime = new ParticleSystem.MinMaxCurve(life * 0.55f, life);
        main.startSpeed = new ParticleSystem.MinMaxCurve(sparkSpeed * 0.45f, sparkSpeed);
        main.simulationSpace = ParticleSystemSimulationSpace.World;

        // Duration and the seed are the two the system refuses to have changed under it,
        // so touch them only when they are actually wrong, and stop it first when they are.
        float wanted = Mathf.Max(duration, 0.01f);
        if (!Mathf.Approximately(main.duration, wanted) || !ps.useAutoRandomSeed)
        {
            bool running = ps.isPlaying;
            if (running) ps.Stop(true, ParticleSystemStopBehavior.StopEmittingAndClear);

            main.duration = wanted;
            ps.useAutoRandomSeed = true; // every burst comes out different

            if (running) ps.Play(true);
        }

        var emission = ps.emission;
        emission.enabled = duration > 0f || neverStops;
        emission.rateOverTime = density;
        emission.SetBursts(flash > 0
            ? new[] { new ParticleSystem.Burst(0f, (short)flash) }
            : new ParticleSystem.Burst[0]);

        var shape = ps.shape;
        shape.enabled = true;
        shape.shapeType = ParticleSystemShapeType.Sphere;
        shape.radius = Mathf.Max(sourceRadius, 0.0001f);

        // The brake. A ceiling that falls from the start speed to nothing over the life
        // is what makes the ramp linear, which is the assumption the radius maths above
        // rests on. A flat low ceiling would just pin every spark to the middle.
        var limit = ps.limitVelocityOverLifetime;
        limit.enabled = true;
        limit.separateAxes = false;
        limit.dampen = 1f;
        limit.limit = new ParticleSystem.MinMaxCurve(sparkSpeed, AnimationCurve.Linear(0f, 1f, 1f, 0f));
    }
}
