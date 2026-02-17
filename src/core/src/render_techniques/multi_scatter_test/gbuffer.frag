#version 460 core

in VS_OUT
{
    vec3 worldPos;
    vec3 worldNormal;
    vec2 texcoord;
} fs_in;

layout(location = 0) out vec4 outNormal;
layout(location = 1) out vec4 outAlbedo;
layout(location = 2) out vec4 outMaterial;

layout(binding = 1) uniform sampler2D g_BaseColor;
layout(binding = 2) uniform sampler2D g_RoughnessMetallic;

void main()
{
    vec3 N = normalize(fs_in.worldNormal);

    vec3 baseColor = texture(g_BaseColor, fs_in.texcoord).rgb;
    vec2 rm        = texture(g_RoughnessMetallic, fs_in.texcoord).rg;
    float rough    = rm.r;
    float metal    = rm.g;

    outNormal   = vec4(normalize(N) * 0.5 + 0.5, 1.0);
    outAlbedo   = vec4(baseColor, 1.0);
    outMaterial = vec4(rough, metal, 0.0, 0.0);
}
