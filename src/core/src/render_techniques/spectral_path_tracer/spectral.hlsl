#ifndef SPECTRAL_HLSL
#define SPECTRAL_HLSL
#include "ray_tracing/path_tracing_shared.h"
#include "materials/material_sampling.hlsl"
#include "components/random_number_generator/random_number_generator.hlsl"
#include "lights/light_evaluation.hlsl"
static const float g_LambdaMin = 400.0f;
static const float g_LambdaMax = 700.0f;



float sampleHeroWavelength(inout Random rng)
{
    float u = rng.rand();
    return lerp(g_LambdaMin, g_LambdaMax, u);
}

float basisR(float lambda)
{
    float x = (lambda - g_LambdaMin) / (g_LambdaMax - g_LambdaMin);   // normalize 400–700 → 0–1
    return saturate(1.0 - abs(x - 0.75) * 3.0);
}

float basisG(float lambda)
{
    float x = (lambda - g_LambdaMin) / (g_LambdaMax - g_LambdaMin);
    return saturate(1.0 - abs(x - 0.50) * 3.0);
}

float basisB(float lambda)
{
    float x = (lambda - g_LambdaMin) / (g_LambdaMax - g_LambdaMin);
    return saturate(1.0 - abs(x - 0.25) * 3.0);
}

float sampleHeroReflectance(float3 rgb, float3 rgbWeight)
{
    return dot(rgb, rgbWeight);
}

float3 heroRGBWeight(float lambda)
{
    return float3(basisR(lambda), basisG(lambda), basisB(lambda));
}

float sampleMpmlReflectance(MaterialBRDF material, float lambda)
{
    float3 rgb = material.albedo;

    if (lambda < 500.0) return rgb.b;   // blue region
    if (lambda < 600.0) return rgb.g;   // green region
    return rgb.r;                       // red region
}

float sampleBRDFPDFAndEvaluteSpectral(MaterialBRDF material, float3 normal, float3 viewDirection,
    float3 lightDirection, float lambda, float3 rgbWeight, out float reflectanceLambda)
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

    reflectanceLambda = sampleHeroReflectance(f_rgb, rgbWeight);

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

    reflectance_lambda = sampleHeroReflectance(f_rgb, rgbWeight);

    // Calculate diffuse PDF for current sample
    float samplePDF = sampleLambertPDF(dotNL);
#endif
    return samplePDF;
}

template<typename RNG>
float sampleBRDFAndEvaluateSpectral(MaterialBRDF material, inout RNG randomNG, float3 normal, float3 viewDirection, 
float lambda, float3 rgbWeight, out float3 lightDirection, out float pdf, out bool specularSampled)
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
    float f_lambda = sampleHeroReflectance(f_rgb, rgbWeight); 
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

float evaluateEnvironmentLightSpectral(LightEnvironment light, float3 direction, float lambda, float3 rgbWeight)
{
#ifndef DISABLE_ENVIRONMENT_LIGHTS
    // Sample RGB environment map
    float3 env_rgb = g_EnvironmentBuffer.SampleLevel(g_TextureSampler, direction, 0.0f).xyz;
    // Convert RGB → scalar spectral radiance
    float env_lambda = sampleHeroReflectance(env_rgb, rgbWeight); ///Rec.709 Luminance weights

    return env_lambda;
#else
    return 0.0f;
#endif
}
#endif // SPECTRAL_HLSL

