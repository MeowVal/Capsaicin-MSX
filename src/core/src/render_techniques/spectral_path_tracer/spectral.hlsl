#ifndef SPECTRAL_HLSL
#define SPECTRAL_HLSL
#include "ray_tracing/path_tracing_shared.h"
#include "materials/material_sampling.hlsl"
#include "components/random_number_generator/random_number_generator.hlsl"
#include "lights/light_evaluation.hlsl"
#include "math/color.hlsl"
static const float g_LambdaMin = 360.0f;
static const float g_LambdaMax = 830.0f;


float VisibleWavelengthsPDF(float lambda)
{
    if (lambda < g_LambdaMin || lambda > g_LambdaMax)
        return 0.0f;

    float x = 0.0072f * (lambda - 538.0f);
    float c = cosh(x);
    return 0.0039398042f / (c * c); 
}
float atanh_approx(float x)
{
    return 0.5f * log((1.0f + x) / (1.0f - x));
}

float SampleVisibleWavelengths(float u)
{
    // clamp u away from 0/1 to avoid atanh infinities
    u = saturate(u);
    u = lerp(1e-6f, 1.0f - 1e-6f, u);

    return 538.0f - 138.888889f * atanh_approx(0.85691062f - 1.82750197f * u);
}
float sampleHeroWavelength(inout Random rng)
{
    float u = rng.rand();
    return SampleVisibleWavelengths(u);
}

float sampleHeroWavelengthUniform(float u)
{
    
    return lerp(g_LambdaMin, g_LambdaMax, u);
}

void sampleHeroWavelengths3(inout Random rng, out float3 lambda, out float3 pdf)
{
    float u = rng.rand();

    float u0 = frac(u + 0.0 / 3.0);
    float u1 = frac(u + 1.0 / 3.0);
    float u2 = frac(u + 2.0 / 3.0);

    lambda.x = SampleVisibleWavelengths(u0);
    lambda.y = SampleVisibleWavelengths(u1);
    lambda.z = SampleVisibleWavelengths(u2);

    pdf.x = VisibleWavelengthsPDF(lambda.x);
    pdf.y = VisibleWavelengthsPDF(lambda.y);
    pdf.z = VisibleWavelengthsPDF(lambda.z);

}


float EvalPoly(float t, float coeffs[], int n)
{
    float x = coeffs[0];
    for (int i = 1; i < n; ++i)
        x = mad(x, t, coeffs[i]);
    return x;
}
float EvaluatePolynomial(float t, float c2, float c1, float c0)
{
    return mad(t, mad(t, c2, c1), c0);  
}
float s(float x) {
    if (isinf(x))
        return x > 0 ? 1 : 0;
    return .5f + x / (2.0f  * sqrt(1 + x * x));
}


int FindInterval(int sz, float z, Texture2D<float4> zNodes)
{
    int first = 1;
    int size  = sz - 2;

    while (size > 0)
    {
        int halfSize = size >> 1;
        int middle   = first + halfSize;

        // Compare using the .x component
        bool predResult = (zNodes.Load(int3(middle, 0, 0)).x < z);

        if (predResult)
        {
            first = middle + 1;
            size  = size - (halfSize + 1);
        }
        else
        {
            size = halfSize;
        }
    }

    int i = first - 1;
    return clamp(i, 0, sz - 2);
}
void SampleLUTCorners(
    Texture2D<float4> lut,
    int2 texel,
    int Res,
    out float3 c000, out float3 c100,
    out float3 c010, out float3 c110,
    out float3 c001, out float3 c101,
    out float3 c011, out float3 c111)
{
    c000 = lut.Load(int3(texel, 0)).xyz;
    c100 = lut.Load(int3(texel + int2(1, 0), 0)).xyz;
    c010 = lut.Load(int3(texel + int2(0, 1), 0)).xyz;
    c110 = lut.Load(int3(texel + int2(1, 1), 0)).xyz;

    c001 = lut.Load(int3(texel + int2(0, Res), 0)).xyz;
    c101 = lut.Load(int3(texel + int2(1, Res), 0)).xyz;
    c011 = lut.Load(int3(texel + int2(0, Res + 1), 0)).xyz;
    c111 = lut.Load(int3(texel + int2(1, Res + 1), 0)).xyz;
}
float3 LookupRGB2SpecCoeffs( float3 rgb )
{
    if (rgb.r == rgb.g && rgb.g == rgb.b)
    {
        float c2 = (rgb.r - 0.5f) / sqrt(rgb.r * (1.0f - rgb.r));
        return float3(0.0f, 0.0f, c2);
    }
    uint Res = g_Res; 
    int maxc = (rgb.r > rgb.g) ? ((rgb.r > rgb.b) ? 0 : 2) : ((rgb.g > rgb.b) ? 1 : 2);
    float z = max(rgb[maxc], 1e-6);
    float x = rgb[(maxc + 1) % 3] * (Res - 1) / z;
    float y = rgb[(maxc + 2) % 3] * (Res - 1) / z;
    

    int xi = min((int)x, Res - 2), yi = min((int)y, Res - 2),
        zi = FindInterval(Res, z, g_ZNodes);
    float dx = x - xi, dy = y - yi, dz = (z - g_ZNodes.Load(int3(zi, 0, 0)).x) / (g_ZNodes.Load(int3(zi + 1, 0, 0)).x - g_ZNodes.Load(int3(zi, 0, 0)).x);
    dz = saturate(dz);

    uint sliceIndex = zi * Res + yi;   // [0, Res*Res-1]
    int2 texel      = int2(xi, sliceIndex);

    float3 c000;
    float3 c100;
    float3 c010;
    float3 c110;
    float3 c001;
    float3 c101;
    float3 c011;
    float3 c111;

    if (maxc == 0)
    {
        SampleLUTCorners(g_RGB2SpecLUT0, texel, Res,
        c000, c100, c010, c110,
        c001, c101, c011, c111);
    }
    else if (maxc == 1)
    {
        SampleLUTCorners(g_RGB2SpecLUT1, texel, Res,
        c000, c100, c010, c110,
        c001, c101, c011, c111);
    }
    else
    {
        SampleLUTCorners(g_RGB2SpecLUT2, texel, Res,
        c000, c100, c010, c110,
        c001, c101, c011, c111);
    }

    // Trilinear interpolation
    float3 c00 = lerp(c000, c100, dx);
    float3 c10 = lerp(c010, c110, dx);
    float3 c0z = lerp(c00,  c10,  dy);

    float3 c01 = lerp(c001, c101, dx);
    float3 c11 = lerp(c011, c111, dx);
    float3 c1z = lerp(c01,  c11,  dy);

    return lerp(c0z, c1z, dz);
}
float3 bt709_to_srgb_linear(float3 c)
{
    // BT.709 linear → sRGB nonlinear
    float3 srgb_nl = select(
        1.099 * pow(c, 0.45) - 0.099, // else
        c * 4.5, // if
        c <= 0.018
    );

    // sRGB nonlinear → sRGB linear
    float3 srgb_lin = select(
        pow((srgb_nl + 0.055) / 1.055, 2.4), // else
        srgb_nl / 12.92, // if
        srgb_nl <= 0.04045
    );

    return srgb_lin;
}
float RGBToSpectrumTableSingle(float lambda, float3 rgb)
{
    
    float3 coeffs = LookupRGB2SpecCoeffs(rgb);
    float t = (lambda - g_LambdaMin) / (g_LambdaMax - g_LambdaMin);
    return s(EvaluatePolynomial(t, coeffs.z, coeffs.y, coeffs.x));;
}
float3 RGBToSpectrumTable3(float3 lambda_nm, float3 rgb)
{
    float3 sRGB = bt709_to_srgb_linear(rgb);
    return float3(
        RGBToSpectrumTableSingle(lambda_nm.x, sRGB),
        RGBToSpectrumTableSingle(lambda_nm.y, sRGB),
        RGBToSpectrumTableSingle(lambda_nm.z, sRGB)
    );
}




/// Wyman et al. Simple Analytic Approximations to the CIE XYZ Color Matching Functions
float xFit_1931( float wave )
{
    float t1 = (wave-442.0f)*((wave<442.0f)?0.0624f:0.0374f);
    float t2 = (wave-599.8f)*((wave<599.8f)?0.0264f:0.0323f);
    float t3 = (wave-501.1f)*((wave<501.1f)?0.0490f:0.0382f);
    return 0.362f*exp(-0.5f*t1*t1) + 1.056f*exp(-0.5f*t2*t2) - 0.065f*exp(-0.5f*t3*t3);
}
float yFit_1931( float wave )
{
    float t1 = (wave-568.8f)*((wave<568.8f)?0.0213f:0.0247f);
    float t2 = (wave-530.9f)*((wave<530.9f)?0.0613f:0.0322f);
    return 0.821f*exp(-0.5f*t1*t1) + 0.286f*exp(-0.5f*t2*t2);
}
float zFit_1931( float wave )
{
    float t1 = (wave-437.0f)*((wave<437.0f)?0.0845f:0.0278f);
    float t2 = (wave-459.0f)*((wave<459.0f)?0.0385f:0.0725f);
    return 1.217f*exp(-0.5f*t1*t1) + 0.681f*exp(-0.5f*t2*t2);
}
/// Wyman et al. Simple Analytic Approximations to the CIE XYZ Color Matching Functions
float3 WymanCie1931(float lambda, float T_Lambda)
{
    float x = xFit_1931(lambda)*T_Lambda;
    float y = yFit_1931(lambda)*T_Lambda;
    float z = zFit_1931(lambda)*T_Lambda;
    return float3(x, y, z);
}
float3 PBRTCie1931(float lambda)
{
    // map lambda to index 0–94
    float t = (lambda - g_LambdaMin) / (g_LambdaMax - g_LambdaMin);
    float idx = t * 94.0f;

    int i0 = clamp((int) floor(idx), 0, 93);
    int i1 = i0 + 1;

    float w = idx - i0;

    float x = lerp(cie_x[i0], cie_x[i1], w);
    float y = lerp(cie_y[i0], cie_y[i1], w);
    float z = lerp(cie_z[i0], cie_z[i1], w);

    return float3(x, y, z);
}

float3 SpectralToXYZ(float3 lambda, float3 T_lambda, float3 pdf_lambda)
{
    float3 xyz = 0;

    xyz += PBRTCie1931(lambda.x) * T_lambda.x / pdf_lambda.x;
    xyz += PBRTCie1931(lambda.y) * T_lambda.y / pdf_lambda.y;
    xyz += PBRTCie1931(lambda.z) * T_lambda.z / pdf_lambda.z;

    xyz /= 3.0f; // average 3 samples

    xyz /= 10566.864005283874576; // PBRT Y normalization   from rgb2spec_opt.cpp

    return xyz;
}

float3 WymanCie1931_3(float3 lambda, float3 T_Lambda, float3 pdf_lambda)
{
    float3 xyz1 = WymanCie1931(lambda.x, T_Lambda.x) / pdf_lambda.x;
    float3 xyz2 = WymanCie1931(lambda.y, T_Lambda.y) / pdf_lambda.y;
    float3 xyz3 = WymanCie1931(lambda.z, T_Lambda.z) / pdf_lambda.z;

    float3 XYZ = (xyz1 + xyz2 + xyz3) / 3.0f;
    return XYZ / 106.856895f; // ∫ ȳ(λ) dλ, ∫ yFit_1931(λ) dλ ≈ 106.856895 
}
float3 reconstructBT709(float3 XYZ)
{
    float3 rgb = convertXYZToBT709(XYZ);
    return max(rgb, 0.0.xxx);
}

float3 SpectralToRGB(float3 lambda, float3 T_Lambda, float3 pdf_lambda)
{
    float3 XYZ = SpectralToXYZ(lambda, T_Lambda, pdf_lambda);

    return reconstructBT709(XYZ);
}


float3 heroRGBWeightUnnormalized(float lambda_nm)
{
    float3 XYZ = WymanCie1931(lambda_nm, 1);
    float3 rgb = convertXYZToBT709(XYZ);

    // Clamp small negatives from matrix transform
    return max(rgb, 0.0.xxx);
}


float sampleMpmlReflectance(MaterialBRDF material, float lambda)
{
    float3 rgb = material.albedo;

    if (lambda < 500.0) return rgb.b;   // blue region
    if (lambda < 600.0) return rgb.g;   // green region
    return rgb.r;                       // red region
}



float sampleBRDFPDFAndEvaluteSpectral(MaterialBRDF material, float3 normal, float3 viewDirection,
    float3 lightDirection, float3 lambda, out float3 reflectanceLambda)
{
#ifndef DISABLE_SPECULAR_MATERIALS
    // Transform the view+light direction into the surfaces tangent coordinate space (oriented so that z axis is aligned to normal)
    Quaternion localRotation = QuaternionRotationZ(normal);
    float3 localView = localRotation.transform(viewDirection);
    float3 newLight = localRotation.transform(lightDirection);

    // Evaluate BRDF for input light direction
    float dotNL = clamp(newLight.z, -1.0f, 1.0f);
    // Calculate half vector
    float3 halfVector = normalize(localView + newLight);
    // Calculate shading angles
    float dotHV = saturate(dot(halfVector, localView));
    float dotNH = clamp(halfVector.z, -1.0f, 1.0f);
    float dotNV = clamp(localView.z, -1.0f, 1.0f);

    float3 f_rgb = evaluateBRDF(material, float3(0,0,1), localView, newLight);
    reflectanceLambda = RGBToSpectrumTable3(lambda, f_rgb);

    // Must use specular direction for H.V to match sampling functions
    float3 specularLightDirection = estimateSpecularPeak(material, float3(0.0f, 0.0f, 1.0f), localView);
    float3 specularHalfVector = normalize(localView + specularLightDirection);
    float specularDotHV = saturate(dot(specularHalfVector, localView));

    // Calculate combined PDF for current sample
    // Note: has some duplicated calculations in evaluateBRDF_GGX and sampleBRDFPDF
    float samplePDF = sampleBRDFPDF(material, dotNH, dotNL, specularDotHV, dotNV, localView, halfVector);
#else
    // Calculate shading angles
    float dotNL = clamp(dot(normal, lightDirection), -1.0f, 1.0f);
    // Calculate half vector
    float3 halfVector = normalize(viewDirection + lightDirection);
    float dotHV = saturate(dot(halfVector, viewDirection));
    float3 f_rgb = evaluateBRDFDiffuse(material, dotHV, dotNL);
    reflectanceLambda = RGBToSpectrumTable3(lambda, f_rgb);

    // Calculate diffuse PDF for current sample
    float samplePDF = sampleLambertPDF(dotNL);
#endif
    return samplePDF;
}

template<typename RNG>
float3 sampleBRDFAndEvaluateSpectral(MaterialBRDF material, inout RNG randomNG, float3 normal, float3 viewDirection, 
float3 lambda, out float3 lightDirection, out float pdf)
{
    // Transform the view direction into the surfaces tangent coordinate space (oriented so that z axis is aligned to normal)
    Quaternion localRotation = QuaternionRotationZ(normal);
    float3 localView = localRotation.transform(viewDirection);

    // Check which BRDF component to sample
    float3 newLight;
    float2 samples = randomNG.rand2();
#ifndef DISABLE_SPECULAR_MATERIALS
    float3 specularLightDirection = estimateSpecularPeak(material, float3(0.0f, 0.0f, 1.0f), localView);
    float3 specularHalfVector = normalize(localView + specularLightDirection);
    // Calculate shading angles
    float specularDotHV = saturate(dot(specularHalfVector, localView));
    float probabilityBRDF = calculateBRDFProbability(material.F0, specularDotHV, material.albedo);
    if (randomNG.rand() < probabilityBRDF)
    {
        // Sample specular BRDF component
        newLight = sampleSpecularDirection(material, localView, samples);
    }
    else
    {
        // Sample diffuse BRDF component
        newLight = sampleLambert(samples);
    }
#else
    // Sample diffuse BRDF component
    newLight = sampleLambert(samples);
#endif

    // Evaluate BRDF for new light direction
    float dotNL = clamp(newLight.z, -1.0f, 1.0f);
    float3 N = float3(0,0,1);
    // Calculate half vector
    float3 halfVector = normalize(localView + newLight);
    // Calculate shading angles
    float dotHV = saturate(dot(halfVector, localView));
#ifndef DISABLE_SPECULAR_MATERIALS
    float dotNH = clamp(halfVector.z, -1.0f, 1.0f);
    float dotNV = clamp(localView.z, -1.0f, 1.0f);
    float3 f_rgb = evaluateBRDF(material, N, localView, newLight);
    
#else
    float3 f_rgb = evaluateBRDFDiffuse(material, dotHV, dotNL);
#endif
    float3 f_lambda = RGBToSpectrumTable3(lambda, f_rgb); 
    // Calculate combined PDF for current sample
    // Note: has some duplicated calculations in evaluateBRDF_GGX and sampleBRDFPDF
#ifndef DISABLE_SPECULAR_MATERIALS
    pdf = sampleBRDFPDF2(material, dotNH, dotNL, dotNV, probabilityBRDF, localView, halfVector);
#else
    pdf = sampleLambertPDF(dotNL);
#endif

    // Transform the new direction back into world space
    lightDirection = normalize(localRotation.inverse().transform(newLight));
    return f_lambda;
}


float3 evaluateAreaLightSpectral(LightArea light, float2 barycentric, float3 lambda)
{
#ifndef DISABLE_AREA_LIGHTS
    // Load RGB emissivity
    float3 emissivity_rgb = light.emissivity.xyz;

    // Optional emissivity texture
    uint emissivityTex = asuint(light.emissivity.w);
    if (emissivityTex != uint(-1))
    {
        float2 uv = interpolate(light.uv0, light.uv1, light.uv2, barycentric);
        float4 tex = g_TextureMaps[NonUniformResourceIndex(emissivityTex)]
                        .SampleLevel(g_TextureSampler, uv, 0.0f);

        emissivity_rgb *= tex.xyz;
        emissivity_rgb *= tex.w; // alpha modulation
    }
    float3 emissivity_lambda = RGBToSpectrumTable3(lambda, emissivity_rgb);

    return emissivity_lambda;
#else
    return float3(0,0,0);
#endif
}

float3 evaluateEnvironmentLightSpectral(LightEnvironment light, float3 direction, float3 lambda )
{
#ifndef DISABLE_ENVIRONMENT_LIGHTS
    // Sample RGB environment map
    float3 env_rgb = g_EnvironmentBuffer.SampleLevel(g_TextureSampler, direction, 0.0f).xyz;
    float3 env_lambda = RGBToSpectrumTable3(lambda, env_rgb); ///Rec.709 Luminance weights

    return env_lambda;
#else
    return float3(0,0,0);
#endif
}

#endif // SPECTRAL_HLSL

