float3 g_Eye;
float2 g_NearFar;
uint g_FrameIndex;
float3 g_PreviousEye;

#include "math/math.hlsl"
float4 main(in uint id : SV_VertexID) : SV_Position
{
    return float4(1.0f - 4.0f * (id & 1), 1.0f - 4.0f * (id >> 1), FLT_MIN, 1.0f);
}
