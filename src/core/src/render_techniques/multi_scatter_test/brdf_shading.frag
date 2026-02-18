
#include "gpu_shared.h"
#include "math/math_constants.hlsl"
#include "brdf_models.hlsl"

cbuffer FrameCB : register(b0)
{
	int g_BRDFModel;
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

static const float3 kLightDir = normalize(float3(0.4f, 0.8f, 0.2f));
static const float3 kLightCol = float3(1.0f, 1.0f, 1.0f);



float4 main(PSInput input) : SV_Target0
{
	float2 uv = input.uv;

	float4 nTex = GNormal.Sample(g_LinearSampler, uv);
	float4 aTex = GAlbedo.Sample(g_LinearSampler, uv);
	float4 mTex = GMaterial.Sample(g_LinearSampler, uv);

	float3 N = DecodeNormal(nTex.rgb);
	float3 albedo = aTex.rgb;
	float rough = saturate(mTex.r);
	float metal = saturate(mTex.g);

	float3 V = normalize(g_Camera.eye);
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


