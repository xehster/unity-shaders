#ifndef PURR_STUDIO_FX_INCLUDED
#define PURR_STUDIO_FX_INCLUDED

// Shared motion + screen life for the cable-chamber studio. Driven by globals StudioController sets;
// all zero (the default when nothing sets them) = everything still and steady.
// StudioFx.cs mirrors the screen functions so the lamps next to a screen flicker with it.

float _StudioSway;          // cable sway amplitude, metres at a fully free point (0 = off)
float _StudioSwaySpeed;     // 1 = default tempo
float _StudioFlicker;       // 0..1 screen brightness wobble
float _StudioGlitch;        // 0..1 glitch strength (0 = none)
float _StudioGlitchRate;    // glitches per screen per ~10 s

// sin-free hashes (Hoskins): identical on GPU and in StudioFx.cs, even at big coordinates / times
float StudioHash11(float p) { p = frac(p * 0.1031); p *= p + 33.33; p *= p + p; return frac(p); }
float StudioHash13(float3 p3) { p3 = frac(p3 * 0.1031); p3 += dot(p3, p3.zyx + 31.32); return frac((p3.x + p3.y) * p3.z); }
float StudioNoise1(float x)
{
    float i = floor(x), f = frac(x);
    float u = f * f * (3.0 - 2.0 * f);
    return lerp(StudioHash11(i), StudioHash11(i + 1.0), u);
}

// ---- cables: vertex sway. weight 0 = held (ceiling / floor), 1 = free; seed decorrelates cables ----
float3 StudioSwayOffset(float3 positionWS, float weight, float seed)
{
    if (_StudioSway <= 0.0 || weight <= 0.0) return 0;
    float t = _Time.y * max(_StudioSwaySpeed, 0.0);
    // a slow draught drifting through the room: neighbours move alike, never in lock-step
    float ph = dot(positionWS.xz, float2(0.23, 0.17)) + seed * 6.2831;
    float x = sin(t * 0.61 + ph) + 0.45 * sin(t * 1.37 + ph * 1.7 + 1.3);
    float z = sin(t * 0.47 + ph * 1.3 + 2.1) + 0.45 * sin(t * 1.13 + ph * 0.8 + 0.4);
    return float3(x, 0.0, z) * (_StudioSway * weight * 0.7);
}

// ---- screens ----
// seed from the object's own position: every screen is its own object, so it gets its own rhythm
float StudioObjectSeed()
{
    return StudioHash13(float3(UNITY_MATRIX_M._m03, UNITY_MATRIX_M._m13, UNITY_MATRIX_M._m23));
}

// x = brightness multiplier, y = glitch type (-1 none, 0 bands, 1 rgb split, 2 roll, 3 static, 4 blackout, 5 swap),
// z = 0..1 progress through the glitch, w = glitch intensity
float4 StudioScreenState(float t, float seed)
{
    float flick = 1.0 - _StudioFlicker * (0.10 * StudioNoise1(t * 7.3 + seed * 91.0) + 0.06 * StudioNoise1(t * 23.0 + seed * 13.0));
    float4 s = float4(flick, -1, 0, 0);
    if (_StudioGlitch <= 0.0) return s;
    float period = lerp(4.0, 11.0, StudioHash11(seed * 17.0)) / max(_StudioGlitchRate, 0.05);
    float tt = t + seed * 37.0;
    float slot = floor(tt / period);
    float h = StudioHash11(slot * 1.37 + seed * 101.0);
    if (h > 0.55) return s;                                   // most slots stay clean
    float start = StudioHash11(slot * 2.11 + seed * 7.0) * period * 0.7;
    float dur = lerp(0.08, 0.5, StudioHash11(slot * 3.7 + seed * 3.0));
    float local = tt - slot * period - start;
    if (local < 0.0 || local > dur) return s;
    s.y = floor(StudioHash11(slot * 5.3 + seed * 11.0) * 5.999);
    s.z = local / dur;
    s.w = _StudioGlitch;
    if (s.y == 4) s.x *= lerp(1.0, 0.04, s.w);                // blackout
    if (s.y == 3) s.x *= lerp(1.0, 0.55 + 0.45 * StudioNoise1(t * 60.0), s.w);
    return s;
}

#endif
