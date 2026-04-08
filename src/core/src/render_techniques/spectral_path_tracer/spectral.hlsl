#ifndef SPECTRAL_HLSL
#define SPECTRAL_HLSL
#include "ray_tracing/path_tracing_shared.h"
    


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
#endif // SPECTRAL_HLSL

