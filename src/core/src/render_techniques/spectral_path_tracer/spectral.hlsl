#ifndef SPECTRAL_HLSL
#define SPECTRAL_HLSL
#include "ray_tracing/path_tracing_shared.h"
#include "materials/material_sampling.hlsl"
#include "components/random_number_generator/random_number_generator.hlsl"
#include "render_techniques/multi_scatter_test/brdf_models.hlsl"

static const float g_LambdaMin = 400.0f;
static const float g_LambdaMax = 700.0f;

float sampleHeroWavelength(inout Random rng)
{
    float u = rng.rand();
    return lerp(g_LambdaMin, g_LambdaMax, u);
}

// Simple camera response → RGB weight; replace with your basis
float3 heroRGBWeight(float lambda)
{
    // Convert nm → normalized 0..1
    float t = saturate((lambda - 380.0f) / (780.0f - 380.0f));

    // Smooth overlapping lobes (approximate RGB sensitivity curves)
    float r = exp(-0.5 * pow((t - 0.75) / 0.15, 2.0));
    float g = exp(-0.5 * pow((t - 0.50) / 0.15, 2.0));
    float b = exp(-0.5 * pow((t - 0.25) / 0.15, 2.0));

    return float3(r, g, b);
}

float sampleMpmlReflectance(MaterialBRDF material, float lambda)
{
    float3 rgb = material.albedo;

    if (lambda < 500.0) return rgb.b;   // blue region
    if (lambda < 600.0) return rgb.g;   // green region
    return rgb.r;                       // red region
}

float sampleBRDFPDFAndEvaluteSpectral(MaterialBRDF material, float3 normal, float3 viewDirection,
    float3 lightDirection, float lambda, out float reflectanceLambda)
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

    float3 LUMA = float3(0.2126, 0.7152, 0.0722);
    float R_lambda = sampleMpmlReflectance(material, lambda);
    reflectanceLambda = dot(f_rgb, LUMA) * R_lambda;

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

    float3 LUMA = float3(0.2126, 0.7152, 0.0722);
    float R_lambda = sampleMpmlReflectance(material, lambda);
    reflectance_lambda = dot(f_rgb, LUMA) * R_lambda;

    // Calculate diffuse PDF for current sample
    float samplePDF = sampleLambertPDF(dotNL);
#endif
    return samplePDF;
}

template<typename RNG>
float sampleBRDFAndEvaluateSpectral(MaterialBRDF material, inout RNG randomNG, float3 normal, float3 viewDirection, 
float lambda, out float3 lightDirection, out float pdf, out bool specularSampled)
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
    specularSampled = false;
    if (randomNG.rand() < probabilityBRDF)
    {
        // Sample specular BRDF component
        newLight = sampleSpecularDirection(material, localView, samples);
        specularSampled = true;
    }
    else
    {
        // Sample diffuse BRDF component
        newLight = sampleLambert(samples);
    }
#else
    // Sample diffuse BRDF component
    newLight = sampleLambert(samples);
    specularSampled = false;
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
    float R_lambda = sampleMpmlReflectance(material, lambda);
    float f_lambda = dot(f_rgb, float3(0.2126, 0.7152, 0.0722)) * R_lambda; /// float3(0.2126, 0.7152, 0.0722) is the Luminance weights from the CIE 1931 XYZ color space for sRGB/Rec.709
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

#endif // SPECTRAL_HLSL

