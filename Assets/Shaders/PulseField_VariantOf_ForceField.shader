Shader "Purrfield/Pulse Field (Variant of Force Field)"
{
    // Rings spreading outward ALONG THE GROUND from the wearer, for the torso aura modules: the
    // same shader serves the damage coil and the repair coil, the colour is the only difference.
    //
    // Measured on the XZ radius rather than as a sphere (Eva, 2026-09-19): the aura is energy
    // dissipating in a circle around the robot, not a bubble around it. It is not perfectly flat
    // either - _Height fades the effect vertically, so it has body near the floor and thins out
    // above, which is what keeps it from reading as a decal.
    //
    // Everything is in OBJECT space, so the pattern never crawls across the aura as the robot
    // walks - a world-space pattern would slide under the effect and destroy the illusion that
    // the rings belong to the wearer.
    Properties
    {
        [HDR] _Color ("Colour", Color) = (1.0, 0.45, 0.15, 1)
        _Alpha ("Base Opacity", Range(0, 1)) = 0.04
        _FresnelPower ("Fresnel Power", Range(0.5, 8)) = 2.5
        _FresnelBoost ("Fresnel Boost", Range(0, 4)) = 0.6

        _RingSpeed ("Ring Speed", Range(0.05, 4)) = 1.0
        _RingWidth ("Ring Width", Range(0.01, 1)) = 0.10
        _RingCount ("Rings At Once", Range(1, 6)) = 2
        _RingSharpness ("Ring Sharpness", Range(1, 8)) = 2.5
        _Height ("Vertical Falloff", Range(0.05, 2)) = 0.45
    }

    SubShader
    {
        Tags { "RenderType"="Transparent" "Queue"="Transparent" "RenderPipeline"="UniversalPipeline" }

        // Premultiplied, not additive - the same choice the shield shader makes and for the same
        // reason: straight additive blows out to white over anything bright, and an effect standing
        // in daylight should not turn into a lamp.
        Blend One OneMinusSrcAlpha
        ZWrite Off

        HLSLINCLUDE
        #pragma vertex vert
        #pragma fragment frag
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

        CBUFFER_START(UnityPerMaterial)
            half4 _Color;
            float _Alpha;
            float _FresnelPower;
            float _FresnelBoost;
            float _RingSpeed;
            float _RingWidth;
            float _RingCount;
            float _RingSharpness;
            float _Height;
        CBUFFER_END

        struct Attributes
        {
            float4 positionOS : POSITION;
            float3 normalOS   : NORMAL;
        };

        struct Varyings
        {
            float4 positionCS : SV_POSITION;
            float3 positionOS : TEXCOORD0;
            float3 normalWS   : TEXCOORD1;
            float3 viewWS     : TEXCOORD2;
        };

        Varyings vert (Attributes IN)
        {
            Varyings OUT;
            VertexPositionInputs p = GetVertexPositionInputs(IN.positionOS.xyz);
            OUT.positionCS = p.positionCS;
            OUT.positionOS = IN.positionOS.xyz;
            OUT.normalWS = GetVertexNormalInputs(IN.normalOS).normalWS;
            OUT.viewWS = GetWorldSpaceNormalizeViewDir(p.positionWS);
            return OUT;
        }

        // Several rings in flight at once, evenly spaced in phase so they leave at a steady beat
        // rather than all at once.
        float Rings(float3 positionOS)
        {
            // Distance along the floor only - 0.5 is the object-space radius of a unit sphere, so
            // this is 0..1 from the wearer out to the edge of the aura.
            float r = saturate(length(positionOS.xz) / 0.5);
            float total = 0;
            int count = (int)floor(_RingCount);

            [loop]
            for (int i = 0; i < count; i++)
            {
                // Each ring is the same travel, offset by its share of one period.
                float phase = frac(_Time.y * _RingSpeed + (float)i / max(1.0, (float)count));
                float band = abs(r - phase);
                float ring = saturate(1.0 - band / _RingWidth);
                ring = pow(ring, _RingSharpness);
                // Fade as it reaches the edge, so rings dissolve instead of popping at the rim.
                total += ring * (1.0 - phase * phase);
            }
            return total;
        }

        half4 frag (Varyings IN) : SV_Target
        {
            float3 n = normalize(IN.normalWS);
            // abs, or back faces read as pure rim and the volume fills in solid
            float facing = saturate(abs(dot(n, normalize(IN.viewWS))));
            float fresnel = pow(1.0 - facing, _FresnelPower) * _FresnelBoost;

            // Vertical falloff: strongest at the wearer's feet, thinning with height, so the aura
            // sits on the ground instead of enclosing them.
            float height = saturate(1.0 - abs(IN.positionOS.y) / max(0.001, _Height * 0.5));
            height *= height;

            float glow = (_Alpha + fresnel + Rings(IN.positionOS) * 1.2) * height;
            float coverage = saturate(glow);
            // glow is left unclamped so an HDR colour crosses the project's bloom threshold on its
            // own - the rings and rim bloom, the flat middle stays calm.
            return half4(_Color.rgb * glow, coverage);
        }
        ENDHLSL

        // Far faces first, near faces second, so the aura reads as a volume rather than coming out
        // in mesh order. Same two-pass trick as the shield.
        Pass
        {
            Name "PulseFar"
            Tags { "LightMode"="UniversalForward" }
            Cull Front
            HLSLPROGRAM
            ENDHLSL
        }

        Pass
        {
            Name "PulseNear"
            Tags { "LightMode"="SRPDefaultUnlit" }
            Cull Back
            HLSLPROGRAM
            ENDHLSL
        }
    }
}
