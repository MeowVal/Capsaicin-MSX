#version 460 core

layout(location = 0) in vec3 inPosition;
layout(location = 1) in vec3 inNormal;
layout(location = 2) in vec2 inTexcoord;
layout(location = 3) in vec3 inTangent;

layout(std140, binding = 0) uniform CameraMatrices
{
    mat4 u_View;
    mat4 u_Proj;
    mat4 u_ViewProj;
    mat4 u_PrevViewProj;
} g_CameraMatrices;

out VS_OUT
{
    vec3 worldPos;
    vec3 worldNormal;
    vec2 texcoord;
} vs_out;

void main()
{
    vec4 wp = vec4(inPosition, 1.0);
    vs_out.worldPos    = wp.xyz;
    vs_out.worldNormal = normalize(inNormal);
    vs_out.texcoord    = inTexcoord;

    gl_Position = g_CameraMatrices.u_ViewProj * wp;
}
