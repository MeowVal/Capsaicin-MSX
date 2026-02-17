cbuffer FrameCB : register(b0)
{
    int g_BRDFModel; // 0=Disney, 1=Heitz, 2=Burley
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

float3 BRDF_Disney(float3 N, float3 V, float3 L, float3 albedo, float rough, float metal);
float3 BRDF_Heitz(float3 N, float3 V, float3 L, float3 albedo, float rough, float metal);
float3 BRDF_Burley(float3 N, float3 V, float3 L, float3 albedo, float rough, float metal);

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
        color = BRDF_Disney(N, V, L, albedo, rough, metal);
    else if (g_BRDFModel == 1)
        color = BRDF_Heitz(N, V, L, albedo, rough, metal);
    else
        color = BRDF_Burley(N, V, L, albedo, rough, metal);

    float NdotL = saturate(dot(N, L));
    color *= kLightCol * NdotL;

    return float4(color, 1.0f);
}

// --- Stub BRDFs (replace with your real implementations) ---

float3 BRDF_Disney(float3 N, float3 V, float3 L, float3 albedo, float rough, float metal)
{
    return albedo;
}

float3 BRDF_Heitz(float3 N, float3 V, float3 L, float3 albedo, float rough, float metal)
{
    return albedo * 0.8f;
}

float3 BRDF_Burley(float3 N, float3 V, float3 L, float3 albedo, float rough, float metal)
{
    return albedo * 0.6f;
}
