#ifndef BRDF_MODELS_HLSL
#define BRDF_MODELS_HLSL
#include "math/math_constants.hlsl"
#include "materials/material_evaluation.hlsl"

#define M_PI			3.14159265358979323846f	/* pi */
#define INV_M_PI		0.31830988618379067153f /* 1/pi */
#define M_PI_2			1.57079632679489661923f	/* pi/2 */
#define SQRT_M_PI		1.77245385090551602729f /* sqrt(pi) */
#define SQRT_2			1.41421356237309504880f /* sqrt(2) */
#define INV_SQRT_M_PI	0.56418958354775628694f /* 1/sqrt(pi) */
#define INV_2_SQRT_M_PI	0.28209479177387814347f /* 0.5/sqrt(pi) */
#define INV_SQRT_2_M_PI 0.3989422804014326779f /* 1/sqrt(2*pi) */
#define INV_SQRT_2		0.7071067811865475244f /* 1/sqrt(2) */
static const int MS_MAX_STEPS = 64;

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
enum NDFType : uint
{
    NDF_Beckmann = 0,
    NDF_GGX = 1,
    NDF_StudentT = 2
};

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

float slopeGGX_Lambda(float3 wi, float alphaX, float alphaY)
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

float slopeGGX_ProjectedArea(float3 wi, float alphaX, float alphaY)
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

float2 slopeGGX_SampleP22_11(float thetaI, float u, float u2)
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
float deriveGammaFromAlpha(float alpha)
{
    return lerp(4.0f, 2.0f, alpha);
}

float slopeStudentT_P22(float sx, float sy, float alphaX, float alphaY)
{
    float gamma = deriveGammaFromAlpha(alphaX);
    float r2 =
        (sx * sx) / (alphaX * alphaX) +
        (sy * sy) / (alphaY * alphaY);

    float base = (gamma - 1.0) / ((gamma - 1.0) + r2);
    return pow(base, gamma) / (PI * alphaX * alphaY);
}

float auxF(float u, float g)
{
    return atan(2.00141 - 1.6253863790572571 * g) *
           sin(0.993127 *
               (-1.00658 + u -
                (0.0209307 * (-2.63062 + g) * u) / (2.19417 + g)) *
               tan(u));
}

float auxF2(float x, float g)
{
    float u = x / sqrt(1.0 + x * x);
    return 1.0 + 1.0 / erfApprox(auxF(u, g) / (1.0 - u));
}

float slopeStudentT_ProjectedArea(float3 wi, float alphaX, float alphaY)
{
    float gamma = deriveGammaFromAlpha(alphaX);
    float u = wi.z;
    if (u > 0.9999)
        return 1.0;
    if (u < -0.9999)
        return 0.0;

    float alphaI = slopeAlphaI(wi, alphaX, alphaY);

    
    float thetaI = acos(u);
    float x = 1.0 / tan(thetaI) / alphaI;

    if (u > 0.0)
        return 0.5 * u * auxF2(x, gamma);
    else
        return -0.5 * u * auxF2(-x, gamma) + u;
}

float slopeStudentT_Lambda(float3 w, float alphaX, float alphaY)
{
    float a = slopeStudentT_ProjectedArea(w, alphaX, alphaY);
    return max(0.0, a - 1.0);
}



float slopeD(float3 wm, float alphaX, float alphaY, int ndfType)
{
    // slope of wm
    float slopeX = -wm.x / wm.z;
    float slopeY = -wm.y / wm.z;

    float p22;
    switch (ndfType)
    {
        case NDF_StudentT:
            p22 = slopeStudentT_P22(slopeX, slopeY, alphaX, alphaY);
            break;
        case NDF_GGX:
            p22 = slopeGGX_P22(slopeX, slopeY, alphaX, alphaY);
            break;
        case NDF_Beckmann:                           
        default:
            p22 = slopeBeckmannP22(slopeX, slopeY, alphaX, alphaY);
            break;

    }

    return p22 / (wm.z * wm.z * wm.z);
}

float slopeDwi(float3 wi, float3 wm, float alphaX, float alphaY, int ndfType)
{
    if (wm.z <= 0.0f)
        return 0.0f;

    // Normalization coefficient
    float projectedArea;
    switch (ndfType)
    {
        case NDF_StudentT:
            projectedArea = slopeStudentT_ProjectedArea(wi, alphaX, alphaY);
            break;
        case NDF_GGX:
            projectedArea = slopeGGX_ProjectedArea(wi, alphaX, alphaY);
            break;
        case NDF_Beckmann:                                                  
        default:
            projectedArea = slopeBeckmannProjectedArea(wi, alphaX, alphaY);
            break;

    }
    if (projectedArea == 0.0f)
        return 0.0f;

    float c = 1.0f / projectedArea;

    // Visible NDF value
    float value = c * max(0.0f, dot(wi, wm)) * slopeD(wm, alphaX, alphaY, ndfType);
    return value;
}

float3 slopeSampleDwi(float3 wi, float u1, float u2, float alphaX, float alphaY, bool beckmann)
{
    // Stretch to isotropic configuration (alpha = 1)
    float3 wi_11 = normalize(float3(alphaX * wi.x, alphaY * wi.y, wi.z));

    // Sample visible slopes for alpha = 1
    float theta = acos(wi_11.z);
    float2 slope_11 = beckmann ? slopeBeckmannSampleP22_11(theta, u1, u2) : slopeGGX_SampleP22_11(theta, u1, u2);

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
float myGamma(float x)
{
    float result = exp(abgam(x + 5)) / (x * (x + 1) * (x + 2) * (x + 3) * (x + 4));
    return result;
}

float pTerm1(float u, float gamma)
{
    return (3 * sqrt(3 - 3 * pow(u, 2))) /
           (pow(1 + pow(u, 2) / (3 - 3 * pow(u, 2)), 2.5) *
            (8 * u - (81 * pow(-1 + pow(u, 2), 3)) / pow(3 - 2 * pow(u, 2), 2.5) -
             (pow(u, 2) * sqrt(3 - 2 * pow(u, 2)) * sqrt((-1 + pow(u, 2)) / (-3 + 2 * pow(u, 2))) *
              (135 - 210 * pow(u, 2) + 83 * pow(u, 4))) /
                 (pow(-1 + pow(u, 2), 3) * pow((-3 + 2 * pow(u, 2)) / (-1 + pow(u, 2)), 2.5))));
}

float pTerm2(float u, float x)
{
    return pow(u, 0.809494 + 0.170783 / (-1.1224 + x)) /
           (1 + pow(u, 0.145598 + 0.000805627 * x + atan(1.05504 * (-2.91109 + pow(x, 2)))));
}

template<typename RNG>
float NormalSample(inout RNG rng)
{
    float2 u = rng.rand2();
    float r = sqrt(-2.0f * log(max(u.x, 1e-7f)));
    float theta = 6.28318530718f * u.y;
    return r * cos(theta);
}

template<typename RNG>
float RandomGamma(inout RNG rng, float a)
{
    if (!isfinite(a) || a <= 0.0f)
        return 0.0f;

    float boost = 1.0f;
    if (a < 1.0f)
    {
        boost = pow(rng.rand(), 1.0f / a);
        a += 1.0f;
    }

    float d = a - 1.0f / 3.0f;
    if (!isfinite(d) || d <= 0.0f)
        return 0.0f;
    float c = 1.0f / sqrt(9.0f * d);
    if (!isfinite(c))
        return 0.0f;

    for (int i = 0; i < 64; i++)
    {
        float x = NormalSample(rng);
        if (!isfinite(x))
            continue;
        float v = 1.0f + c * x;
        if (v <= 0.0f)
            continue;

        v = v * v * v;
        if (!isfinite(v))
            continue;
        float u = rng.rand();

        if (u < 1.0f - 0.0331f * x * x * x * x)
            return d * v * boost;

        float logu = log(u);
        if (!isfinite(logu))
            continue;
        if (logu < 0.5f * x * x + d * (1.0f - v + log(v)))
            return d * v * boost;
    }

    return d * boost;
}

float asinh_approx(float x)
{
    return log(x + sqrt(x * x + 1.0f));
}

template<typename RNG>
float sampleMPrime(float u, float gamma, inout RNG rng)
{
    if (!isfinite(u) || !isfinite(gamma) || gamma <= 1.0f)
        return 0.0f;

    if (u < 0.0)
    {
        float y = gamma;
        float a = -1.49293 + y - (0.0655156 * (0.0442664 + u)) / (1.20697 + cos(0.633638 + y));
        float c = 1.00448 + (0.0138041 + u) / (-0.850096 - u + 0.516877 * pow(y, 2) - asinh_approx(u));
        if (!isfinite(a) || !isfinite(c) || a <= 0.0f || c <= 0.0f)
            return 0.0f;

        float m1 = (sqrt(-1 + y) * (-3 + 2 * y) * (-6 * pow(PI, 1.5) * u * pow(-1 + y, 3.5) * (-4 + 3 * y) * pow(myGamma(-1 + y), 3) + 4 * (4 * pow(-1 + y, 2) * (-3 + pow(u, 2) + (3 + pow(u, 2)) * y) * pow(myGamma(-0.5 + y), 3) + pow(2, 3 - 2 * y) * PI * u * pow(-1 + y, 2.5) * (-14 + 13 * y) * myGamma(-0.5 + y) * myGamma(-2 + 2 * y) + (pow(PI, 1.5) * (-6 * (-1 + y) * (-4 + 3 * y) + pow(u, 2) * (8 - 5 * pow(y, 2))) * myGamma(y) * myGamma(-1 + 2 * y)) / pow(4, y)))) /
                          (2. * (16 * (pow(u, 2) * (-2 + y) + 3 * (-1 + y)) * pow(-1 + y, 2.5) *
                                     pow(myGamma(-0.5 + y), 3) +
                                 pow(2, 5 - 2 * y) * PI * u * pow(-1 + y, 3) * (-20 + 13 * y) *
                                     myGamma(-0.5 + y) * myGamma(-2 + 2 * y) +
                                 pow(PI, 1.5) * myGamma(y) * (-3 * u * (-3 + 2 * y) * (-4 + 3 * y) * pow(myGamma(y), 2) - pow(2, 3 - 2 * y) * pow(-1 + y, 1.5) * (6 * (-1 + y) * (-4 + 3 * y) + pow(u, 2) * (-2 + y) * (-6 + 5 * y)) * myGamma(-2 + 2 * y))));
        if (!isfinite(m1))
            return 0.0f;

        float ga = myGamma(a);
        float gac = myGamma(a + 1.0f / c);
        if (!isfinite(ga) || !isfinite(gac) || gac == 0.0f)
            return 0.0f;

        float b = m1 * ga / gac;
        if (!isfinite(b))
            return 0.0f;

        float g = RandomGamma(rng, a);
        if (!isfinite(g) || g <= 0.0f)
            return 0.0f;

        float res = pow(g, 1.0f / c) * b;
        return isfinite(res) ? res : 0.0f;
    }

    float xi1 = rng.rand();
    float p1 = pTerm1(u, gamma);
    float p2 = pTerm2(u, gamma);
    if (!isfinite(p1) || !isfinite(p2) || p1 < 0.0f || p2 < 0.0f)
        return 0.0f;

    float denom = (-1.0f + gamma) * (-1.0f + u * u);
    if (!isfinite(denom) || denom == 0.0f)
        return 0.0f;

    float gammaWidth = 1.0f / (1.0f - u * u / denom);
    if (!isfinite(gammaWidth))
        return 0.0f;

    if (xi1 < p1)
    {
        // term 1
        float g = RandomGamma(rng, -1.5f + gamma);
        float res = g * gammaWidth;
        return isfinite(res) ? res : 0.0f;
    }
    else if (xi1 < p1 + p2)
    {
        float g = RandomGamma(rng, gamma - 1.0f);
        return isfinite(g) ? g : 0.0f;
    }
    else
    {
            // term 3
        float m = RandomGamma(rng, gamma - 1.0);
        if (!isfinite(m))
            return 0.0f;
        for (int iter = 0; iter < 64; ++iter)
        {
            float arg = u * sqrt(-(m / ((-1.0f + gamma) * (-1.0f + u * u))));
            if (!isfinite(arg))
                break;
            float acc = erfApprox(arg);
            if (!isfinite(acc))
                break;
            float r = rng.rand();
            if (r <= acc)
                return isfinite(m) ? m : 0.0f;
            m = RandomGamma(rng, gamma - 1.0f);
            if (!isfinite(m))
                break;
        }
        return m;
        
    }

}

template<typename RNG>
float3 slopeStudentT_SampleDwi(float3 wi, float u1, float u2, float alphaX, float alphaY, inout RNG rng)
{
    float gamma = deriveGammaFromAlpha(alphaX);

    if (!isfinite(gamma) || gamma <= 1.0f)
        return float3(0, 0, 1);


    float m_prime = sampleMPrime(wi.z, gamma, rng);

    if (!isfinite(m_prime) || m_prime <= 0.0f)
        return float3(0, 0, 1);
    float denom = m_prime / (gamma - 1.0f);
    if (!isfinite(denom) || denom <= 0.0f)
        return float3(0, 0, 1);


    float beckRough = 1.0f / sqrt(denom);
    if (!isfinite(beckRough) || beckRough <= 0.0f)
        return float3(0, 0, 1);

    float ax = beckRough * alphaX;
    float ay = beckRough * alphaY;

    if (!isfinite(ax) || !isfinite(ay) || ax <= 0.0f || ay <= 0.0f)
        return float3(0, 0, 1);

    // reuse your existing Beckmann visible-normal sampler:
    return slopeSampleDwi(wi, u1, u2, ax, ay, true);
}


float slopeLambda(float3 wi, float alphaX, float alphaY, int ndfType)
{
    switch (ndfType)
    {
        case NDF_StudentT:
            return slopeStudentT_Lambda(wi, alphaX, alphaY);
        case NDF_GGX:
            return slopeGGX_Lambda(wi, alphaX, alphaY);
        case NDF_Beckmann:
        default:
            return slopeBeckmannLambda(wi, alphaX, alphaY);

    }
}

/************* MICROSURFACE *************/

float microsurfaceG1(float3 wi, float alphaX, float alphaY, int ndfType)
{
    if (wi.z > 0.9999f)
        return 1.0f;
    if (wi.z <= 0.0f)
        return 0.0f;

    float Lambda = slopeLambda(wi, alphaX, alphaY, ndfType);
    return 1.0f / (1.0f + Lambda);
}

float microsurfaceG1Height(float3 wi, float h0,
                             bool heightUniform,
                             float alphaX, float alphaY, int ndfType)
{
    if (wi.z > 0.9999f)
        return 1.0f;
    if (wi.z <= 0.0f)
        return 0.0f;

    float C1_h0 = heightUniform ? heightUniformC1(h0) : heightGaussianC1(h0);
    float Lambda = slopeLambda(wi, alphaX, alphaY, ndfType);

    return pow(C1_h0, Lambda);
}

float microsurfaceSampleHeight(float3 wr, float hr, float u, bool heightUniform, float alphaX, float alphaY, int ndfType)
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

    float G1 = microsurfaceG1Height(wr, hr, heightUniform, alphaX, alphaY, ndfType);

    if (u > 1.0f - G1)
        return FLT_MAX;

    float C1Hr = heightUniform ? heightUniformC1(hr) : heightGaussianC1(hr);
    float Lambda = slopeLambda(wr, alphaX, alphaY, ndfType);

    float invArg = C1Hr / pow((1.0f - u), 1.0f / Lambda);

    float h = heightUniform
        ? heightUniformInvC1(invArg)
        : heightGaussianInvC1(invArg);

    return h;
}

float conductorEvalPhaseFunction(float3 wi, float3 wo, float alphaX, float alphaY, int ndfType)
{
    float3 wh = normalize(wi + wo);
    if (wh.z < 0.0f)
        return 0.0f;

    float Dwi = slopeDwi(wi, wh, alphaX, alphaY, ndfType);
    return 0.25f * Dwi / dot(wi, wh);
}

template<typename RNG>
float3 conductorSamplePhaseFunction(float3 wi, float2 u, float alphaX, float alphaY, int ndfType, inout RNG rng)
{
    float3 wm;
    switch (ndfType)
    {
        case NDF_StudentT:
            wm = slopeStudentT_SampleDwi(wi, u.x, u.y, alphaX, alphaY, rng);
            break;
        case NDF_GGX:
            wm = slopeSampleDwi(wi, u.x, u.y, alphaX, alphaY, false);
            break;
        case NDF_Beckmann:
        default:
            wm = slopeSampleDwi(wi, u.x, u.y, alphaX, alphaY, true);
            break;
    }

    float3 wo = -wi + 2.0f * wm * dot(wi, wm);
    return wo;
}

float conductorEvalSingleScattering(float3 wi, float3 wo, float alphaX, float alphaY, int ndfType)
{
    float3 wh = normalize(wi + wo);
    float D = slopeD(wh, alphaX, alphaY, ndfType);

    float LambdaI = slopeLambda(wi, alphaX, alphaY, ndfType);
    float LambdaO = slopeLambda(wo, alphaX, alphaY, ndfType);
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

float dielectricEvalPhaseFunctionCore(float3 wi, float3 wo, bool wiOutside, bool woOutside, float alphaX, float alphaY, int ndfType, float eta)
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

        float Dwi = slopeDwi(wi, wh, alphaX, alphaY, ndfType);
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
            float Dwi = slopeDwi(wi, wh, alphaX, alphaY, ndfType);

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
            float Dwi = slopeDwi(wi, wh, alphaX, alphaY, ndfType);

            value = etaLocal * etaLocal * (1.0f - F) *
                    Dwi * max(0.0f, -dot(wo, wh)) *
                    1.0f / pow(dot(wi, wh) + etaLocal * dot(wo, wh), 2.0f);
        }

        return value;
    }
}

float dielectricEvalPhaseFunction(float3 wi, float3 wo, float alphaX, float alphaY, int ndfType, float eta)
{
    return dielectricEvalPhaseFunctionCore(wi, wo, true, true, alphaX, alphaY, ndfType, eta)
           +
           dielectricEvalPhaseFunctionCore(wi, wo, true, false, alphaX, alphaY, ndfType, eta);
}
template<typename RNG>
float3 dielectricSamplePhaseFunction(float3 wi, inout RNG rng, bool wiOutside, out bool woOutside, float alphaX, float alphaY, int ndfType, float eta)
{
    float u1 = rng.rand();
    float u2 = rng.rand();
    float u3 = rng.rand(); // for Fresnel branch
    float etaLocal = wiOutside ? eta : 1.0f / eta;

    float3 wm;
    if (wiOutside)
    {
        switch (ndfType)
        {
            case NDF_StudentT:
                wm = slopeStudentT_SampleDwi(wi, u1, u2, alphaX, alphaY, rng);
                break;

            case NDF_GGX:
                wm = slopeSampleDwi(wi, u1, u2, alphaX, alphaY, false);
                break;

            case NDF_Beckmann:
            default:
                wm = slopeSampleDwi(wi, u1, u2, alphaX, alphaY, true);
                break;
        }
    }
    else
    {
        switch (ndfType)
        {
            case NDF_StudentT:
                wm = -slopeStudentT_SampleDwi(-wi, u1, u2, alphaX, alphaY, rng);
                break;

            case NDF_GGX:
                wm = -slopeSampleDwi(-wi, u1, u2, alphaX, alphaY, false);
                break;

            case NDF_Beckmann:
            default:
                wm = -slopeSampleDwi(-wi, u1, u2, alphaX, alphaY, true);
                break;
        }
    }

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

float dielectricEvalSingleScattering(float3 wi, float3 wo, float alphaX, float alphaY, int ndfType, float eta)
{
    bool woOutside = (wo.z > 0.0f);
    bool wiOutside = true;

    if (woOutside)
    {
        float3 wh = normalize(wi + wo);
        float D = slopeD(wh, alphaX, alphaY, ndfType);

        float LambdaI = slopeLambda(wi, alphaX, alphaY, ndfType);
        float LambdaO = slopeLambda(wo, alphaX, alphaY, ndfType);
        float G2 = 1.0f / (1.0f + LambdaI + LambdaO);

        float F = dielectricFresnel(wi, wh, eta);
        return F * D * G2 / (4.0f * wi.z);
    }
    else
    {
        float3 wh = -normalize(wi + wo * eta);
        if (eta < 1.0f)
            wh = -wh;

        float D = slopeD(wh, alphaX, alphaY, ndfType);

        float LambdaI = slopeLambda(wi, alphaX, alphaY, ndfType);
        float LambdaO = slopeLambda(-wo, alphaX, alphaY, ndfType);

        float G2 = betaFunc(1.0f + LambdaI, 1.0f + LambdaO);

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

template<typename RNG>
float diffuseEvalPhaseFunction(float3 wi, float3 wo, float2 u, float alphaX, float alphaY, int ndfType, inout RNG rng)
{
    float3 wm;
    switch (ndfType)
    {
        case NDF_StudentT:
        {
                wm = slopeStudentT_SampleDwi(wi, u.x, u.y, alphaX, alphaY, rng);
                break;
        }
        case NDF_GGX:
        {
                wm = slopeSampleDwi(wi, u.x, u.y, alphaX, alphaY, false);
                break;
        }
        case NDF_Beckmann:
        default:
        {
                wm = slopeSampleDwi(wi, u.x, u.y, alphaX, alphaY, true);
                break;
        }
    }
    return INV_M_PI * max(0.0f, dot(wo, wm));
}

template<typename RNG>
float3 diffuseSamplePhaseFunction(float3 wi, float4 u, float alphaX, float alphaY, int ndfType, inout RNG rng)
{
    float3 wm;
    switch (ndfType)
    {
        case NDF_StudentT:
        {
                wm = slopeStudentT_SampleDwi(wi, u.x, u.y, alphaX, alphaY, rng);
                break;
            }
        case NDF_GGX:
        {
                wm = slopeSampleDwi(wi, u.x, u.y, alphaX, alphaY, false);
                break;
            }
        case NDF_Beckmann:
        default:
        {
                wm = slopeSampleDwi(wi, u.x, u.y, alphaX, alphaY, true);
                break;
            }
    }

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

template<typename RNG>
float diffuseEvalSingleScattering(float3 wi, float3 wo, float2 u, float alphaX, float alphaY, int ndfType, RNG rng)
{
    float3 wm;
    switch (ndfType)
    {
        case NDF_StudentT:
        {
                wm = slopeStudentT_SampleDwi(wi, u.x, u.y, alphaX, alphaY, rng);
                break;
            }
        case NDF_GGX:
        {
                wm = slopeSampleDwi(wi, u.x, u.y, alphaX, alphaY, false);
                break;
            }
        case NDF_Beckmann:
        default:
        {
                wm = slopeSampleDwi(wi, u.x, u.y, alphaX, alphaY, true);
                break;
            }
    }

    float Lambda_i = slopeLambda(wi, alphaX, alphaY, ndfType);
    float Lambda_o = slopeLambda(wo, alphaX, alphaY, ndfType);
    float G2_given_G1 = (1.0f + Lambda_i) / (1.0f + Lambda_i + Lambda_o);

    float value = INV_M_PI * max(0.0f, dot(wm, wo)) * G2_given_G1;
    return value;
}


template<typename RNG>
float dielectricEval(float3 wi, float3 wo, int scatteringOrder, bool heightUniform, float alphaX, float alphaY, int ndfType, float ior, inout RNG rng)
{
    // Only outgoing directions above the surface contribute
    if (wo.z < 0.0f)
        return 0.0f;

    // Initial direction inside the microsurface
    float3 wr = -wi;

    // Initial height: 1 + invC1(0.999)
    float hr = 1.0f + (heightUniform ?
                       heightUniformInvC1(0.999f) :
                       heightGaussianInvC1(0.999f));

    bool outside = true; 
    float sum = 0.0f;
    int currentOrder = 0;
    // Random walk
    for (int step = 0; step < MS_MAX_STEPS; ++step)
    {
        // Stop if we only want up to a specific order
        if (scatteringOrder != 0 && currentOrder > scatteringOrder)
            break;

        // --- Sample next height ---
        float U = rng.rand();

        // Dielectric: height sampling depends on inside/outside
        hr = outside
            ? microsurfaceSampleHeight(wr, hr, U, heightUniform, alphaX, alphaY, ndfType)
            : -microsurfaceSampleHeight(-wr, -hr, U, heightUniform, alphaX, alphaY, ndfType);

        // Leave the microsurface?
        if (hr == FLT_MAX || hr == -FLT_MAX)
            break;

        currentOrder++;

        // --- Next-event estimation ---
        float phase = dielectricEvalPhaseFunctionCore(-wr, wo, outside, (wo.z > 0.0f), alphaX, alphaY, ndfType, ior);

        float shadow = (wo.z > 0.0f)
            ? microsurfaceG1Height(wo, hr, heightUniform, alphaX, alphaY, ndfType)
            : microsurfaceG1Height(-wo, -hr, heightUniform, alphaX, alphaY, ndfType);

        float I = phase * shadow;

        if (isfinite(I))
        {
            if (scatteringOrder == 0 ||
                currentOrder == scatteringOrder)
            {
                sum += I;
            }
        }

        // --- Sample next direction ---
        float3 newWr = dielectricSamplePhaseFunction(-wr, rng, outside, outside, alphaX, alphaY, ndfType, ior);

        // Safety: NaN check
        if (!isfinite(hr) || !isfinite(newWr.z))
            return 0.0f;

        wr = newWr;

        // Update inside/outside state for dielectric
        outside = (wr.z > 0.0f);
    }

    return sum;
}

template<typename RNG>
float3 dielectricSample( float3 wi, out int scatteringOrder, bool heightUniform, float alphaX, float alphaY, int ndfType, float ior, inout RNG rng)
{
    // Initial direction inside the microsurface
    float3 wr = -wi;

    // Initial height: 1 + invC1(0.999)
    float hr = 1.0f + (heightUniform ?
                       heightUniformInvC1(0.999f) :
                       heightGaussianInvC1(0.999f));

    bool outside = true;
    scatteringOrder = 0;

    // Random walk
    for (int step = 0; step < MS_MAX_STEPS; ++step)
    {
        // --- Sample next height ---
        float U = rng.rand();

        // Dielectric: height sampling depends on inside/outside state
        hr = outside
            ? microsurfaceSampleHeight(wr, hr, U, heightUniform, alphaX, alphaY, ndfType)
            : -microsurfaceSampleHeight(-wr, -hr, U, heightUniform, alphaX, alphaY, ndfType);

        // Leave the microsurface?
        if (hr == FLT_MAX || hr == -FLT_MAX)
            break;

        scatteringOrder++;

        // --- Sample next direction ---
        float3 newWr = dielectricSamplePhaseFunction( -wr, rng, outside,  outside, alphaX, alphaY, ndfType, ior);

        // Safety: NaN check
        if (!isfinite(hr) || !isfinite(newWr.z))
            return float3(0, 0, 1);

        wr = newWr;

        // Update inside/outside state
        outside = (wr.z > 0.0f);
    }

    return wr;
}

template<typename RNG>
float3 samplePhaseFunction(float3 wi, bool isConductor, float alphaX, float alphaY, int ndfType, inout RNG rng)
{
    if (isConductor)
    {
        float2 u = float2(rng.rand(), rng.rand());
        return conductorSamplePhaseFunction(wi, u, alphaX, alphaY, ndfType, rng);
    }

    
    // diffuse microsurface
    float4 u = float4(rng.rand(), rng.rand(), rng.rand(), rng.rand());
    return diffuseSamplePhaseFunction(wi, u, alphaX, alphaY, ndfType, rng);
}

template<typename RNG>
float evalPhaseFunction(float3 wi, float3 wo, float alphaX, float alphaY, int ndfType, bool isConductor, inout RNG rng)
{
    if (isConductor)
    {
        return conductorEvalPhaseFunction(wi, wo, alphaX, alphaY, ndfType);
    }
    float2 u = float2(rng.rand(), rng.rand());
    return diffuseEvalPhaseFunction(wi, wo, u, alphaX, alphaY, ndfType, rng);

}

template<typename RNG>
float microsurfaceEval(MaterialBRDF material, float3 wi, float3 wo, int scatteringOrder, bool heightUniform, float alphaX, float alphaY, int ndfType, inout RNG rng)
{
    // Only outgoing directions above the surface contribute
    if (wo.z < 0.0f)
        return 0.0f;

    bool isDielectric = (material.transmission > 0.0f);
    bool isConductor = !isDielectric && (material.metallicity > 0.5f);
    // Initial direction inside the microsurface
    float3 wr = -wi;

    // Initial height (same as C++: 1 + invC1(0.999))
    float hr = 1.0f + (heightUniform ? heightUniformInvC1(0.999f) : heightGaussianInvC1(0.999f));

    float sum = 0.0f;
    int currentOrder = 0;

    // Random walk inside the microsurface
    for (int step = 0; step < MS_MAX_STEPS; ++step)
    {
        // Stop if we only want up to a specific order
        if (scatteringOrder != 0 && currentOrder > scatteringOrder)
            break;

        // --- Sample next height ---
        float U = rng.rand();
        hr = microsurfaceSampleHeight(wr, hr, U, heightUniform, alphaX, alphaY, ndfType);

        // Ray leaves the microsurface?
        if (hr == FLT_MAX)
            break;

        currentOrder++;
        // --- Next-event estimation toward wo ---
        float phase = evalPhaseFunction(-wr, wo, alphaX, alphaY, ndfType, isConductor, rng);
        float shadow = microsurfaceG1Height(wo, hr, heightUniform, alphaX, alphaY, ndfType);
        float I = phase * shadow;

        if (isfinite(I))
        {
            if (scatteringOrder == 0 || currentOrder == scatteringOrder)
                sum += I;
        }

        // --- Sample next direction ---
        wr = samplePhaseFunction(-wr, isConductor, alphaX, alphaY, ndfType, rng);

        // Safety: NaN check
        if (!isfinite(hr) || !isfinite(wr.z))
            return 0.0f;
    }

    return sum;
}

template<typename RNG>
float3 microsurfaceSample(MaterialBRDF material, float3 wi, out int scatteringOrder, bool heightUniform, float alphaX, float alphaY, int ndfType, inout RNG randomNG)
{
    // init
    float3 wr = -wi;
    bool isDielectric = (material.transmission > 0.0f);
    bool isConductor = !isDielectric && (material.metallicity > 0.5f);


    // initial height (same as C++)
    float hr = 1.0f + (heightUniform ? heightUniformInvC1(0.999f) : heightGaussianInvC1(0.999f));

    scatteringOrder = 0;

    // random walk
    for (int step = 0; step < MS_MAX_STEPS; ++step)
    {
        // next height
        float u = randomNG.rand(); // your RNG
        hr = microsurfaceSampleHeight(wr, hr, u, heightUniform, alphaX, alphaY, ndfType);

        // leave the microsurface?
        if (hr == FLT_MAX)
            break;

        scatteringOrder++;

        // next direction
        wr = samplePhaseFunction(-wr, isConductor, alphaX, alphaY, ndfType, randomNG);

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

void buildTangentFrame(float3 N, out float3 T, out float3 B)
{
    float3 up = (abs(N.z) < 0.999f) ? float3(0, 0, 1) : float3(0, 1, 0);
    T = normalize(cross(up, N));
    B = cross(N, T);
}

float3 toLocal(float3 v, float3 T, float3 B, float3 N)
{
    return float3(dot(v, T), dot(v, B), dot(v, N));
}

template<typename RNG>
BRDFLobes Heitz(float3 N, float3 V, float3 L, MaterialBRDF material, inout RNG rng)
{
    BRDFLobes r;
    r.isMetal = (material.metallicity > 0.5);
    float NdotV = saturate(dot(N, V));
    float NdotL = saturate(dot(N, L));

    if (NdotL <= 0.0 || NdotV <= 0.0)
    {
        r.diffuseShape = 0.0;
        r.specularSingleShape = 0.0;
        r.specularMultiShape = 0.0;
        r.F0Rgb = material.F0;
        return r;
    }

    float alphaX = material.roughnessAlpha;
    float alphaY = alphaX;
    bool isDielectric = (material.transmission > 0.0f);
    bool isConductor = !isDielectric && (material.metallicity > 0.5f);
    int ndfType;
        
    switch (material.brdfType)
    {
        case BRDF_Heitz_GGX: 
            {
                ndfType = 1;
                break;
            }
        case BRDF_Heitz_StudentT: 
            {
                ndfType = 2;
                break;
            }
        case BRDF_Heitz_Beckmann:
        default:
        {
                ndfType = 0;
                break;
            }
    }
    if (isConductor)
    {
        r.specularSingleShape = conductorEvalSingleScattering(V, L, alphaX, alphaY, ndfType);
        r.specularMultiShape = microsurfaceEval(material, V, L, 0, true, alphaX, alphaY, ndfType, rng);

    }
    else if (isDielectric)
    {
        r.specularSingleShape = dielectricEvalSingleScattering(V, L, alphaX, alphaY, ndfType, material.ior);
        r.specularMultiShape = dielectricEval(V, L, 0, true, alphaX, alphaY, ndfType, material.ior, rng);

    }
    else
    {
       
        float2 u = float2(0.5, 0.5); 
        r.specularSingleShape = diffuseEvalSingleScattering(V, L, u, alphaX, alphaY, ndfType, rng);
        r.specularMultiShape = microsurfaceEval(material, V, L, 0, true, alphaX, alphaY, ndfType, rng);

    }
    

    r.F0Rgb = material.F0;

    r.diffuseShape =  INV_PI;

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
