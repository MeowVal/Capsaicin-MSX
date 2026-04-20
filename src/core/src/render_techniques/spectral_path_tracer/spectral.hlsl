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
    // Placeholder: you’ll plug in your real basis / CMFs
    // For now, just a dummy smooth function
    float t = saturate((lambda - g_LambdaMin) / (g_LambdaMax - g_LambdaMin));
    return normalize(float3(1.0f - t, t, 0.5f));
}

float sampleMpmlReflectance(MaterialBRDF material, float lambda)
{
    float3 rgb = material.albedo;

    if (lambda < 500.0) return rgb.b;   // blue region
    if (lambda < 600.0) return rgb.g;   // green region
    return rgb.r;                       // red region
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
    float3 specularLightDirection = calculateGGXSpecularDirection(float3(0.0f, 0.0f, 1.0f), localView, sqrt(material.roughnessAlpha));
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

