#include "../../gpu_shared.h"
cbuffer FrameCB : register(b0)
{
	int g_BRDFModel;
	float3 _padding;
	float4x4 g_ViewProjectionInverse;
};

float3 g_Eye;
float2 g_NearFar;
uint g_FrameIndex;
uint2 g_BufferDimensions;
uint g_DisableAlbedoTextures;

Texture2D g_DepthBuffer;
Texture2D g_ShadingNormalBuffer;
Texture2D g_GradientsBuffer;
Texture2D g_RoughnessBuffer;
Texture2D g_VisibilityBuffer;
Texture2D g_OcclusionAndBentNormalBuffer;


Texture2D g_LutBuffer;
uint g_LutSize;

StructuredBuffer<uint> g_IndexBuffer;
StructuredBuffer<Vertex> g_VertexBuffer;
uint g_VertexDataIndex;
StructuredBuffer<Instance> g_InstanceBuffer;
StructuredBuffer<Material> g_MaterialBuffer;

RWTexture2D<float4> g_IrradianceBuffer;
RWTexture2D<float4> g_ReflectionBuffer;

Texture2D g_TextureMaps[] : register(space99);
SamplerState g_NearestSampler;
SamplerState g_LinearSampler;
SamplerState g_TextureSampler;

#include "math/math_constants.hlsl"
#include "geometry/geometry.hlsl"
#include "geometry/mesh.hlsl"
//#include "lights/light_evaluation.hlsl"
#include "materials/material_evaluation.hlsl"
#include "materials/material_sampling.hlsl"
#include "brdf_models.hlsl"


static const float3 kLightDir = normalize(float3(0.4f, 0.8f, 0.2f));
static const float3 kLightCol = float3(1.0f, 1.0f, 1.0f);

float3 transformPointProjection(float2 uv, float depth, float4x4 invViewProj)
{
	float4 clip = float4(uv * 2.0f - 1.0f, depth, 1.0f);
	float4 world = mul(invViewProj, clip);
	return world.xyz / world.w;
}


float4 main(float4 pos : SV_Position) : SV_Target0
{
	uint2 did = uint2(pos.xy);
	float2 uv = (did + 0.5f) / g_BufferDimensions;
	float depth = g_DepthBuffer.Load(int3(did, 0)).x;
	if (depth <= 0.0f)
		return float4(0, 0, 0, 1);
	
	float3 worldPos = transformPointProjection(uv, depth, g_ViewProjectionInverse);

	float3 N = normalize(2.0f * g_ShadingNormalBuffer.Load(int3(did, 0)).xyz - 1.0f);
	
	float4 visibility = g_VisibilityBuffer.Load(int3(did, 0));
	uint instanceID = asuint(visibility.z);
	uint primitiveID = asuint(visibility.w);

	Instance instance = g_InstanceBuffer[instanceID];
	
	UVs uvs = fetchUVs(instance, primitiveID);
	float2 meshUV = interpolate(uvs.uv0, uvs.uv1, uvs.uv2, visibility.xy);
	
	
	

	Material material = g_MaterialBuffer[instance.material_index];
	MaterialEvaluated me = MakeMaterialEvaluated(material, meshUV);
	MaterialBRDF brdf = MakeMaterialBRDF(me);
	

	float3 V = normalize(g_Eye - worldPos);
	float3 L = normalize(-kLightDir);

	float3 color;
	if (g_BRDFModel == 0)
		color = Cook_Torrance(N, V, L, brdf.albedo, me.roughness, me.metallicity);
	else if (g_BRDFModel == 1)
		color = Fast_MSX(N, V, L, brdf.albedo, me.roughness, me.metallicity);
	else
		color = Heitz(N, V, L, brdf.albedo, me.roughness, me.metallicity);

	float NdotL = saturate(dot(N, L));
	color *= kLightCol * NdotL;
    color = kLightCol;
	return float4(color, 1.0f);
}


