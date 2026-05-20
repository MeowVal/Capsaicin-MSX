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
 /// Wyman et al. Simple Analytic Approximations to the CIE XYZ Color Matching Functions
float xFit_1931(float wave)
{
    float t1 = (wave - 442.0f) * ((wave < 442.0f) ? 0.0624f : 0.0374f);
    float t2 = (wave - 599.8f) * ((wave < 599.8f) ? 0.0264f : 0.0323f);
    float t3 = (wave - 501.1f) * ((wave < 501.1f) ? 0.0490f : 0.0382f);
    return 0.362f * exp(-0.5f * t1 * t1) + 1.056f * exp(-0.5f * t2 * t2) - 0.065f * exp(-0.5f * t3 * t3);
}
float yFit_1931(float wave)
{
    float t1 = (wave - 568.8f) * ((wave < 568.8f) ? 0.0213f : 0.0247f);
    float t2 = (wave - 530.9f) * ((wave < 530.9f) ? 0.0613f : 0.0322f);
    return 0.821f * exp(-0.5f * t1 * t1) + 0.286f * exp(-0.5f * t2 * t2);
}
float zFit_1931(float wave)
{
    float t1 = (wave - 437.0f) * ((wave < 437.0f) ? 0.0845f : 0.0278f);
    float t2 = (wave - 459.0f) * ((wave < 459.0f) ? 0.0385f : 0.0725f);
    return 1.217f * exp(-0.5f * t1 * t1) + 0.681f * exp(-0.5f * t2 * t2);
}
/// Wyman et al. Simple Analytic Approximations to the CIE XYZ Color Matching Functions
float ComputeCMFScale()
{
    float3 XYZ_white = float3(0, 0, 0);

    for (float lambda = 360.0; lambda <= 830.0; lambda += 5.0)
    {
        float pdf = VisibleWavelengthsPDF(lambda);
        float3 cmf = float3(
            xFit_1931(lambda),
            yFit_1931(lambda),
            zFit_1931(lambda)
        ) / pdf;

        XYZ_white += cmf;
    }

    XYZ_white *= 5.0; // nm step
    const float3x3 XYZ_to_BT709 = float3x3(3.240835667f, -1.537319541f, -0.4985901117f,
        -0.9692294598f, 1.875940084f, 0.04155444726f,
        0.05564493686f, -0.2040314376f, 1.057253838f);
    float3 rgbWhite = mul(XYZ_to_BT709, XYZ_white);

    return (1.0 / rgbWhite.y) * 235; // WB1 normalization   (1.0 / rgbWhite.y) * 235
}
static float CMF_SCALE = ComputeCMFScale();
void sampleHeroWavelength(inout Random rng, out float lambda, out float pdf)
{
    float u = rng.rand();
    lambda = SampleVisibleWavelengths(u);       
    pdf = VisibleWavelengthsPDF(lambda);
}

void sampleHeroWavelengthUniform(inout Random rng, out float lambda, out float pdf)
{
    float u = rng.rand();
    lambda = lerp(g_LambdaMin, g_LambdaMax, u);
    pdf = 1 / (g_LambdaMax - g_LambdaMin);

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

    uint sliceIndex = yi + zi * Res; // [0, Res*Res-1]
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
float3 computeJH19Coeffs(float3 rgb)
{
    float r = rgb.r, g = rgb.g, b = rgb.b;

    float3 coeffs;

    // These are the fitted coefficients from the paper
    coeffs.x = 1.0 * r + -1.0 * g + 0.0 * b;
    coeffs.y = -0.5 * r + 1.5 * g + 0.0 * b;
    coeffs.z = 0.0 * r + -1.0 * g + 1.0 * b;

    return coeffs;
}
float basis0(float lambda)
{
    return exp(-0.5 * pow((lambda - 610.0) / 45.0, 2.0));
}

float basis1(float lambda)
{
    return exp(-0.5 * pow((lambda - 530.0) / 30.0, 2.0));
}

float basis2(float lambda)
{
    return exp(-0.5 * pow((lambda - 460.0) / 25.0, 2.0));
}
float evalSpectrum(float lambda, float3 coeffs)
{
    return coeffs.x * basis0(lambda)
         + coeffs.y * basis1(lambda)
         + coeffs.z * basis2(lambda);
}
float3 RGBToSpectrum_JH19(float3 lambda_nm, float3 rgb)
{
    float3 coeffs = computeJH19Coeffs(rgb);

    return float3(
        evalSpectrum(lambda_nm.x, coeffs),
        evalSpectrum(lambda_nm.y, coeffs),
        evalSpectrum(lambda_nm.z, coeffs)
    );
}
float RGBToSpectrumTableSingle(float lambda, float3 rgb)
{
    
    float3 sRGB = rgb;
    float m = max(max(sRGB.r, sRGB.g), sRGB.b);
    if (m <= 0.0f)
        return 0.0;
    float3 remapped = sRGB / m;
    float3 coeffs = LookupRGB2SpecCoeffs(remapped);
    float x = EvaluatePolynomial(lambda, coeffs.x, coeffs.y, coeffs.z);
    return s(x) * m;
}
float RGBToSpectrumTable1(float lambda, float3 coeffs)
{
    return s(EvaluatePolynomial(lambda, coeffs.x, coeffs.y, coeffs.z));;
}
float3 RGBToSpectrumTable3(float3 lambda_nm, float3 rgb)
{
    float3 sRGB = rgb;
    float m = max(max(sRGB.r, sRGB.g), sRGB.b);
    if (m <= 0.0f)
        return 0.0.xxx;
    float3 remapped =  sRGB / m ;

    float3 coeffs = LookupRGB2SpecCoeffs(remapped);
    return float3(
        RGBToSpectrumTable1(lambda_nm.x, coeffs) * m,
        RGBToSpectrumTable1(lambda_nm.y, coeffs) * m,
        RGBToSpectrumTable1(lambda_nm.z, coeffs) * m
    );
    //return LookupRGB2SpecCoeffs(chroma);
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
    float idxF = (lambda - g_LambdaMin) / (5); //there is 5 nm between each sample of the Cie 
    //float idx = t * 94.0f;

    int i0 = clamp((int)floor(idxF), 0, 93);
    int i1 = i0 + 1;

    float w = idxF - i0;

    float x = lerp(g_CIE_X[i0], g_CIE_X[i1], w);
    float y = lerp(g_CIE_Y[i0], g_CIE_Y[i1], w);
    float z = lerp(g_CIE_Z[i0], g_CIE_Z[i1], w);

    return float3(x, y, z);
}
float3 PBRT_CMF(float lambda)
{
    return float3(
        xFit_1931(lambda),
        yFit_1931(lambda),
        zFit_1931(lambda)
    ) * CMF_SCALE;
}
float3 HeroWavelengthContribution(float lambda, float L_lambda, float pdf_lambda)
{
    float3 xyz = (PBRT_CMF(lambda) * L_lambda) / pdf_lambda;
    
    return xyz;
}
float3 HeroWavelengthContribution3(float3 lambda, float3 L_lambda, float3 pdf_lambda)
{
    float3 xyz = 0;
    xyz += HeroWavelengthContribution(lambda.x, L_lambda.x, pdf_lambda.x);
    xyz += HeroWavelengthContribution(lambda.y, L_lambda.y, pdf_lambda.y);
    xyz += HeroWavelengthContribution(lambda.z, L_lambda.z, pdf_lambda.z);  
    xyz /= 3.0f;
    
    return xyz;
}
float3 SpectralToXYZSingle(float lambda, float T_lambda, float pdf_lambda)
{
    float3 xyz = 0;

    xyz += (PBRTCie1931(lambda) * T_lambda) / pdf_lambda;
    return xyz;
}

float3 SpectralToXYZ(float3 lambda, float3 T_lambda, float3 pdf_lambda)
{
    float3 xyz = 0;

    xyz += (PBRTCie1931(lambda.x) * T_lambda.x) / pdf_lambda.x;
    xyz += (PBRTCie1931(lambda.y) * T_lambda.y) / pdf_lambda.y;
    xyz += (PBRTCie1931(lambda.z) * T_lambda.z) / pdf_lambda.z;

    xyz /= 3.0f; // average 3 samples

    //xyz /= 106.856895f;
    //xyz /= max(xyz.y, 1e-6);

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
    float3 rgb = convertXYZToBT709Adaptation(XYZ);
    return max(rgb, 0.0.xxx);
}
float3 SpectralToXYZ_Flat(float3 lambda, float3 T_Lambda, float3 pdf_lambda)
{
    float3 T_flat = float3(1.0, 1.0, 1.0); // flat spectrum

    float3 xyz = 0.0;

    xyz += PBRTCie1931(lambda.x) * (T_flat.x / max(pdf_lambda.x, 1e-8));
    xyz += PBRTCie1931(lambda.y) * (T_flat.y / max(pdf_lambda.y, 1e-8));
    xyz += PBRTCie1931(lambda.z) * (T_flat.z / max(pdf_lambda.z, 1e-8));

    xyz /= 3.0f;
    const float deltaLambda = 5.0f;
    const float N = 106.856895f; // PBRT 1nm normalization

    xyz *= (deltaLambda / N);

    return xyz;
}

float3 SpectralToRGBSingle(float lambda, float T_Lambda, float pdf_lambda)
{
    float3 XYZ = SpectralToXYZSingle(lambda, T_Lambda, pdf_lambda);

    return reconstructBT709(XYZ);
}

float3 SpectralToRGB(float3 lambda, float3 T_Lambda, float3 pdf_lambda)
{
    float3 XYZ = SpectralToXYZ(lambda, T_Lambda, pdf_lambda);

    return reconstructBT709(XYZ);
}




float sampleMpmlReflectance(MaterialBRDF material, float lambda)
{
    float3 rgb = material.albedo;

    if (lambda < 500.0) return rgb.b;   // blue region
    if (lambda < 600.0) return rgb.g;   // green region
    return rgb.r;                       // red region
}
float FresnelSchlickScalar(float VdotH, float f0Lambda)
{
    float F90 = 1.0;
    return f0Lambda + (F90 - f0Lambda) * pow(1.0 - saturate(abs(VdotH)), 5.0);
}
float3 FresnelSchlickScalar3(float VdotH, float3 f0Lambda)
{
    float F90 = 1.0f;
    return f0Lambda + (F90 - f0Lambda) * pow(1.0 - saturate(abs(VdotH)), 5.0);
}
float reconstructSpectral(BRDFLobes lobes,
                          MaterialBRDF material,
                          float lambda,
                          float dotNL, float dotHV, float fMulti)
{
    // Diffuse
    float albedo_lambda = RGBToSpectrumTableSingle(lambda, material.albedo);

    float diffuseLambda = albedo_lambda * lobes.diffuseShape;

    // Specular
    float specularLambda = 0.0;

    if (!lobes.isMetal)
    {
        // Dielectric → achromatic Fresnel
        float F0 = 0.04;
        float F = FresnelSchlickScalar(dotHV, F0);
        specularLambda = lobes.specularSingleShape * F;
    }
    else
    {
        // Metal → spectral F0
        float f0Lambda = RGBToSpectrumTableSingle(lambda, lobes.F0Rgb);
        float fLambda = FresnelSchlickScalar(dotHV, f0Lambda);
        specularLambda = lobes.specularSingleShape * fLambda;
    }

    return (diffuseLambda + specularLambda) * saturate(dotNL);
}
float3 reconstructSpectral3(BRDFLobes lobes,
                          MaterialBRDF material,
                          float3 lambda,
                          float dotNL, float dotHV, float3 fMulti)
{
    // Diffuse
    float3 albedo_lambda = RGBToSpectrumTable3(lambda, material.albedo);

    float3 diffuseLambda = albedo_lambda * lobes.diffuseShape;
    // Specular
    float3 specularLambda;
    float3 specularLambdaMulti;

    if (!lobes.isMetal)
    {
        // Dielectric → achromatic Fresnel
        float F0 = 0.04;
        float F = FresnelSchlickScalar(dotHV, F0);
        specularLambda = (lobes.specularSingleShape * F).xxx;
        specularLambdaMulti = lobes.specularMultiShape * fMulti;


    }
    else
    {
        // Metal → spectral F0
        float3 f0Lambda = RGBToSpectrumTable3(lambda, lobes.F0Rgb);
        float3 fLambda = FresnelSchlickScalar3(dotHV, f0Lambda);
        specularLambda = lobes.specularSingleShape * fLambda;
        specularLambdaMulti = lobes.specularMultiShape * fMulti;
    }

    return (diffuseLambda + (specularLambda + specularLambdaMulti)) * saturate(dotNL);
}
float reconstructSpectralHeitz(BRDFLobes lobes, MaterialBRDF material, float lambda, float dotNL)
{
    // Spectral albedo (Lambert diffuse)
    float albedo_lambda = RGBToSpectrumTableSingle(lambda, material.albedo);
    float diffuse = albedo_lambda * lobes.diffuseShape;

    float f0Lambda = RGBToSpectrumTableSingle(lambda, lobes.F0Rgb);
    float specularLambdaSingle = lobes.specularSingleShape;
    float specularLambdaMulti = lobes.specularMultiShape;

    return (diffuse + (specularLambdaSingle + specularLambdaMulti) * f0Lambda) * saturate(dotNL);
}
float3 reconstructSpectral3_Heitz( BRDFLobes lobes, MaterialBRDF material, float3 lambda, float dotNL)
{
    // Spectral albedo (Lambert diffuse)
    float3 albedo_lambda = RGBToSpectrumTable3(lambda, material.albedo);
    float3 diffuse = albedo_lambda * lobes.diffuseShape;

    float3 f0Lambda = RGBToSpectrumTable3(lambda, lobes.F0Rgb);
    float3 specularLambdaSingle = lobes.specularSingleShape;
    float3 specularLambdaMulti = lobes.specularMultiShape;

    return (diffuse + (specularLambdaSingle + specularLambdaMulti)*f0Lambda) * saturate(dotNL);
}

template<typename RNG>
float evaluateBRDFSpectral(MaterialBRDF material, float3 normal, float3 viewDirection, float3 lightDirection, float lambda, inout RNG rng, out float pdf)
{
    switch (material.brdfType)
    {
        case BRDF_CookTorr:{
                float3 H = normalize(viewDirection + lightDirection);
                float dotHV = saturate(dot(H, viewDirection));
                float dotNL = saturate(dot(normal, lightDirection));
                BRDFLobes lobes = CookTorrance(normal, viewDirection, lightDirection, material);
                pdf = 0;
                return reconstructSpectral(lobes, material, lambda, dotNL, dotHV, 0);
            }
        case BRDF_FastMSX:{
                float3 H = normalize(viewDirection + lightDirection);
                float dotHV = saturate(dot(H, viewDirection));
                float dotNL = saturate(dot(normal, lightDirection));
                BRDFLobes lobes = FastMSX(normal, viewDirection, lightDirection, material);
                float f0Lambda = RGBToSpectrumTableSingle(lambda, lobes.F0Rgb);
                float fLambda = FresnelSchlickScalar(dotHV, f0Lambda);
                pdf = 0;
                return reconstructSpectral(lobes, material, lambda, dotNL, dotHV, fLambda * fLambda);
            }
        case BRDF_Heitz_Beckmann:
        case BRDF_Heitz_GGX:
        case BRDF_Heitz_StudentT:{
                float dotNL = saturate(dot(normal, lightDirection));
                BRDFLobes lobes = Heitz(normal, viewDirection, lightDirection, material, rng);
                pdf = max(lobes.specularSingleShape + lobes.specularMultiShape, 1e-6);
                return reconstructSpectralHeitz(lobes, material, lambda, dotNL);
            }
        case BRDF_GGX:
        default:
        {
                float3 H = normalize(viewDirection + lightDirection);
                float dotHV = saturate(dot(H, viewDirection));
                float dotNH = saturate(dot(normal, H));
                float dotNL = saturate(dot(normal, lightDirection));
                float dotNV = saturate(dot(normal, viewDirection));
                BRDFLobes lobes = evaluateBRDF_GGX(material, dotHV, dotNH, dotNL, dotNV);
                pdf = 0;
                return reconstructSpectral(lobes, material, lambda, dotNL, dotHV, 0);
            }
    }
}

template<typename RNG>
float3 evaluateBRDFSpectral3(MaterialBRDF material, float3 normal, float3 viewDirection, float3 lightDirection, float3 lambda, inout RNG randomNG, out float pdf)
{
    switch (material.brdfType)
    {
        case BRDF_CookTorr:{
                float3 H = normalize(viewDirection + lightDirection);
                float dotHV = saturate(dot(H, viewDirection));
                float dotNL = saturate(dot(normal, lightDirection));
                BRDFLobes lobes = CookTorrance(normal, viewDirection, lightDirection, material);
                pdf = 0;
                return reconstructSpectral3(lobes, material, lambda, dotNL, dotHV, 0);
            }
        case BRDF_FastMSX:{
                float3 H = normalize(viewDirection + lightDirection);
                float dotHV = saturate(dot(H, viewDirection));
                float dotNL = saturate(dot(normal, lightDirection));
                BRDFLobes lobes = FastMSX(normal, viewDirection, lightDirection, material);
                pdf = 0;
                float3 f0Lambda = RGBToSpectrumTable3(lambda, lobes.F0Rgb);
                float3 fLambda = FresnelSchlickScalar3(dotHV, f0Lambda);
                return reconstructSpectral3(lobes, material, lambda, dotNL, dotHV, fLambda * fLambda);
            }
        case BRDF_Heitz_Beckmann:
        case BRDF_Heitz_StudentT:
        case BRDF_Heitz_GGX:
            {
                float dotNL = saturate(dot(normal, lightDirection));
                BRDFLobes lobes = Heitz(normal, viewDirection, lightDirection, material, randomNG);
                pdf = max(lobes.specularSingleShape + lobes.specularMultiShape, 1e-6);
                return reconstructSpectral3_Heitz(lobes, material, lambda, dotNL);
            }
        case BRDF_GGX:
        default:
        {
                float3 H = normalize(viewDirection + lightDirection);
                float dotHV = saturate(dot(H, viewDirection));
                float dotNH = saturate(dot(normal, H));
                float dotNL = saturate(dot(normal, lightDirection));
                float dotNV = saturate(dot(normal, viewDirection));
                BRDFLobes lobes = evaluateBRDF_GGX(material, dotHV, dotNH, dotNL, dotNV);
                pdf = 0;
                return reconstructSpectral3(lobes, material, lambda, dotNL, dotHV, 0);
            }
    }

}
float evaluateBRDFDiffuseSpecular(MaterialBRDF material, float dotHV, float dotNL, float lambda)
{
    // Calculate diffuse component
    float diffuse = RGBToSpectrumTableSingle(lambda, material.albedo) * INV_PI;
    // Add the weight of the diffuse compensation term to prevent excessive brightness compared to specular
#ifndef DISABLE_SPECULAR_MATERIALS
    diffuse *= diffuseCompensation(fresnel(material.F0, dotHV), dotHV).r;
#else
    diffuse *= diffuseCompensation(fresnel(0.04f.xxx, dotHV), dotHV).r;
#endif
    diffuse *= saturate(dotNL);
    return diffuse;
}
float3 evaluateBRDFDiffuseSpecular3(MaterialBRDF material, float dotHV, float dotNL, float3 lambda)
{
    // Calculate diffuse component
    float3 diffuse = RGBToSpectrumTable3(lambda, material.albedo) * INV_PI;
    // Add the weight of the diffuse compensation term to prevent excessive brightness compared to specular
#ifndef DISABLE_SPECULAR_MATERIALS
    diffuse *= diffuseCompensation(fresnel(material.F0, dotHV), dotHV).r;
#else
    diffuse *= diffuseCompensation(fresnel(0.04f.xxx, dotHV), dotHV).r;
#endif
    diffuse *= saturate(dotNL);
    return diffuse;
}

template<typename RNG>
float sampleBRDFPDFAndEvaluteSpectral(MaterialBRDF material, float3 normal, float3 viewDirection,
    float3 lightDirection, float lambda, out float reflectanceLambda, inout RNG randomNG)
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

    float samplePDF;
    reflectanceLambda = evaluateBRDFSpectral(material, float3(0, 0, 1), localView, newLight, lambda, randomNG, samplePDF);

    if (samplePDF == 0.0f)
    {
      // Must use specular direction for H.V to match sampling functions
        float3 specularLightDirection = estimateSpecularPeak(material, float3(0.0f, 0.0f, 1.0f), localView);
        float3 specularHalfVector = normalize(localView + specularLightDirection);
        float specularDotHV = saturate(dot(specularHalfVector, localView));

    // Calculate combined PDF for current sample
    // Note: has some duplicated calculations in evaluateBRDF_GGX and sampleBRDFPDF
        samplePDF = sampleBRDFPDF(material, dotNH, dotNL, specularDotHV, dotNV, localView, halfVector);
    }
    
#else
    // Calculate shading angles
    float dotNL = clamp(dot(normal, lightDirection), -1.0f, 1.0f);
    // Calculate half vector
    float3 halfVector = normalize(viewDirection + lightDirection);
    float dotHV = saturate(dot(halfVector, viewDirection));
    reflectanceLambda = evaluateBRDFDiffuseSpecular(material, dotHV, dotNL, lambda);
    

    // Calculate diffuse PDF for current sample
    float samplePDF = sampleLambertPDF(dotNL);
#endif
    return samplePDF;
}
template<typename RNG>
float sampleBRDFPDFAndEvaluteSpectral3(MaterialBRDF material, float3 normal, float3 viewDirection,
    float3 lightDirection, float3 lambda, out float3 reflectanceLambda, inout RNG randomNG)
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

    float samplePDF;
    reflectanceLambda = evaluateBRDFSpectral3(material, float3(0, 0, 1), localView, newLight, lambda, randomNG, samplePDF);

    if (samplePDF == 0.0f)
    {
        // Must use specular direction for H.V to match sampling functions
        float3 specularLightDirection = estimateSpecularPeak(material, float3(0.0f, 0.0f, 1.0f), localView);
        float3 specularHalfVector = normalize(localView + specularLightDirection);
        float specularDotHV = saturate(dot(specularHalfVector, localView));

        // Calculate combined PDF for current sample
        // Note: has some duplicated calculations in evaluateBRDF_GGX and sampleBRDFPDF
        samplePDF = sampleBRDFPDF(material, dotNH, dotNL, specularDotHV, dotNV, localView, halfVector);
    }
    
#else
    // Calculate shading angles
    float dotNL = clamp(dot(normal, lightDirection), -1.0f, 1.0f);
    // Calculate half vector
    float3 halfVector = normalize(viewDirection + lightDirection);
    float dotHV = saturate(dot(halfVector, viewDirection));
    reflectanceLambda = evaluateBRDFDiffuseSpecular3(material, dotHV, dotNL, lambda);
    

    // Calculate diffuse PDF for current sample
    float samplePDF = sampleLambertPDF(dotNL);
#endif
    return samplePDF;
}
template<typename RNG>
float sampleBRDFAndEvaluateSpectral(MaterialBRDF material, inout RNG randomNG, float3 normal, float3 viewDirection,
float lambda, out float3 lightDirection, out float pdf)
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
        newLight = sampleSpecularDirection(material, localView, samples, randomNG);
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
    float f_lambda = evaluateBRDFSpectral(material, N, localView, newLight, lambda, randomNG, pdf);
    
#else
    float f_lambda= evaluateBRDFDiffuseSpecular(material, dotHV, dotNL, lambda);
#endif
    // Calculate combined PDF for current sample
    // Note: has some duplicated calculations in evaluateBRDF_GGX and sampleBRDFPDF
#ifndef DISABLE_SPECULAR_MATERIALS
    if (pdf == 0)
        pdf = sampleBRDFPDF2(material, dotNH, dotNL, dotNV, probabilityBRDF, localView, halfVector);
#else
    pdf = sampleLambertPDF(dotNL);
#endif

    
    // Transform the new direction back into world space
    lightDirection = normalize(localRotation.inverse().transform(newLight));
    return f_lambda;
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
        newLight = sampleSpecularDirection(material, localView, samples, randomNG);
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
    float3 N = float3(0, 0, 1);
    // Calculate half vector
    float3 halfVector = normalize(localView + newLight);
    // Calculate shading angles
    float dotHV = saturate(dot(halfVector, localView));
#ifndef DISABLE_SPECULAR_MATERIALS
    float dotNH = clamp(halfVector.z, -1.0f, 1.0f);
    float dotNV = clamp(localView.z, -1.0f, 1.0f);
    float3 f_lambda = evaluateBRDFSpectral3(material, N, localView, newLight, lambda, randomNG, pdf);
    
#else
    float3 f_lambda= evaluateBRDFDiffuseSpecular3(material, dotHV, dotNL, lambda);
#endif
    // Calculate combined PDF for current sample
    // Note: has some duplicated calculations in evaluateBRDF_GGX and sampleBRDFPDF
#ifndef DISABLE_SPECULAR_MATERIALS
    if (pdf == 0)
        pdf = sampleBRDFPDF2(material, dotNH, dotNL, dotNV, probabilityBRDF, localView, halfVector);
#else
    pdf = sampleLambertPDF(dotNL);
#endif

    
    // Transform the new direction back into world space
    lightDirection = normalize(localRotation.inverse().transform(newLight));
    return f_lambda;
}

float evaluateAreaLightSpectral(LightArea light, float2 barycentric, float lambda)
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
    float3 emissivity_srgb = linear_to_srgb(emissivity_rgb);
    float emissivity_lambda = RGBToSpectrumTableSingle(lambda, emissivity_rgb);

    return emissivity_lambda;
#else
    return 0.0f;
#endif
}

float3 evaluateAreaLightSpectral3(LightArea light, float2 barycentric, float3 lambda)
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
    return 0.0f.xxx;
#endif
}         

float evaluateEnvironmentLightSpectral(LightEnvironment light, float3 direction, float lambda )
{
#ifndef DISABLE_ENVIRONMENT_LIGHTS
    // Sample RGB environment map
    float3 env_rgb = g_EnvironmentBuffer.SampleLevel(g_TextureSampler, direction, 0.0f).xyz;

    float env_lambda = RGBToSpectrumTableSingle(lambda, env_rgb);

    return env_lambda;
#else
    return 0.0f;
#endif
}
float3 evaluateEnvironmentLightSpectral3(LightEnvironment light, float3 direction, float3 lambda)
{
#ifndef DISABLE_ENVIRONMENT_LIGHTS
    // Sample RGB environment map
    float3 env_rgb = g_EnvironmentBuffer.SampleLevel(g_TextureSampler, direction, 0.0f).xyz;

    float3 env_lambda = RGBToSpectrumTable3(lambda, env_rgb);

    return env_lambda;
#else
    return 0.0f.xxx;
#endif
}

#endif // SPECTRAL_HLSL

