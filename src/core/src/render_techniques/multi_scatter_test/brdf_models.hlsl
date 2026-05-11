#ifndef BRDF_MODELS_HLSL
#define BRDF_MODELS_HLSL
#include "math/math_constants.hlsl"
#include "materials/material_evaluation.hlsl"

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
    float a2 = ClampAlphaRoughness(a * a);
    float denom = (NdotH * NdotH) * (a2 - 1.0) + 1.0;
    return a2 / (PI * denom * denom);
}
float3 F0(float3 albedo, float metal)
{
    return lerp(float3(0.04, 0.04, 0.04), albedo, metal);
}

float3 Fresnel_Schlick(float VdotH, float3 F0)
{
    float3 F90 = 1.0f.xxx;
    return F0 + (F90 - F0) * pow(1.0f - saturate(abs(VdotH)), 5.0f);
}

float G1_SmithGGX(float NdotX, float alpha)
{
    float a2 = ClampAlphaRoughness(alpha * alpha);
    float cos2 = NdotX * NdotX;
    float tan2 = (1.0 - cos2) / cos2;
    return 2.0 / (1.0 + sqrt(1.0 + a2 * tan2));
}

float G_SmithGGX(float NdotV, float NdotL, float alpha)
{
    return G1_SmithGGX(NdotV, alpha) * G1_SmithGGX(NdotL, alpha);
}

float3 F0_from_IOR(float ior)
{
    float f = (ior - 1.0) / (ior + 1.0);
    return float3(f * f, f * f, f * f);
}


BRDFLobes Cook_Torrance(float3 N, float3 V, float3 L, MaterialBRDF material)
{
    BRDFLobes r;
    r.isMetal = (material.metallicity > 0.5f);
    float3 H = normalize(V + L);
    float rough = material.roughnessAlpha;

    float NdotV = saturate(dot(N, V));
    float NdotL = saturate(dot(N, L));
    float NdotH = saturate(dot(N, H));
    float VdotH = saturate(dot(V, H));

    if (NdotL <= 0.0f || NdotV <= 0.0f)
    {
        r.diffuse_scalar = 0.0f;
        r.specular_shape = 0.0f;
        r.spec_multi_shape = 0.0f;
        r.F0_rgb = material.F0;
        return r;
    }

    // --- F0 ---
    float3 f0 = material.F0;

        // --- Fresnel (Schlick) ---
    float3 F = Fresnel_Schlick(VdotH, f0);

    // --- GGX Normal Distribution ---
    float D = GGX_NDF(NdotH, rough);

    // --- Smith GGX Geometry (Schlick-GGX) ---
    float G = G_SmithGGX(NdotV, NdotL, rough);


    // --- Specular ---
    r.specular_shape = ((D * G ) / (4.0 * NdotL * NdotV + 1e-5));

    // --- Diffuse (energy conserving) ---
    float3 kd = (1.0f.xxx - F) * 1.05 * (1.0f - pow(1.0f - saturate(abs(VdotH)), 5.0f));
    r.diffuse_scalar = kd.r * INV_PI;

    r.spec_multi_shape = 0.0f; // no MS in this model
    r.F0_rgb = f0;
    return r;
}

BRDFLobes Fast_MSX(float3 N, float3 V, float3 L, MaterialBRDF material)
{
    BRDFLobes r;
    r.isMetal = (material.metallicity > 0.5);
    float3 H = normalize(V + L);
    float3 C = normalize(H + N);
    float rough = material.roughnessAlpha;

    float NdotV = saturate(dot(N, V));
    float NdotL = saturate(dot(N, L));
    float NdotH = saturate(dot(N, H));
    float VdotH = saturate(dot(V, H));

    float CosVC = saturate(dot(V, C));
    float ThetaVC = acos(CosVC);
    float ThetaM = (PI - acos(saturate(dot(V, L)))) * 0.25;

    if (NdotL <= 0.0f || NdotV <= 0.0f)
    {
        r.diffuse_scalar = 0.0f;
        r.specular_shape = 0.0f;
        r.spec_multi_shape = 0.0f;
        r.F0_rgb = material.F0;
        return r;
    }

    // --- F0 ---
    float3 f0 = material.F0;

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

    // --- Cook-Torrance Specular ---
    r.specular_shape = ((D * G ) / (4.0 * NdotL * NdotV + 1e-5));

    // --- MSX Specular ---
    r.spec_multi_shape = (DI * GI) / (2.0 * max(1e-4, CosVC));

    // --- Diffuse (energy conserving) ---
    float3 kd = (1.0f.xxx - F) * 1.05 * (1.0f - pow(1.0f - saturate(abs(VdotH)), 5.0f));
    r.diffuse_scalar = kd.r * INV_PI;
    r.F0_rgb = f0;
    return r;
}
float Luminance(float3 c)
{
    return dot(c, float3(0.2126, 0.7152, 0.0722));
}
float Ess_Approx(float rough, float3 f0)
{
    float a = ClampAlphaRoughness(rough * rough);
    float F0_lum = Luminance(f0); // Base term: smoother surfaces keep more energy in single scattering 

    float Ess = 1.0 - a * (0.6 + 0.4 * F0_lum); 
    return saturate(Ess); 
}

BRDFLobes Heitz(float3 N, float3 V, float3 L, MaterialBRDF material)
{
    BRDFLobes r;
    r.isMetal = (material.metallicity > 0.5);
    float3 H = normalize(V + L);
    float rough = material.roughnessAlpha;

    float NdotV = saturate(dot(N, V));
    float NdotL = saturate(dot(N, L));
    float NdotH = saturate(dot(N, H));
    float VdotH = saturate(dot(V, H));

    if (NdotL <= 0.0 || NdotV <= 0.0)
    {
        r.diffuse_scalar = 0.0;
        r.specular_shape = 0.0;
        r.spec_multi_shape = 0.0;
        r.F0_rgb = material.F0;
        return r;
    }

    // --- F0 ---
    float3 f0 = material.F0;

    // --- Fresnel (Schlick) ---
    float3 F = Fresnel_Schlick(VdotH, f0);

    // --- GGX NDF ---
    float D = GGX_NDF(NdotH, rough);

    // --- Smith GGX Geometry (Schlick-GGX) ---
    float G = SchlickGGX(NdotV, NdotL, rough);

    // --- Single-scattering specular (standard Cook-Torrance) ---
    r.specular_shape = (D * G ) / (4.0 * NdotL * NdotV + 1e-5);

    // --- Heitz-style multiple scattering ---

    // Directional-hemispherical single-scattering energy
    float Ess = Ess_Approx(rough, f0);
    float Ems = 1.0 - Ess; // energy left for multiple scattering

    // Average Fresnel over microfacets (simple, cheap choice)

    // Broad multiple-scattering lobe (Lambert-like BRDF)
    r.spec_multi_shape = Ems * INV_PI;

    // Per-light BRDF -> multiply by NdotL in your lighting loop
    r.F0_rgb = f0;
    // --- Diffuse ---
    // Energy-conserving diffuse for dielectrics.
    // Metals (metal=1) naturally get no diffuse.
    float3 kd = (1.0f.xxx - F) * 1.05 * (1.0f - pow(1.0f - saturate(abs(VdotH)), 5.0f));
    r.diffuse_scalar = kd.r * INV_PI;

    return r;
}
float P22_StudentT(float sx, float sy, float alpha, float gamma)
{
    float r2 = sx*sx + sy*sy; 
    float num = gamma - 1.0;
    float denom = (gamma - 1.0) + r2 / (alpha * alpha);

    float base = num / denom;
    return pow(base, gamma) / (PI * alpha * alpha);
}
float D_StudentT(float3 H_local, float alpha, float gamma)
{
    float hz = H_local.z;
    if (hz <= 0.0) return 0.0;

    float sx = H_local.x / hz;
    float sy = H_local.y / hz;

    float P = P22_StudentT(sx, sy, alpha, gamma);
    return P / (hz * hz * hz);
}

float auxF(float u, float g)
{
    return atan(2.00141 - 1.6253863790572571 * g) *
           sin(0.993127 * (-1.00658 + u -
                (0.0209307 * (-2.63062 + g) * u) / (2.19417 + g)) * tan(u));
}

float auxF2(float x, float g)
{
    float u = x / sqrt(1.0 + x * x);
    float num = auxF(u, g);
    float den = 1.0 - u;
    return 1.0 + 1.0 / max(1e-6, num / max(1e-6, den));
}
float roughness_i(float3 wi_local, float alpha)
{
    return sqrt(alpha);
}

float G1_StudentT(float3 wi_local, float alpha, float gamma)
{
    float u = wi_local.z; // cos(theta_i)
    if (u > 0.9999) return 1.0;
    if (u <= 0.0) return 0.0;

    float a_i = alpha; // isotropic
    float theta = acos(u);
    float x = 1.0 / tan(theta) / max(1e-4, a_i);

    return 0.5 * u * auxF2(x, gamma);
}

float G_StudentT(float3 V_local, float3 L_local,
                 float alpha, float gamma)
{
    float Gv = G1_StudentT(V_local,alpha, gamma);
    float Gl = G1_StudentT(L_local, alpha, gamma);
    return Gv * Gl;
}
BRDFLobes StudentT_BRDF(float3 N, float3 V, float3 L,
    MaterialBRDF material)
{
    BRDFLobes r;
    r.isMetal = (material.metallicity > 0.5);
    float3 H = normalize(V + L);
    material.gamma = 3.0; // tail heaviness parameter, controls the "sharpness of the distribution's tails
    float alpha = material.roughnessAlpha; // isotropic
    float3 any = abs(N.z) < 0.999 ? float3(0, 0, 1) : float3(1, 0, 0);
    float3 T = normalize(cross(any, N));
    float3 B = cross(N, T);
    float3 V_local = float3(dot(V, T), dot(V, B), dot(V, N));
    float3 L_local = float3(dot(L, T), dot(L, B), dot(L, N));
    float3 H_local = float3(dot(H, T), dot(H, B), dot(H, N));

    float NdotV = saturate(dot(N, V));
    float NdotL = saturate(dot(N, L));
    float NdotH = saturate(dot(N, H));
    float VdotH = saturate(dot(V, H));

    if (NdotV <= 0.0 || NdotL <= 0.0)
    {
        r.diffuse_scalar = 0.0;
        r.specular_shape = 0.0;
        r.spec_multi_shape = 0.0;
        r.F0_rgb = material.F0;
        return r;
    }
    float3 F0 = material.F0;;
    // Fresnel
    float3 F = Fresnel_Schlick(VdotH, F0);

    // NDF from P22
    float D = D_StudentT(H_local, alpha, material.gamma);

    // Geometry from sigma-approx G1
    float G = G_StudentT(V_local, L_local, alpha, material.gamma);

    r.specular_shape = (D * G ) / (4.0 * NdotV * NdotL + 1e-5);

    // reuse of Heitz MS term 
    float rough_iso = 0.5 * (alpha + alpha);
    float Ess = Ess_Approx(rough_iso, F0);
    float Ems = 1.0 - Ess;
    r.spec_multi_shape = Ems * INV_PI;

    r.F0_rgb = F0;
    float3 kd = (1.0f.xxx - F) * 1.05 * (1.0f - pow(1.0f - saturate(abs(VdotH)), 5.0f));
    r.diffuse_scalar = kd.r * INV_PI;

    return r;
}





#endif
