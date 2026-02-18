#ifndef BRDF_MODELS_HLSL
#define BRDF_MODELS_HLSL
#include "math/math_constants.hlsl"
float3 Cook_Torrance(float3 N, float3 V, float3 L, float3 albedo, float rough, float metal)
{
    float3 H = normalize(V + L);

    float NdotV = saturate(dot(N, V));
    float NdotL = saturate(dot(N, L));
    float NdotH = saturate(dot(N, H));
    float VdotH = saturate(dot(V, H));

    if (NdotL <= 0.0 || NdotV <= 0.0)
        return float3(0.0, 0.0, 0.0);

    // --- F0 ---
    float3 F0 = lerp(float3(0.04, 0.04, 0.04), albedo, metal);

        // --- Fresnel (Schlick) ---
    float3 F = F0 + (1.0 - F0) * pow(1.0 - VdotH, 5.0);

    // --- GGX Normal Distribution ---
    float a = rough * rough;
    float a2 = a * a;
    float denom = (NdotH * NdotH) * (a2 - 1.0) + 1.0;
    float D = a2 / (PI * denom * denom);

    // --- Smith GGX Geometry (Schlick-GGX) ---
    float k = (rough + 1.0);
    k = (k * k) / 8.0;

    float Gv = NdotV / (NdotV * (1.0 - k) + k);
    float Gl = NdotL / (NdotL * (1.0 - k) + k);
    float G = Gv * Gl;


    // --- Specular ---
    float3 spec = ((D * G * F) / (4.0 * NdotL * NdotV + 1e-5));

    // --- Diffuse (energy conserving) ---
    float3 kd = (1.0 - F) * (1.0 - metal);
    float3 diff = kd * albedo * (1.0 / PI);

    return (diff + spec) * NdotL;
}

float3 Fast_MSX(float3 N, float3 V, float3 L, float3 albedo, float rough, float metal)
{
    return albedo * 0.8f;
}

float3 Heitz(float3 N, float3 V, float3 L, float3 albedo, float rough, float metal)
{
    return albedo * 0.6f;
}
#endif
