float3 g_Eye;
float2 g_NearFar;
uint g_FrameIndex;
float3 g_PreviousEye;

struct VSOut
{
	float4 position : SV_Position;
	float2 uv : TEXCOORD0;
};

VSOut main(uint id : SV_VertexID)
{
	VSOut o;

	float2 pos = float2(
		(id == 2) ? 3.0f : -1.0f,
		(id == 1) ? 3.0f : -1.0f
	);

	o.position = float4(pos, 0.0f, 1.0f);
	o.uv = 0.5f * (pos + 1.0f);

	return o;
}
