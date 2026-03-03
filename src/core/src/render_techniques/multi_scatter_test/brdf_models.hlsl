#ifndef BRDF_MODELS_HLSL
#define BRDF_MODELS_HLSL
#include "math/math_constants.hlsl"



float SchlickGGX(float NdotV, float NdotL, float rough)
{
    float r = rough + 1.0;
    float k = (r * r) / 8.0;
    float Gv = NdotV / (NdotV * (1.0 - k) + k);
    float Gl = NdotL / (NdotL * (1.0 - k) + k);
    return Gv * Gl;
}
float GGX_NDF(float NdotH, float rough)
{
    float a = rough;
    float a2 = a * a;
    float denom = (NdotH * NdotH) * (a2 - 1.0) + 1.0;
    return a2 / (PI * denom * denom);
}
float3 F0(float3 albedo, float metal)
{
    return lerp(float3(0.04, 0.04, 0.04), albedo, metal);
}

float3 Fresnel_Schlick(float VdotH, float3 F0)
{
    return F0 + (1.0 - F0) * pow(1.0 - VdotH, 5.0);
}

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
    float3 f0 = F0(albedo, metal);

        // --- Fresnel (Schlick) ---
    float3 F = Fresnel_Schlick(VdotH, f0);

    // --- GGX Normal Distribution ---
    float D = GGX_NDF(NdotH, rough);

    // --- Smith GGX Geometry (Schlick-GGX) ---
    float G = SchlickGGX(NdotV, NdotL, rough);


    // --- Specular ---
    float3 spec = ((D * G * F) / (4.0 * NdotL * NdotV + 1e-5));

    // --- Diffuse (energy conserving) ---
    float3 kd = (1.0 - F) * (1.0 - metal);
    float3 diff = kd * albedo * (1.0 / PI);

    return (diff + spec);
}

float3 Fast_MSX(float3 N, float3 V, float3 L, float3 albedo, float rough, float metal)
{

    float3 H = normalize(V + L);
    float3 C = normalize(H + N);

    float NdotV = saturate(dot(N, V));
    float NdotL = saturate(dot(N, L));
    float NdotH = saturate(dot(N, H));
    float VdotH = saturate(dot(V, H));

    float CosVC = saturate(dot(V, C));
    float ThetaVC = acos(CosVC);
    float ThetaM = (PI - acos(saturate(dot(V, L)))) * 0.25;

    if (NdotL <= 0.0 || NdotV <= 0.0)
        return float3(0.0, 0.0, 0.0);

    // --- F0 ---
    float3 f0 = F0(albedo, metal);

        // --- Fresnel (Schlick) ---
    float3 F = Fresnel_Schlick(VdotH, f0);

    // --- GGX Normal Distribution ---
    float D = GGX_NDF(NdotH, rough);

    // --- Smith GGX Geometry (Schlick-GGX) ---
    float G = SchlickGGX(NdotV, NdotL, rough);

    // --- MSX NDF ---
    float CosTM = cos(ThetaM);
    float denom = CosTM * CosTM * (rough * rough - 1.0) + 1.0;
    float DI = (rough * rough) / (PI * denom * denom);

    //  --- MSX Geometry ---
    float OP = sin(ThetaVC - ThetaM) * sin(ThetaVC - ThetaM) / (sin(ThetaVC) + sin(ThetaM));
    float GI = 1.0 - max(0.0, OP);

    // --- MSX Fresnel ---
    float3 FI = F * F;

    
    // --- Cook-Torrance Specular ---
    float3 FsE = ((D * G * F) / (4.0 * NdotL * NdotV + 1e-5));

    // --- MSX Specular ---
    float3 FsI = (DI * GI * FI) / (2.0 * max(1e-4, CosVC));
    float3 spec = FsE + FsI;

    // --- Diffuse (energy conserving) ---
    float3 kd = (1.0 - F) * (1.0 - metal);
    float3 diff = kd * albedo * (1.0 / PI);

    return diff + spec;
}
float Luminance(float3 c)
{
    return dot(c, float3(0.2126, 0.7152, 0.0722));
}
float Ess_Approx(float rough, float3 f0)
{
    float a = rough * rough;
    float F0_lum = Luminance(f0); // Base term: smoother surfaces keep more energy in single scattering 

    float Ess = 1.0 - a * (0.6 + 0.4 * F0_lum); 
    return saturate(Ess); 
}

float3 Heitz(float3 N, float3 V, float3 L, float3 albedo, float rough, float metal)
{
    float3 H = normalize(V + L);

    float NdotV = saturate(dot(N, V));
    float NdotL = saturate(dot(N, L));
    float NdotH = saturate(dot(N, H));
    float VdotH = saturate(dot(V, H));

    if (NdotL <= 0.0 || NdotV <= 0.0)
        return float3(0.0, 0.0, 0.0);

    // --- F0 ---
    float3 f0 = F0(albedo, metal);

    // --- Fresnel (Schlick) ---
    float3 F = Fresnel_Schlick(VdotH, f0);

    // --- GGX NDF ---
    float D = GGX_NDF(NdotH, rough);

    // --- Smith GGX Geometry (Schlick-GGX) ---
    float G = SchlickGGX(NdotV, NdotL, rough);

    // --- Single-scattering specular (standard Cook-Torrance) ---
    float3 spec_single = (D * G * F) / (4.0 * NdotL * NdotV + 1e-5);

    // --- Heitz-style multiple scattering ---

    // Directional-hemispherical single-scattering energy
    float Ess = Ess_Approx(rough, f0);
    float Ems = 1.0 - Ess; // energy left for multiple scattering

    // Average Fresnel over microfacets (simple, cheap choice)
    float3 Favg = f0;

    // Broad multiple-scattering lobe (Lambert-like BRDF)
    float3 spec_multi = Ems * Favg * (1.0 / PI);

    // Per-light BRDF -> multiply by NdotL in your lighting loop
    float3 spec = spec_single + spec_multi;

    // --- Diffuse ---
    // Energy-conserving diffuse for dielectrics.
    // Metals (metal=1) naturally get no diffuse.
    float3 kd = (1.0 - F) * (1.0 - metal);
    float3 diff = kd * albedo * (1.0 / PI);

    return diff + spec;
}

#endif
