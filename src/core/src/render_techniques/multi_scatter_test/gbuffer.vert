struct VSInput
{
    float3 position : POSITION;
    float3 normal : NORMAL;
    float2 texcoord : TEXCOORD0;
    float3 tangent : TANGENT;
};

cbuffer CameraMatrices : register(b0)
{
    float4x4 u_View;
    float4x4 u_Proj;
    float4x4 u_ViewProj;
    float4x4 u_PrevViewProj;
};

struct VSOutput
{
    float4 position : SV_Position;
    float3 worldPos : TEXCOORD0;
    float3 worldNormal : TEXCOORD1;
    float3 worldTangent : TEXCOORD2;
    float2 texcoord : TEXCOORD3;
};

VSOutput main(VSInput input)
{
    VSOutput o;

    float4 wp = float4(input.position, 1.0f);

    o.worldPos = wp.xyz;
    o.worldNormal = normalize(input.normal);
    o.worldTangent = normalize(input.tangent);
    o.texcoord = input.texcoord;

    o.position = mul(u_ViewProj, wp);
    return o;
}
