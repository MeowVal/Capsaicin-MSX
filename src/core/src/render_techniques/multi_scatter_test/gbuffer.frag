
Texture2D g_BaseColor : register(t1);
Texture2D g_RoughnessMetallic : register(t2);
Texture2D g_NormalMap : register(t3);
Texture2D g_AO : register(t4);
Texture2D g_Emissive : register(t5);

SamplerState g_Sampler : register(s0);

struct PSInput
{
    float4 position : SV_Position;
    float3 worldPos : TEXCOORD0;
    float3 worldNormal : TEXCOORD1;
    float3 worldTangent : TEXCOORD2;
    float2 texcoord : TEXCOORD3;
};

struct PSOutput
{
    float4 outNormal : SV_Target0;
    float4 outAlbedo : SV_Target1;
    float4 outMaterial : SV_Target2;
    float4 outWorldPos : SV_Target3;
};

float3 DecodeNormalMap(float3 n)
{
    return normalize(n * 2.0f - 1.0f);
}

PSOutput main(PSInput input)
{
    PSOutput o;

    // Base geometry normal
    float3 N = normalize(input.worldNormal);
    float3 T = normalize(input.worldTangent);
    float3 B = normalize(cross(N, T));

    // Normal map
    float3 nMap = g_NormalMap.Sample(g_Sampler, input.texcoord).xyz;
    nMap = DecodeNormalMap(nMap);

    float3x3 TBN = float3x3(T, B, N); // 3 float3 → 3x3 matrix
    float3 worldNormal = normalize(mul(nMap, TBN));

    // Albedo
    float4 baseColorTex = g_BaseColor.Sample(g_Sampler, input.texcoord);
    float3 baseColor = baseColorTex.rgb;
    float alpha = baseColorTex.a;

    // Roughness / Metallic
    float2 rm = g_RoughnessMetallic.Sample(g_Sampler, input.texcoord).rg;
    float rough = saturate(rm.r);
    float metal = saturate(rm.g);

    // AO
    float ao = g_AO.Sample(g_Sampler, input.texcoord).r;

    // Emissive
    float3 emissive = g_Emissive.Sample(g_Sampler, input.texcoord).rgb;
    float emissiveIntensity = max(max(emissive.r, emissive.g), emissive.b);

    // Encode normal
    o.outNormal = float4(worldNormal * 0.5f + 0.5f, 1.0f);

    // Albedo
    o.outAlbedo = float4(baseColor, alpha);

    // Roughness, Metallic, AO, Emissive
    o.outMaterial = float4(rough, metal, ao, emissiveIntensity);

    // World position
    o.outWorldPos = float4(input.worldPos, 1.0f);

    return o;
}
