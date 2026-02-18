
#ifndef BRDF_SHADING_HLSL
#define BRDF_SHADING_HLSL

#include "gpu_shared.h"
#include "math/math_constants.hlsl"

cbuffer FrameCB : register(b0)
{
    int g_BRDFModel; // 0=CookTorrance, 1=Fast-MSX, 2=Heitz, 3= GGX
};

struct CameraData
{
    float3 eye;
    float pad0;
};
cbuffer CameraCB : register(b1)
{
    CameraData g_Camera;
};

Texture2D<float4> GNormal : register(t0);
Texture2D<float4> GAlbedo : register(t1);
Texture2D<float4> GMaterial : register(t2);

SamplerState g_LinearSampler : register(s0);

cbuffer BufferDimCB : register(b2)
{
    uint2 g_BufferDimensions;
    uint2 pad1;
};

struct PSInput
{
    float4 position : SV_Position;
    float2 uv : TEXCOORD0;
};

float3 DecodeNormal(float3 enc)
{
    return normalize(enc * 2.0f - 1.0f);
}

// Very simple directional light for testing
static const float3 kLightDir = normalize(float3(0.4f, 0.8f, 0.2f));
static const float3 kLightCol = float3(1.0f, 1.0f, 1.0f);

float3 Cook_Torrance(float3 N, float3 V, float3 L, float3 albedo, float rough, float metal);
float3 Fast_MSX(float3 N, float3 V, float3 L, float3 albedo, float rough, float metal);
float3 Heitz(float3 N, float3 V, float3 L, float3 albedo, float rough, float metal);

PSInput VS_Fullscreen(uint id : SV_VertexID)
{
    PSInput o;
    float2 pos = float2((id == 2) ? 3.0f : -1.0f,
                        (id == 1) ? 3.0f : -1.0f);
    o.position = float4(pos, 0.0f, 1.0f);
    o.uv = 0.5f * (pos + 1.0f);
    return o;
}

float4 PS_Shading(PSInput input) : SV_Target0
{
    float2 uv = input.uv;

    float4 nTex = GNormal.Sample(g_LinearSampler, uv);
    float4 aTex = GAlbedo.Sample(g_LinearSampler, uv);
    float4 mTex = GMaterial.Sample(g_LinearSampler, uv);

    float3 N = DecodeNormal(nTex.rgb);
    float3 albedo = aTex.rgb;
    float rough = saturate(mTex.r);
    float metal = saturate(mTex.g);

    float3 V = normalize(g_Camera.eye); // for test: assume eye at origin
    float3 L = normalize(-kLightDir);

    float3 color;
    if (g_BRDFModel == 0)
        color = Cook_Torrance(N, V, L, albedo, rough, metal);
    else if (g_BRDFModel == 1)
        color = Fast_MSX(N, V, L, albedo, rough, metal);
    else
        color = Heitz(N, V, L, albedo, rough, metal);

    float NdotL = saturate(dot(N, L));
    color *= kLightCol * NdotL;

    return float4(color, 1.0f);
}

// --- Stub BRDFs (replace with your real implementations) ---

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
    float3 F0 = lerp(float3(0.04, 0.04, 0.04), albedo, metal);

        // --- Fresnel (Schlick) ---
    float3 F = F0 + (1.0 - F0) * pow(1.0 - VdotH, 5.0);

    // --- GGX Normal Distribution ---
    float a = rough * rough;
    float a2 = a * a;
    float denom = (NdotH * NdotH) * (a2 - 1.0) + 1.0;
    float D = a2 / (PI * denom * denom);

    // --- Smith GGX Geometry (Schlick-GGX) ---
    float k = (rough + 1.0);
    k = (k * k) / 8.0;

    float Gv = NdotV / (NdotV * (1.0 - k) + k);
    float Gl = NdotL / (NdotL * (1.0 - k) + k);
    float G = Gv * Gl;


    // --- Specular ---
    float3 spec = ((D * G * F) / (4.0 * NdotL * NdotV + 1e-5));

    // --- Diffuse (energy conserving) ---
    float3 kd = (1.0 - F) * (1.0 - metal);
    float3 diff = kd * albedo * (1.0 / PI);

    return (diff + spec) * NdotL;
}

float3 Fast_MSX(float3 N, float3 V, float3 L, float3 albedo, float rough, float metal)
{
    return albedo * 0.8f;
}

float3 Heitz(float3 N, float3 V, float3 L, float3 albedo, float rough, float metal)
{
    return albedo * 0.6f;
}
#endif
