#ifndef BRDF_MODELS_HLSL
#define BRDF_MODELS_HLSL
#include "math/math_constants.hlsl"
#include "materials/material_evaluation.hlsl"
#include "components/random_number_generator/random_number_generator.hlsl"

#define M_PI			3.14159265358979323846f	/* pi */
#define INV_M_PI		0.31830988618379067153f /* 1/pi */
#define M_PI_2			1.57079632679489661923f	/* pi/2 */
#define SQRT_M_PI		1.77245385090551602729f /* sqrt(pi) */
#define SQRT_2			1.41421356237309504880f /* sqrt(2) */
#define INV_SQRT_M_PI	0.56418958354775628694f /* 1/sqrt(pi) */
#define INV_2_SQRT_M_PI	0.28209479177387814347f /* 0.5/sqrt(pi) */
#define INV_SQRT_2_M_PI 0.3989422804014326779f /* 1/sqrt(2*pi) */
#define INV_SQRT_2		0.7071067811865475244f /* 1/sqrt(2) */

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

float3 FresnelSchlick(float VdotH, float3 F0)
{
    float3 F90 = 1.0f.xxx;
    return F0 + (F90 - F0) * pow(1.0f - saturate(abs(VdotH)), 5.0f);
}

float G1SmithGGX(float NdotX, float alpha)
{
    float a2 = ClampAlphaRoughness(alpha * alpha);
    float cos2 = NdotX * NdotX;
    float tan2 = (1.0 - cos2) / cos2;
    return 2.0 / (1.0 + sqrt(1.0 + a2 * tan2));
}

float GSmithGGX(float NdotV, float NdotL, float alpha)
{
    return G1SmithGGX(NdotV, alpha) * G1SmithGGX(NdotL, alpha);
}

float3 F0FromIOR(float ior)
{
    float f = (ior - 1.0) / (ior + 1.0);
    return float3(f * f, f * f, f * f);
}


BRDFLobes CookTorrance(float3 N, float3 V, float3 L, MaterialBRDF material)
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
        r.diffuseShape = 0.0f;
        r.specularSingleShape = 0.0f;
        r.specularMultiShape = 0.0f;
        r.F0Rgb = material.F0;
        return r;
    }

    // --- F0 ---
    float3 f0 = material.F0;

        // --- Fresnel (Schlick) ---
    float3 F = FresnelSchlick(VdotH, f0);

    // --- GGX Normal Distribution ---
    float D = GGX_NDF(NdotH, rough);

    // --- Smith GGX Geometry (Schlick-GGX) ---
    float G = GSmithGGX(NdotV, NdotL, rough);


    // --- Specular ---
    r.specularSingleShape = ((D * G ) / (4.0 * NdotL * NdotV + 1e-5));

    // --- Diffuse (energy conserving) ---
    float3 kd = (1.0f.xxx - F) * 1.05 * (1.0f - pow(1.0f - saturate(abs(VdotH)), 5.0f));
    r.diffuseShape = kd.r * INV_PI;

    r.specularMultiShape = 0.0f; // no MS in this model
    r.F0Rgb = f0;
    return r;
}

BRDFLobes FastMSX(float3 N, float3 V, float3 L, MaterialBRDF material)
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
        r.diffuseShape = 0.0f;
        r.specularSingleShape = 0.0f;
        r.specularMultiShape = 0.0f;
        r.F0Rgb = material.F0;
        return r;
    }

    // --- F0 ---
    float3 f0 = material.F0;

        // --- Fresnel (Schlick) ---
    float3 F = FresnelSchlick(VdotH, f0);

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
    r.specularSingleShape = ((D * G ) / (4.0 * NdotL * NdotV + 1e-5));

    // --- MSX Specular ---
    r.specularMultiShape = (DI * GI) / (2.0 * max(1e-4, CosVC));

    // --- Diffuse (energy conserving) ---
    float3 kd = (1.0f.xxx - F) * 1.05 * (1.0f - pow(1.0f - saturate(abs(VdotH)), 5.0f));
    r.diffuseShape = kd.r * INV_PI;
    r.F0Rgb = f0;
    return r;
}

bool IsFiniteNumber(float x)
{
    return (x <= FLT_MAX && x >= -FLT_MAX);
}

float erfApprox(float x)
{
    // constants
    const float a1 = 0.254829592f;
    const float a2 = -0.284496736f;
    const float a3 = 1.421413741f;
    const float a4 = -1.453152027f;
    const float a5 = 1.061405429f;
    const float p = 0.3275911f;

    // Save the sign
    float sign = (x < 0.0f) ? -1.0f : 1.0f;
    x = abs(x);

    // A&S formula 7.1.26
    float t = 1.0f / (1.0f + p * x);
    float y = 1.0f - (((((a5 * t + a4) * t + a3) * t + a2) * t + a1) * t * exp(-x * x));

    return sign * y;
}

float erfinvApprox(float x)
{
    // Clamp domain to avoid NaNs
    x = clamp(x, -0.999999f, 0.999999f);

    // Approximation from Mike Giles (2010)
    float w = -log((1.0f - x) * (1.0f + x));
    float p;

    if (w < 5.000000f)
    {
        w = w - 2.500000f;
        p = 2.81022636e-08f;
        p = 3.43273939e-07f + p * w;
        p = -3.52338770e-06f + p * w;
        p = -4.39150654e-06f + p * w;
        p = 0.00021858087f + p * w;
        p = -0.00125372503f + p * w;
        p = -0.00417768164f + p * w;
        p = 0.246640727f + p * w;
        p = 1.50140941f + p * w;
    }
    else
    {
        w = sqrt(w) - 3.000000f;
        p = -0.000200214257f;
        p = 0.000100950558f + p * w;
        p = 0.00134934322f + p * w;
        p = -0.00367342844f + p * w;
        p = 0.00573950773f + p * w;
        p = -0.00762246130f + p * w;
        p = 0.00943887047f + p * w;
        p = 1.00167406f + p * w;
        p = 2.83297682f + p * w;
    }

    return p * x;
}

// Gamma/Beta approximations (used in dielectric refraction G2)
float abgam(float x)
{
    float gam0 = 1.0 / 12.0;
    float gam1 = 1.0 / 30.0;
    float gam2 = 53.0 / 210.0;
    float gam3 = 195.0 / 371.0;
    float gam4 = 22999.0 / 22737.0;
    float gam5 = 29944523.0 / 19733142.0;
    float gam6 = 109535241009.0 / 48264275462.0;

    float temp =
        0.5 * log(2.0 * M_PI) - x + (x - 0.5) * log(x) +
        gam0 / (x + gam1 / (x + gam2 / (x + gam3 / (x + gam4 /
        (x + gam5 / (x + gam6 / x))))));

    return temp;
}

float gammaFunc(float x)
{
    float result = exp(abgam(x + 5.0)) / (x * (x + 1.0) * (x + 2.0) * (x + 3.0) * (x + 4.0));
    return result;
}

float betaFunc(float m, float n)
{
    return gammaFunc(m) * gammaFunc(n) / gammaFunc(m + n);
}

/************* MICROSURFACE HEIGHT DISTRIBUTION *************/

float heightUniformP1(float h)
{
    return (h >= -1.0f && h <= 1.0f) ? 0.5f : 0.0f;
}

float heightUniformC1(float h)
{
    return saturate(0.5f * (h + 1.0f));
}

float heightUniformInvC1(float u)
{
    return clamp(2.0f * u - 1.0f, -1.0f, 1.0f);
}

float heightGaussianP1(float h)
{
    return INV_SQRT_2_M_PI * exp(-0.5f * h * h);
}

float heightGaussianC1(float h)
{
    return 0.5f + 0.5f * erfApprox(INV_SQRT_2 * h);
}

float heightGaussianInvC1(float u)
{
    float x = 2.0f * u - 1.0f; // map U ∈ [0,1] → x ∈ [-1,1]
    return SQRT_2 * erfinvApprox(x);
}

/************* MICROSURFACE SLOPE DISTRIBUTION *************/

float slopeAlphaI(float3 wi, float alphaX, float alphaY)
{
    float invSinTheta2 = 1.0f / (1.0f - wi.z * wi.z);
    float cosPhi2 = wi.x * wi.x * invSinTheta2;
    float sinPhi2 = wi.y * wi.y * invSinTheta2;

    return sqrt(cosPhi2 * alphaX * alphaX +
                sinPhi2 * alphaY * alphaY);
}

float slopeBeckmannP22(float slopeX, float slopeY, float alphaX, float alphaY)
{
    float ax2 = alphaX * alphaX;
    float ay2 = alphaY * alphaY;

    float exponent = -(slopeX * slopeX) / ax2 - (slopeY * slopeY) / ay2;

    return (1.0f / (PI * alphaX * alphaY)) * exp(exponent);
}

float slopeBeckmannLambda(float3 wi, float alphaX, float alphaY)
{
    // Handle near-normal incidence
    if (wi.z > 0.9999f)
        return 0.0f;

    // Handle near-grazing from below
    if (wi.z < -0.9999f)
        return -1.0f;

    // Compute directional roughness α_i
    float alphaI = slopeAlphaI(wi, alphaX, alphaY);

    // a = cot(theta_i) / alpha_i
    float theta_i = acos(wi.z);
    float a = 1.0f / tan(theta_i) / alphaI;

    // Smith's Lambda for Beckmann
    float erf_a = erfApprox(a);
    float value = 0.5f * (erf_a - 1.0f) + INV_2_SQRT_M_PI * exp(-a * a) / a;

    return value;
}

float slopeBeckmannProjectedArea(float3 wi, float alphaX, float alphaY)
{
    // Near-normal incidence
    if (wi.z > 0.9999f)
        return 1.0f;

    // Near-grazing from below
    if (wi.z < -0.9999f)
        return 0.0f;

    // Directional roughness α_i
    float alphaI = slopeAlphaI(wi, alphaX, alphaY);

    // Angles
    float thetaI = acos(wi.z);

    // a = cot(theta_i) / α_i
    float a = 1.0f / tan(thetaI) / alphaI;

    // Projected area A(wi)
    float erf_a = erfApprox(a);
    float value =
        0.5f * (erf_a + 1.0f) * wi.z +
        INV_2_SQRT_M_PI * alphaI * sin(thetaI) * exp(-a * a);

    return value;
}

float2 slopeBeckmannSampleP22_11(float thetaI, float u, float u2)
{
    float2 slope;

    // Special case: normal incidence
    if (thetaI < 0.0001f)
    {
        float r = sqrt(-log(u));
        float phi = 6.28318530718f * u2;
        slope.x = r * cos(phi);
        slope.y = r * sin(phi);
        return slope;
    }

    // Constants
    float sinThetaI = sin(thetaI);
    float cosThetaI = cos(thetaI);

    // Slope corresponding to theta_i
    float slopeI = cosThetaI / sinThetaI;

    // Projected area A(wi)
    float a = slopeI;
    float erfA = erfApprox(a);

    float projectedArea =
        0.5f * (erfA + 1.0f) * cosThetaI +
        INV_2_SQRT_M_PI * sinThetaI * exp(-a * a);

    if (projectedArea < 0.0001f || projectedArea != projectedArea)
        return float2(0.0f, 0.0f);

    // VNDF normalization factor
    float c = 1.0f / projectedArea;

    // Root-finding in erf-domain
    float erfMin = -0.9999f;
    float erfMax = max(erfMin, erfApprox(slopeI));
    float erfCurrent = 0.5f * (erfMin + erfMax);

    while (erfMax - erfMin > 0.00001f)
    {
        if (!(erfCurrent >= erfMin && erfCurrent <= erfMax))
            erfCurrent = 0.5f * (erfMin + erfMax);

        // Evaluate slope from erf
        float slopeVal = erfinvApprox(erfCurrent);

        // CDF(slope)
        float CDF =
            (slopeVal >= slopeI)
            ? 1.0f
            : c * (INV_2_SQRT_M_PI * sinThetaI * exp(-slopeVal * slopeVal) +
                   cosThetaI * (0.5f + 0.5f * erfApprox(slopeVal)));

        float diff = CDF - u;

        if (abs(diff) < 0.00001f)
            break;

        // Update bounds
        if (diff > 0.0f)
        {
            if (erfMax == erfCurrent)
                break;
            erfMax = erfCurrent;
        }
        else
        {
            if (erfMin == erfCurrent)
                break;
            erfMin = erfCurrent;
        }

        // Newton update
        float derivative =
            0.5f * c * cosThetaI -
            0.5f * c * sinThetaI * slopeVal;

        erfCurrent -= diff / derivative;
    }

    // Final slopes
    slope.x = erfinvApprox(clamp(erfCurrent, erfMin, erfMax));
    slope.y = erfinvApprox(2.0f * u2 - 1.0f);

    return slope;
}

float slopeGGX_P22(float slopeX, float slopeY, float alphaX, float alphaY)
{
    float tmp = 1.0f +
        slopeX * slopeX / (alphaX * alphaX) +
        slopeY * slopeY / (alphaY * alphaY);

    return 1.0f / (M_PI * alphaX * alphaY * tmp * tmp);
}

float slopeGGXLambda(float3 wi, float alphaX, float alphaY)
{
    if (wi.z > 0.9999f)
        return 0.0f;
    if (wi.z < -0.9999f)
        return -1.0f;

    float thetaI = acos(wi.z);
    float alphaI = slopeAlphaI(wi, alphaX, alphaY);
    float a = 1.0f / tan(thetaI) / alphaI;

    float value = 0.5f * (-1.0f + sign(a) * sqrt(1.0f + 1.0f / (a * a)));
    return value;
}

float slopeGGXProjectedArea(float3 wi, float alphaX, float alphaY)
{
    if (wi.z > 0.9999f)
        return 1.0f;
    if (wi.z < -0.9999f)
        return 0.0f;

    float thetaI = acos(wi.z);
    float sinThetaI = sin(thetaI);
    float alphaI = slopeAlphaI(wi, alphaX, alphaY);

    float value = 0.5f * (wi.z + sqrt(wi.z * wi.z + sinThetaI * sinThetaI * alphaI * alphaI));
    return value;
}

float2 slopeGGXsampleP22_11(float thetaI, float u, float u2)
{
    float2 slope;

    if (thetaI < 0.0001f)
    {
        float r = sqrt(u / (1.0f - u));
        float phi = 6.28318530718f * u2;
        slope.x = r * cos(phi);
        slope.y = r * sin(phi);
        return slope;
    }

    float sinThetaI = sin(thetaI);
    float cosThetaI = cos(thetaI);
    float tanThetaI = sinThetaI / cosThetaI;

    float slopeI = cosThetaI / sinThetaI;

    float projectedArea = 0.5f * (cosThetaI + 1.0f);
    if (projectedArea < 0.0001f || projectedArea != projectedArea)
        return float2(0.0f, 0.0f);

    float c = 1.0f / projectedArea;

    float A = 2.0f * u / cosThetaI / c - 1.0f;
    float B = tanThetaI;
    float tmp = 1.0f / (A * A - 1.0f);

    float D = sqrt(max(0.0f, B * B * tmp * tmp - (A * A - B * B) * tmp));
    float slopeX1 = B * tmp - D;
    float slopeX2 = B * tmp + D;
    slope.x = (A < 0.0f || slopeX2 > 1.0f / tanThetaI) ? slopeX1 : slopeX2;

    float u2Local;
    float S;
    if (u2 > 0.5f)
    {
        S = 1.0f;
        u2Local = 2.0f * (u2 - 0.5f);
    }
    else
    {
        S = -1.0f;
        u2Local = 2.0f * (0.5f - u2);
    }

    float z = (u2Local * (u2Local * (u2Local * 0.27385f - 0.73369f) + 0.46341f)) /
              (u2Local * (u2Local * (u2Local * 0.093073f + 0.309420f) - 1.000000f) + 0.597999f);

    slope.y = S * z * sqrt(1.0f + slope.x * slope.x);

    return slope;
}


float slopeD(float3 wm, float alphaX, float alphaY, bool beckmann)
{
    // slope of wm
    float slopeX = -wm.x / wm.z;
    float slopeY = -wm.y / wm.z;

    float p22 = beckmann ? slopeBeckmannP22(slopeX, slopeY, alphaX, alphaY) : slopeGGX_P22(slopeX, slopeY, alphaX, alphaY);

    return p22 / (wm.z * wm.z * wm.z);
}

float slopeDwi(float3 wi, float3 wm, float alphaX, float alphaY, bool beckmann)
{
    if (wm.z <= 0.0f)
        return 0.0f;

    // Normalization coefficient
    float projectedArea = beckmann ? slopeBeckmannProjectedArea(wi, alphaX, alphaY) : slopeGGXProjectedArea(wi, alphaX, alphaY);
    if (projectedArea == 0.0f)
        return 0.0f;

    float c = 1.0f / projectedArea;

    // Visible NDF value
    float value = c * max(0.0f, dot(wi, wm)) * slopeD(wm, alphaX, alphaY, beckmann);
    return value;
}

float3 slopeSampleDwi(float3 wi, float u1, float u2, float alphaX, float alphaY, bool beckmann)
{
    // Stretch to isotropic configuration (alpha = 1)
    float3 wi_11 = normalize(float3(alphaX * wi.x, alphaY * wi.y, wi.z));

    // Sample visible slopes for alpha = 1
    float theta = acos(wi_11.z);
    float2 slope_11 = beckmann ? slopeBeckmannSampleP22_11(theta, u1, u2) : slopeGGXsampleP22_11(theta, u1, u2);

    // Rotate slopes to align with wi_11
    float phi = atan2(wi_11.y, wi_11.x);
    float cosPhi = cos(phi);
    float sinPhi = sin(phi);

    float2 slope;
    slope.x = cosPhi * slope_11.x - sinPhi * slope_11.y;
    slope.y = sinPhi * slope_11.x + cosPhi * slope_11.y;

    // Unstretch back to anisotropic space
    slope.x *= alphaX;
    slope.y *= alphaY;

    // Numerical stability fallback
    if (!isfinite(slope.x) || slope.x != slope.x)
    {
        if (wi.z > 0.0f)
            return float3(0.0f, 0.0f, 1.0f);
        else
            return normalize(float3(wi.x, wi.y, 0.0f));
    }

    // Convert slope → microfacet normal
    float3 wm = normalize(float3(-slope.x, -slope.y, 1.0f));
    return wm;
}

float slopeLambda(float3 wi, float alphaX, float alphaY, bool beckmann)
{
    return beckmann
        ? slopeBeckmannLambda(wi, alphaX, alphaY)
        : slopeGGXLambda(wi, alphaX, alphaY);
}

/************* MICROSURFACE *************/

float microsurfaceG1(float3 wi, float alphaX, float alphaY, bool beckmann)
{
    if (wi.z > 0.9999f)
        return 1.0f;
    if (wi.z <= 0.0f)
        return 0.0f;

    float Lambda = slopeLambda(wi, alphaX, alphaY, beckmann);
    return 1.0f / (1.0f + Lambda);
}

float microsurfaceG1Height(float3 wi, float h0,
                             bool heightUniform,
                             float alphaX, float alphaY, bool beckmann)
{
    if (wi.z > 0.9999f)
        return 1.0f;
    if (wi.z <= 0.0f)
        return 0.0f;

    float C1_h0 = heightUniform ? heightUniformC1(h0) : heightGaussianC1(h0);
    float Lambda = slopeLambda(wi, alphaX, alphaY, beckmann);

    return pow(C1_h0, Lambda);
}

float microsurfaceSampleHeight(float3 wr, float hr, float u, bool heightUniform, float alphaX, float alphaY, bool beckmann)
{
    if (wr.z > 0.9999f)
        return FLT_MAX;

    if (wr.z < -0.9999f)
    {
        float C1Hr = heightUniform ? heightUniformC1(hr) : heightGaussianC1(hr);
        float h = heightUniform
            ? heightUniformInvC1(u * C1Hr)
            : heightGaussianInvC1(u * C1Hr);
        return h;
    }

    if (abs(wr.z) < 0.0001f)
        return hr;

    float G1 = microsurfaceG1Height(wr, hr, heightUniform, alphaX, alphaY, beckmann);

    if (u > 1.0f - G1)
        return FLT_MAX;

    float C1Hr = heightUniform ? heightUniformC1(hr) : heightGaussianC1(hr);
    float Lambda = slopeLambda(wr, alphaX, alphaY, beckmann);

    float invArg = C1Hr / pow((1.0f - u), 1.0f / Lambda);

    float h = heightUniform
        ? heightUniformInvC1(invArg)
        : heightGaussianInvC1(invArg);

    return h;
}

float conductorEvalPhaseFunction(float3 wi, float3 wo, float alphaX, float alphaY, bool beckmann)
{
    float3 wh = normalize(wi + wo);
    if (wh.z < 0.0f)
        return 0.0f;

    float Dwi = slopeDwi(wi, wh, alphaX, alphaY, beckmann);
    return 0.25f * Dwi / dot(wi, wh);
}

float3 conductorSamplePhaseFunction(float3 wi, float2 u, float alphaX, float alphaY, bool beckmann)
{
    float3 wm = slopeSampleDwi(wi, u.x, u.y, alphaX, alphaY, beckmann);
    float3 wo = -wi + 2.0f * wm * dot(wi, wm);
    return wo;
}

float conductorEvalSingleScattering(float3 wi, float3 wo, float alphaX, float alphaY, bool beckmann)
{
    float3 wh = normalize(wi + wo);
    float D = slopeD(wh, alphaX, alphaY, beckmann);

    float LambdaI = slopeLambda(wi, alphaX, alphaY, beckmann);
    float LambdaO = slopeLambda(wo, alphaX, alphaY, beckmann);
    float G2 = 1.0f / (1.0f + LambdaI + LambdaO);

    return D * G2 / (4.0f * wi.z);
}

float3 dielectricRefract(float3 wi, float3 wm, float eta)
{
    float cosThetaI = dot(wi, wm);
    float cosThetaT2 = 1.0f - (1.0f - cosThetaI * cosThetaI) / (eta * eta);
    float cosThetaT = -sqrt(max(0.0f, cosThetaT2));

    return wm * (dot(wi, wm) / eta + cosThetaT) - wi / eta;
}

float dielectricFresnel(float3 wi, float3 wm, float eta)
{
    float cosThetaI = dot(wi, wm);
    float cosThetaT2 = 1.0f - (1.0f - cosThetaI * cosThetaI) / (eta * eta);

    if (cosThetaT2 <= 0.0f)
        return 1.0f;

    float cos_theta_t = sqrt(cosThetaT2);

    float Rs = (cosThetaI - eta * cos_theta_t) / (cosThetaI + eta * cos_theta_t);
    float Rp = (eta * cosThetaI - cos_theta_t) / (eta * cosThetaI + cos_theta_t);

    return 0.5f * (Rs * Rs + Rp * Rp);
}

float dielectricEvalPhaseFunctionCore(float3 wi, float3 wo, bool wiOutside, bool woOutside, float alphaX, float alphaY, bool beckmann, float eta)
{
    float etaLocal = wiOutside ? eta : 1.0f / eta;

    if (wiOutside == woOutside)
    {
        float3 wh = normalize(wi + wo);
        if (!wiOutside)
        {
            wh = -wh;
            wi = -wi;
            wo = -wo;
        }

        float Dwi = slopeDwi(wi, wh, alphaX, alphaY, beckmann);
        float F = dielectricFresnel(wi, wh, etaLocal);

        return 0.25f * Dwi / dot(wi, wh) * F;
    }
    else
    {
        float3 wh = -normalize(wi + wo * etaLocal);
        wh *= wiOutside ? sign(wh.z) : -sign(wh.z);

        if (dot(wh, wi) < 0.0f)
            return 0.0f;

        float value;
        if (wiOutside)
        {
            float F = dielectricFresnel(wi, wh, etaLocal);
            float Dwi = slopeDwi(wi, wh, alphaX, alphaY, beckmann);

            value = etaLocal * etaLocal * (1.0f - F) *
                    Dwi * max(0.0f, -dot(wo, wh)) *
                    1.0f / pow(dot(wi, wh) + etaLocal * dot(wo, wh), 2.0f);
        }
        else
        {
            wi = -wi;
            wo = -wo;
            wh = -wh;

            float F = dielectricFresnel(wi, wh, etaLocal);
            float Dwi = slopeDwi(wi, wh, alphaX, alphaY, beckmann);

            value = etaLocal * etaLocal * (1.0f - F) *
                    Dwi * max(0.0f, -dot(wo, wh)) *
                    1.0f / pow(dot(wi, wh) + etaLocal * dot(wo, wh), 2.0f);
        }

        return value;
    }
}

float dielectricEvalPhaseFunction(float3 wi, float3 wo, float alphaX, float alphaY, bool beckmann, float eta)
{
    return dielectricEvalPhaseFunctionCore(wi, wo, true, true, alphaX, alphaY, beckmann, eta) 
           +
           dielectricEvalPhaseFunctionCore(wi, wo, true, false, alphaX, alphaY, beckmann, eta);
}
template<typename RNG>
float3 dielectricSamplePhaseFunction(float3 wi, RNG rng, bool wiOutside, out bool woOutside, float alphaX, float alphaY, bool beckmann, float eta)
{
    float u1 = rng.rand();
    float u2 = rng.rand();
    float u3 = rng.rand(); // for Fresnel branch
    float etaLocal = wiOutside ? eta : 1.0f / eta;

    float3 wm = wiOutside
        ? slopeSampleDwi(wi, u1, u2, alphaX, alphaY, beckmann)
        : -slopeSampleDwi(-wi, u1, u2, alphaX, alphaY, beckmann);

    float F = dielectricFresnel(wi, wm, etaLocal);

    if (u3 < F)
    {
        float3 wo = -wi + 2.0f * wm * dot(wi, wm);
        woOutside = wiOutside;
        return wo;
    }
    else
    {
        woOutside = !wiOutside;
        float3 wo = dielectricRefract(wi, wm, etaLocal);
        return normalize(wo);
    }
}

float dielectricEvalSingleScattering(float3 wi, float3 wo, float alphaX, float alphaY, bool beckmann, float eta)
{
    bool woOutside = (wo.z > 0.0f);
    bool wiOutside = true;

    if (woOutside)
    {
        float3 wh = normalize(wi + wo);
        float D = slopeD(wh, alphaX, alphaY, beckmann);

        float LambdaI = slopeLambda(wi, alphaX, alphaY, beckmann);
        float LambdaO = slopeLambda(wo, alphaX, alphaY, beckmann);
        float G2 = 1.0f / (1.0f + LambdaI + LambdaO);

        float F = dielectricFresnel(wi, wh, eta);
        return F * D * G2 / (4.0f * wi.z);
    }
    else
    {
        float3 wh = -normalize(wi + wo * eta);
        if (eta < 1.0f)
            wh = -wh;

        float D = slopeD(wh, alphaX, alphaY, beckmann);

        float LambdaI = slopeLambda(wi, alphaX, alphaY, beckmann);
        float LambdaO = slopeLambda(-wo, alphaX, alphaY, beckmann);

        float G2 = (float) betaFunc(1.0f + LambdaI, 1.0f + LambdaO);

        float F = dielectricFresnel(wi, wh, eta);

        float value =
            max(0.0f, dot(wi, wh)) * max(0.0f, -dot(wo, wh)) *
            (1.0f / wi.z) * eta * eta * (1.0f - F) *
            G2 * D / pow(dot(wi, wh) + eta * dot(wo, wh), 2.0f);

        return value;
    }
}

void buildOrthonormalBasis(out float3 omega1, out float3 omega2, float3 omega3)
{
    if (omega3.z < -0.9999999f)
    {
        omega1 = float3(0.0f, -1.0f, 0.0f);
        omega2 = float3(-1.0f, 0.0f, 0.0f);
    }
    else
    {
        float a = 1.0f / (1.0f + omega3.z);
        float b = -omega3.x * omega3.y * a;
        omega1 = float3(1.0f - omega3.x * omega3.x * a, b, -omega3.x);
        omega2 = float3(b, 1.0f - omega3.y * omega3.y * a, -omega3.y);
    }
}

float diffuseEvalPhaseFunction(float3 wi, float3 wo, float2 u, float alphaX, float alphaY, bool beckmann)
{
    float3 wm = slopeSampleDwi(wi, u.x, u.y, alphaX, alphaY, beckmann);
    return INV_M_PI * max(0.0f, dot(wo, wm));
}

float3 diffuseSamplePhaseFunction(float3 wi, float4 u, float alphaX, float alphaY, bool beckmann)
{
    float3 wm = slopeSampleDwi(wi, u.x, u.y, alphaX, alphaY, beckmann);

    float3 w1, w2;
    buildOrthonormalBasis(w1, w2, wm);

    float r1 = 2.0f * u.z - 1.0f;
    float r2 = 2.0f * u.w - 1.0f;

    float phi, r;
    if (r1 == 0.0f && r2 == 0.0f)
    {
        r = 0.0f;
        phi = 0.0f;
    }
    else if (r1 * r1 > r2 * r2)
    {
        r = r1;
        phi = (M_PI / 4.0f) * (r2 / r1);
    }
    else
    {
        r = r2;
        phi = (M_PI / 2.0f) - (r1 / r2) * (M_PI / 4.0f);
    }

    float x = r * cos(phi);
    float y = r * sin(phi);
    float z = sqrt(max(0.0f, 1.0f - x * x - y * y));

    float3 wo = x * w1 + y * w2 + z * wm;
    return wo;
}

float diffuseEvalSingleScattering(float3 wi, float3 wo, float2 u, float alphaX, float alphaY, bool beckmann)
{
    float3 wm = slopeSampleDwi(wi, u.x, u.y, alphaX, alphaY, beckmann);

    float Lambda_i = slopeLambda(wi, alphaX, alphaY, beckmann);
    float Lambda_o = slopeLambda(wo, alphaX, alphaY, beckmann);
    float G2_given_G1 = (1.0f + Lambda_i) / (1.0f + Lambda_i + Lambda_o);

    float value = INV_M_PI * max(0.0f, dot(wm, wo)) * G2_given_G1;
    return value;
}
template<typename RNG>
float3 samplePhaseFunction(float3 wi, bool isConductor, bool isDielectric, float alphaX, float alphaY, bool beckmann, float eta, inout RNG rng)
{
    if (isConductor)
    {
        float2 u = float2(rng.rand(), rng.rand());
        return conductorSamplePhaseFunction(wi, u,
                                            alphaX, alphaY,
                                            beckmann);
    }

    if (isDielectric)
    {
        bool woOutside;
        return dielectricSamplePhaseFunction(wi, rng,
                                             /*wiOutside=*/true,
                                             woOutside,
                                             alphaX, alphaY,
                                             beckmann,
                                             eta);
    }

    // diffuse microsurface
    float4 u = float4(rng.rand(), rng.rand(), rng.rand(), rng.rand());
    return diffuseSamplePhaseFunction(wi, u,
                                      alphaX, alphaY,
                                      beckmann);
}
template<typename RNG>
float3 microsurfaceSample(MaterialBRDF material, float3 wi, out int scatteringOrder, bool heightUniform, float alphaX, float alphaY, bool beckmann, inout RNG randomNG)
{
    // init
    float3 wr = -wi;
    bool isConductor = material.metallicity > 0.5;
    bool isDielectric = !isConductor;

    // initial height (same as C++)
    float hr = 1.0f + (heightUniform ?
                       heightUniformInvC1(0.999f) :
                       heightGaussianInvC1(0.999f));

    scatteringOrder = 0;

    // random walk
    for (;;)
    {
        // next height
        float u = randomNG.rand(); // your RNG
        hr = microsurfaceSampleHeight(wr, hr, u,
                                       heightUniform,
                                       alphaX, alphaY,
                                       beckmann);

        // leave the microsurface?
        if (hr == FLT_MAX)
            break;

        scatteringOrder++;

        // next direction
        wr = samplePhaseFunction(-wr, isConductor, isDielectric, alphaX, alphaY, beckmann, material.ior, randomNG);

        // numerical safety
        if (!isfinite(hr) || !isfinite(wr.z))
            return float3(0, 0, 1);
    }

    return wr;
}


float Luminance(float3 c)
{
    return dot(c, float3(0.2126, 0.7152, 0.0722));
}
float EssApprox(float rough, float3 f0)
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
        r.diffuseShape = 0.0;
        r.specularSingleShape = 0.0;
        r.specularMultiShape = 0.0;
        r.F0Rgb = material.F0;
        return r;
    }

    // --- F0 ---
    float3 f0 = material.F0;

    // --- Fresnel (Schlick) ---
    float3 F = FresnelSchlick(VdotH, f0);

    // --- GGX NDF ---
    float D = GGX_NDF(NdotH, rough);

    // --- Smith GGX Geometry (Schlick-GGX) ---
    float G = SchlickGGX(NdotV, NdotL, rough);

    // --- Single-scattering specular (standard Cook-Torrance) ---
    r.specularSingleShape = (D * G ) / (4.0 * NdotL * NdotV + 1e-5);

    // --- Heitz-style multiple scattering ---

    // Directional-hemispherical single-scattering energy
    float Ess = EssApprox(rough, f0);
    float Ems = 1.0 - Ess; // energy left for multiple scattering

    // Average Fresnel over microfacets (simple, cheap choice)

    // Broad multiple-scattering lobe (Lambert-like BRDF)
    r.specularMultiShape = Ems * INV_PI;

    // Per-light BRDF -> multiply by NdotL in your lighting loop
    r.F0Rgb = f0;
    // --- Diffuse ---
    // Energy-conserving diffuse for dielectrics.
    // Metals (metal=1) naturally get no diffuse.
    float3 kd = (1.0f.xxx - F) * 1.05 * (1.0f - pow(1.0f - saturate(abs(VdotH)), 5.0f));
    r.diffuseShape = kd.r * INV_PI;

    return r;
}
float P22StudentT(float sx, float sy, float alpha, float gamma)
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

    float P = P22StudentT(sx, sy, alpha, gamma);
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
float roughnessI(float3 wi_local, float alpha)
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
        r.diffuseShape = 0.0;
        r.specularSingleShape = 0.0;
        r.specularMultiShape = 0.0;
        r.F0Rgb = material.F0;
        return r;
    }
    float3 F0 = material.F0;;
    // Fresnel
    float3 F = FresnelSchlick(VdotH, F0);

    // NDF from P22
    float D = D_StudentT(H_local, alpha, material.gamma);

    // Geometry from sigma-approx G1
    float G = G_StudentT(V_local, L_local, alpha, material.gamma);

    r.specularSingleShape = (D * G ) / (4.0 * NdotV * NdotL + 1e-5);

    // reuse of Heitz MS term 
    float rough_iso = 0.5 * (alpha + alpha);
    float Ess = EssApprox(rough_iso, F0);
    float Ems = 1.0 - Ess;
    r.specularMultiShape = Ems * INV_PI;

    r.F0Rgb = F0;
    float3 kd = (1.0f.xxx - F) * 1.05 * (1.0f - pow(1.0f - saturate(abs(VdotH)), 5.0f));
    r.diffuseShape = kd.r * INV_PI;

    return r;
}





#endif
