/**********************************************************************
Copyright (c) 2025 Advanced Micro Devices, Inc. All rights reserved.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
********************************************************************/

#ifndef MATERIAL_EVALUATION_HLSL
#define MATERIAL_EVALUATION_HLSL

#include "materials.hlsl"
#include "math/math_constants.hlsl"
struct BRDFLobes
{
    float diffuseShape; // Lambertian shape only, no color
    float specularSingleShape; // D*G / (4*N·L*N·V), wavelength-independent
    float specularMultiShape;
    float3 F0Rgb; // RGB F0 for metals OR scalar F0.xxx for dielectrics
    bool isMetal;
};
#include "render_techniques/multi_scatter_test/brdf_models.hlsl"

/**
 * Calculates schlick fresnel term.
 * @param F0    The fresnel reflectance an grazing angle.
 * @param dotHV The dot product of the half-vector and view direction (range [-1, 1]).
 * @return The calculated fresnel term.
 */
float3 fresnel(float3 F0, float dotHV)
{
    // The half-vector may be incorrectly flipped or invisible to the view direction in some cases, and thus
    // dotHV may be negative. For this case, we use abs(dotHV) to correct flipping and avoid NaN.
    float3 F90 = 1.0f.xxx;
    return F0 + (F90 - F0) * pow(1.0f - saturate(abs(dotHV)), 5.0f);
}

/**
 * Calculates the amount to modify the diffuse component of a combined BRDF.
 * @param f     Pre-calculated fresnel value.
 * @param dotHV The dot product of the half-vector and view direction (range [-1, 1]).
 * @return The amount to modify diffuse component by.
 */
float3 diffuseCompensationTerm(float3 f, float dotHV)
{
    // PBR Diffuse Lighting for GGX + Smith Microsurfaces - Hammon 2017

    // The half-vector may be incorrectly flipped or invisible to the view direction in some cases, and thus
    // dotHV may be negative. For this case, we use abs(dotHV) to correct flipping and avoid NaN.
    return (1.0f.xxx - f) * 1.05 * (1.0f - pow(1.0f - saturate(abs(dotHV)), 5.0f));
}

/**
 * Calculates the amount to modify the diffuse component of a combined BRDF.
 * @param F0    The fresnel reflectance at grazing angle.
 * @param dotHV The dot product of the half-vector and view direction (range [-1, 1]).
 * @return The amount to modify diffuse component by.
 */
float3 diffuseCompensation(float3 F0, float dotHV)
{
    return diffuseCompensationTerm(fresnel(F0, dotHV), dotHV);
}

/**
 * Evaluate the Trowbridge-Reitz Normal Distribution Function.
 * @param roughnessAlphaSqr The NDF roughness value squared.
 * @param dotNH             The dot product of the normal and half vector (range [-1, 1]).
 * @return The calculated NDF value.
 */
float evaluateNDFTrowbridgeReitz(float roughnessAlphaSqr, float dotNH)
{
    // Heaviside function for microfacet normal in the upper hemisphere.
    if (dotNH < 0.0f)
    {
        return 0.0f;
    }

    // Numerically stable form of Walter 2007 GGX NDF
    float eps = 1e-5f;
    float denom = (1.0f - dotNH * dotNH) / (roughnessAlphaSqr + eps) + dotNH * dotNH;
    return 1.0f / (PI * roughnessAlphaSqr * denom * denom);
}

/**
 * Evaluate the GGX Visibility function.
 * @param roughnessAlphaSqr The GGX roughness value squared.
 * @param dotNL             The dot product of the normal and light direction (range [-1, 1]).
 * @param dotNV             The dot product of the normal and view direction (range [-1, 1]).
 * @return The calculated visibility value.
 */
float evaluateVisibilityGGX(float roughnessAlphaSqr, float dotNL, float dotNV)
{
    // The masking-shadowing function is indefinite for back-facing shading normals.
    // So we use abs(dotNL) and abs(dotNV) for this case.
    // This is hacky, but still satisfies the reciprocity and energy conservation.
    float rMod = 1.0f - roughnessAlphaSqr;
    float recipG1 = abs(dotNL) + sqrt(roughnessAlphaSqr + (rMod * dotNL * dotNL));
    float recipG2 = abs(dotNV) + sqrt(roughnessAlphaSqr + (rMod * dotNV * dotNV));
    float recipV = recipG1 * recipG2;
    return recipV;
}

/**
 * Evaluate the GGX BRDF.
 * @param roughnessAlphaSqr The GGX roughness value squared.
 * @param F0                The fresnel reflectance at grazing angle.
 * @param dotHV             The dot product of the half-vector and view direction (range [-1, 1]).
 * @param dotNH             The dot product of the normal and half vector (range [-1, 1]).
 * @param dotNL             The dot product of the normal and light direction (range [-1, 1]).
 * @param dotNV             The dot product of the normal and view direction (range [-1, 1]).
 * @param [out] fresnelOut  The returned fresnel value.
 * @return The calculated reflectance.
 */
float3 evaluateGGX(float roughnessAlphaSqr, float3 F0, float dotHV, float dotNH, float dotNL, float dotNV, out float3 fresnelOut)
{
    // Calculate Fresnel
    fresnelOut = fresnel(F0, dotHV);

    // Calculate Trowbridge-Reitz Distribution function
    float d = evaluateNDFTrowbridgeReitz(roughnessAlphaSqr, dotNH);

    // Calculate GGX Visibility function
    float recipV = evaluateVisibilityGGX(roughnessAlphaSqr, dotNL, dotNV);

    return (fresnelOut * d) / recipV;
}

/**
 * Evaluate the GGX BRDF without Fresnel.
 * @param roughnessAlphaSqr The GGX roughness value squared.
 * @param dotNH             The dot product of the normal and half vector (range [-1, 1]).
 * @param dotNL             The dot product of the normal and light direction (range [-1, 1]).
 * @param dotNV             The dot product of the normal and view direction (range [-1, 1]).
 * @return The calculated reflectance.
 */
float evaluateGGX(float roughnessAlphaSqr, float dotNH, float dotNL, float dotNV)
{
    // Calculate Trowbridge-Reitz Distribution function
    float d = evaluateNDFTrowbridgeReitz(roughnessAlphaSqr, dotNH);

    // Calculate GGX Visibility function
    float recipV = evaluateVisibilityGGX(roughnessAlphaSqr, dotNL, dotNV);

    return d / recipV;
}

/**
 * Evaluate the Lambert BRDF.
 * @param albedo The diffuse colour term.
 * @return The calculated reflectance.
 */
float3 evaluateLambert(float3 albedo)
{
    return albedo * INV_PI;
}
      

/**
 * Evaluate the combined BRDF.
 * @param material Material data describing BRDF.
 * @param dotHV    The dot product of the half-vector and view direction (range [-1, 1]).
 * @param dotNH    The dot product of the normal and half vector (range [-1, 1]).
 * @param dotNL    The dot product of the normal and light direction (range [-1, 1]).
 * @param dotNV    The dot product of the normal and view direction (range [-1, 1]).
 * @return The calculated reflectance.
 */
BRDFLobes evaluateBRDF_GGX(MaterialBRDF material, float dotHV, float dotNH, float dotNL, float dotNV)
{
    BRDFLobes r;
    r.isMetal = (material.metallicity > 0.5);
    // Calculate diffuse component
    float3 F = fresnel(material.F0, dotHV);
    float3 diffCompRGB = diffuseCompensation(F, dotHV);
    r.diffuseShape = INV_PI * diffCompRGB.r;

#ifndef DISABLE_SPECULAR_MATERIALS
    // Calculate specular component
    float3 spec_rgb = evaluateGGX(material.roughnessAlphaSqr, dotNH, dotNL, dotNV);
    r.specularSingleShape = (spec_rgb.r + spec_rgb.g + spec_rgb.b) * (1.0 / 3.0);
    
    r.specularMultiShape = 0.0f;
    r.F0Rgb = material.F0;
#else
    r.specularSingleShape = 0.0;
    r.F0Rgb = float3(0,0,0);
    r.specularMultiShape = 0.0f;
#endif
    return r;
}

/**
 * Evaluate the combined BRDF.
 * @param material       Material data describing BRDF.
 * @param normal         Shading normal vector at current position (must be normalised).
 * @param viewDirection  Outgoing ray view direction (must be normalised).
 * @param lightDirection The direction to the sampled light (must be normalised).
 * @return The calculated reflectance.
 */
float3 evaluateBRDF_GGX(MaterialBRDF material, float3 normal, float3 viewDirection, float3 lightDirection)
{
    // Calculate diffuse component
    float3 diffuse = evaluateLambert(material.albedo);

    // Calculate shading angles
    float dotNL = clamp(dot(normal, lightDirection), -1.0f, 1.0f);
    // Calculate half vector
    float3 halfVector = normalize(viewDirection + lightDirection);
    float dotHV = saturate(dot(halfVector, viewDirection));
#ifndef DISABLE_SPECULAR_MATERIALS
    float dotNH = clamp(dot(normal, halfVector), -1.0f, 1.0f);
    float dotNV = clamp(dot(normal, viewDirection), -1.0f, 1.0f);

    // Calculate specular component
    float3 f;
    float3 specular = evaluateGGX(material.roughnessAlphaSqr, material.F0, dotHV, dotNH, dotNL, dotNV, f);

    // Add the weight of the diffuse compensation term
    diffuse *= diffuseCompensationTerm(f, dotHV);
    float3 brdf = (specular + diffuse) * saturate(dotNL); // saturate(dotNL) = abs(dotNL) * Heaviside function for the upper hemisphere.
#else
    // Add the weight of the diffuse compensation term to prevent excessive brightness compared to specular
    diffuse *= diffuseCompensation(fresnel(0.04f.xxx, dotHV), dotHV);
    float3 brdf = diffuse * saturate(dotNL);
#endif
    return brdf;
}
float3 reconstructRGB(BRDFLobes lobes, MaterialBRDF material, float dotNL, float dotHV, float3 fMulti)
{
    float3 diffuseRgb = material.albedo * lobes.diffuseShape;
    float3 F = FresnelSchlick(dotHV, lobes.F0Rgb);
    float3 specSingle = F * lobes.specularSingleShape;
    float3 specMulti = lobes.specularMultiShape * fMulti;

    return (diffuseRgb + specSingle + specMulti) * saturate(dotNL);
}
float3 reconstructRGB_Heitz(BRDFLobes lobes, MaterialBRDF material, float dotNL)
{
    float3 diffuseRgb = material.albedo * lobes.diffuseShape;
    float3 specularRgb = (lobes.specularSingleShape + lobes.specularMultiShape) * material.F0; // already full BSDF

    return (diffuseRgb + specularRgb) * saturate(dotNL);
}

template<typename RNG>
float3 evaluateBRDF(MaterialBRDF material, float3 normal, float3 viewDirection, float3 lightDirection, inout RNG rng, out float pdf)
{
    switch (material.brdfType)
    {
        case BRDF_CookTorr:{
                float3 H = normalize(viewDirection + lightDirection);
                float dotHV = saturate(dot(H, viewDirection));
                float dotNL = saturate(dot(normal, lightDirection));
                BRDFLobes lobes = CookTorrance(normal, viewDirection, lightDirection, material);
                pdf = 0.0f;
                return reconstructRGB(lobes, material, dotNL, dotHV, 0.0f.xxx);
            }
        case BRDF_FastMSX:{
                float3 H = normalize(viewDirection + lightDirection);
                float dotHV = saturate(dot(H, viewDirection));
                float dotNL = saturate(dot(normal, lightDirection));
                BRDFLobes lobes = FastMSX(normal, viewDirection, lightDirection, material);
                float3 F = FresnelSchlick(dotHV, lobes.F0Rgb);
                pdf = 0.0f;
                return reconstructRGB(lobes, material, dotNL, dotHV, F * F);
            }
        case BRDF_Heitz_GGX:
        case BRDF_Heitz_StudentT:
        case BRDF_Heitz_Beckmann:{
                float dotNL = saturate(dot(normal, lightDirection));
                BRDFLobes lobes = Heitz(normal, viewDirection, lightDirection, material, rng);
                pdf = max(lobes.specularSingleShape + lobes.specularMultiShape, 1e-6);
                return reconstructRGB_Heitz(lobes, material, dotNL);
            }
        case BRDF_GGX:
        default:
        {
            float3 H = normalize(viewDirection + lightDirection);
            float dotHV = saturate(dot(H, viewDirection));
            float dotNH = saturate(dot(normal, H));
            float dotNL = saturate(dot(normal, lightDirection));
            float dotNV = saturate(dot(normal, viewDirection));
            BRDFLobes lobes = evaluateBRDF_GGX(material, dotHV, dotNH, dotNL, dotNV);
            pdf = 0;
            return reconstructRGB(lobes, material, dotNL, dotHV, 0.0f.xxx);
        }
    }
}
/**
 * Evaluate the BRDF for the diffuse and specular BRDF components separately.
 * @param material       Material data describing BRDF.
 * @param dotHV          The dot product of the half-vector and view direction (range [-1, 1]).
 * @param dotNH          The dot product of the normal and half vector (range [-1, 1]).
 * @param dotNL          The dot product of the normal and light direction (range [-1, 1]).
 * @param dotNV          The dot product of the normal and view direction (range [-1, 1]).
 * @param [out] diffuse  The calculated diffuse component of the reflectance.
 * @param [out] specular The calculated specular component of the reflectance.
 */
void evaluateBRDFSplit(MaterialBRDF material, float dotHV, float dotNH, float dotNL, float dotNV, out float3 diffuse, out float3 specular)
{
    // Calculate diffuse component
    diffuse = evaluateLambert(material.albedo);

#ifndef DISABLE_SPECULAR_MATERIALS
    // Calculate specular component
    float3 f;
    specular = evaluateGGX(material.roughnessAlphaSqr, material.F0, dotHV, dotNH, dotNL, dotNV, f);

    // Add the weight of the diffuse compensation term
    diffuse *= diffuseCompensationTerm(f, dotHV);
    specular *= saturate(dotNL); // saturate(dotNL) = abs(dotNL) * Heaviside function for the upper hemisphere.
    diffuse *= saturate(dotNL);
#else
    specular = 0.0f.xxx;
    // Add the weight of the diffuse compensation term to prevent excessive brightness compared to specular
    diffuse *= diffuseCompensation(fresnel(0.04f.xxx, dotHV), dotHV);
    diffuse *= saturate(dotNL);
#endif
}

/**
 * Evaluate the BRDF for the diffuse and specular BRDF components separately.
 * @param material       Material data describing BRDF.
 * @param normal         Shading normal vector at current position (must be normalised).
 * @param viewDirection  Outgoing ray view direction (must be normalised).
 * @param lightDirection The direction to the sampled light (must be normalised).
 * @param [out] diffuse  The calculated diffuse component of the reflectance.
 * @param [out] specular The calculated specular component of the reflectance.
 */
void evaluateBRDFSplit(MaterialBRDF material, float3 normal, float3 viewDirection, float3 lightDirection, out float3 diffuse, out float3 specular)
{
    // Calculate diffuse component
    diffuse = evaluateLambert(material.albedo);

    // Calculate shading angles
    float dotNL = clamp(dot(normal, lightDirection), -1.0f, 1.0f);
    // Calculate half vector
    float3 halfVector = normalize(viewDirection + lightDirection);
    float dotHV = saturate(dot(halfVector, viewDirection));
#ifndef DISABLE_SPECULAR_MATERIALS
    float dotNH = clamp(dot(normal, halfVector), -1.0f, 1.0f);
    float dotNV = clamp(dot(normal, viewDirection), -1.0f, 1.0f);

    // Calculate specular component
    float3 f;
    specular = evaluateGGX(material.roughnessAlphaSqr, material.F0, dotHV, dotNH, dotNL, dotNV, f);

    // Add the weight of the diffuse compensation term
    diffuse *= diffuseCompensationTerm(f, dotHV);
    specular *= saturate(dotNL); // saturate(dotNL) = abs(dotNL) * Heaviside function for the upper hemisphere.
    diffuse *= saturate(dotNL);
#else
    specular = 0.0f.xxx;
    // Add the weight of the diffuse compensation term to prevent excessive brightness compared to specular
    diffuse *= diffuseCompensation(fresnel(0.04f.xxx, dotHV), dotHV);
    diffuse *= saturate(dotNL);
#endif
}

/**
 * Evaluate the diffuse component of the BRDF.
 * @param material Material data describing BRDF.
 * @param dotHV    The dot product of the half-vector and view direction (range [-1, 1]).
 * @param dotNL    The dot product of the normal and light direction (range [-1, 1]).
 * @return The calculated reflectance.
 */
float3 evaluateBRDFDiffuse(MaterialBRDF material, float dotHV, float dotNL)
{
    // Calculate diffuse component
    float3 diffuse = evaluateLambert(material.albedo);

    // Add the weight of the diffuse compensation term to prevent excessive brightness compared to specular
#ifndef DISABLE_SPECULAR_MATERIALS
    diffuse *= diffuseCompensation(fresnel(material.F0, dotHV), dotHV);
#else
    diffuse *= diffuseCompensation(fresnel(0.04f.xxx, dotHV), dotHV);
#endif
    diffuse *= saturate(dotNL);
    return diffuse;
}

#ifndef DISABLE_SPECULAR_MATERIALS
/**
 * Evaluate the specular component of the BRDF.
 * @param material Material data describing BRDF.
 * @param dotNH    The dot product of the normal and half vector (range [-1, 1]).
 * @param dotNL    The dot product of the normal and light direction (range [-1, 1]).
 * @param dotHV    The dot product of the half-vector and view direction (range [-1, 1]).
 * @param dotNV    The dot product of the normal and view direction (range [-1, 1]).
 * @return The calculated reflectance.
 */
float3 evaluateBRDFSpecular(MaterialBRDF material, float dotHV, float dotNH, float dotNL, float dotNV)
{
    // Calculate specular component
    float3 f;
    float3 specular = evaluateGGX(material.roughnessAlphaSqr, material.F0, dotHV, dotNH, dotNL, dotNV, f);

    specular *= saturate(dotNL); // saturate(dotNL) = abs(dotNL) * Heaviside function for the upper hemisphere.
    return specular;
}
#endif

/**
 * NDF filtering for specular AA using given derivatives for ray differentials.
 * [Y. Tokuyoshi and A. S. Kaplanyan 2021 "Stable Geometric Specular Antialiasing with Projected-Space NDF Filtering"]
 * @param dndu   Derivaive of normals in the horizontal axis of screen.
 * @param dndv   Derivaive of normals in the vertical axis of screen.
 * @param alpha2 Alpha roughness squared.
 * @return Filtered alpha roughness squared. The range is [0, 1].
 */
float IsotropicNDFFiltering(const float3 dndu, const float3 dndv, const float alpha2)
{
    const float SIGMA2 = 0.15915494;
    const float KAPPA = 0.18;
    const float kernelRoughnessAlpha2 = SIGMA2 * (dot(dndu, dndu) + dot(dndv, dndv));
    const float clampedKernelRoughnessAlpha2 = min(kernelRoughnessAlpha2, KAPPA);
    const float filteredRoughnessAlpha2 = saturate(alpha2 + clampedKernelRoughnessAlpha2);
    return filteredRoughnessAlpha2;
}

#endif // MATERIAL_EVALUATION_HLSL
