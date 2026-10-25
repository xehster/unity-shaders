#ifndef PURR_SURFACE_SHAPE
#define PURR_SURFACE_SHAPE

// Shared by the elemental surface shaders (Puddle, FireGround): value noise, the ragged disc outline and the
// walker ripples. Drawn on a unit cylinder: object xz × 2 is the disc (-1..1), no UVs.

#define MAX_RIPPLES 8

float Hash(float2 p) { return frac(sin(dot(p, float2(127.1, 311.7))) * 43758.5453); }

float Noise(float2 p)
{
    float2 i = floor(p), f = frac(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    return lerp(lerp(Hash(i), Hash(i + float2(1, 0)), u.x),
                lerp(Hash(i + float2(0, 1)), Hash(i + float2(1, 1)), u.x), u.y);
}

float Fbm(float2 p)
{
    return Noise(p) * 0.6 + Noise(p * 2.13 + 7.1) * 0.3 + Noise(p * 4.37 + 3.7) * 0.1;
}

// Ragged outline of a disc drawn on a unit cylinder: 1 inside, 0 outside, soft over a pixel or so.
float SurfaceOutline(float2 disc, float2 worldXZ, float noiseScale, float raggedness, out float r, out float outer)
{
    r = length(disc);
    outer = 1.0 - raggedness * Fbm(worldXZ * noiseScale + 13.7);
    float aa = fwidth(r) * 1.5;
    return 1.0 - smoothstep(outer - aa, outer, r);
}

#ifndef SURFACE_SHAPE_NO_RIPPLES
// per surface, from script (MaterialPropertyBlock): world x, world z, age s, strength
float4 _Ripples[MAX_RIPPLES];

// height of the water surface at a world xz from every ripple — rings running out from where a foot
// came down, a short wave packet that fades with age and distance.
// Needs _RippleWavelength, _RippleSpeed, _RippleLife, _IdleBump declared by the including shader.
float RippleHeight(float2 xz)
{
    float h = 0;
    float k = 6.2831853 / _RippleWavelength;
    [unroll] for (int i = 0; i < MAX_RIPPLES; i++)
    {
        float4 r = _Ripples[i];
        if (r.w <= 0 || r.z >= _RippleLife) continue;
        float d = distance(xz, r.xy);
        float front = r.z * _RippleSpeed;
        float x = d - front;
        float packet = exp(-x * x * 18.0);                       // a few rings around the front
        float fade = (1.0 - r.z / _RippleLife);
        h += sin(x * k) * packet * fade * fade * r.w / (1.0 + d * 1.5);
    }
    // a faint idle wobble so the still water is never a mirror-flat decal
    h += (Noise(xz * 3.0 + _Time.y * 0.6) - 0.5) * _IdleBump;
    return h;
}
#endif

#endif // PURR_SURFACE_SHAPE
