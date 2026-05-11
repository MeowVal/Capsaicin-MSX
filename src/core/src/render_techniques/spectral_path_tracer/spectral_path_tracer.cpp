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

#include "spectral_path_tracer.h"

#include "capsaicin_internal.h"
#include "components/light_builder/light_builder.h"
#include "components/light_sampler/light_sampler_switcher.h"
#include "components/random_number_generator/random_number_generator.h"
#include "components/stratified_sampler/stratified_sampler.h"
#pragma warning(push)
#pragma warning(disable : 4305)
#include "render_techniques/spectral_path_tracer/rgb2spec_bt709_64.h"
#pragma warning(pop)
#include "spectral_cmf.h"


auto const *kSpectralPTRaygenShaderName       = "SpectralPTRaygen";
auto const *kSpectralPTMissShaderName         = "SpectralPTMiss";
auto const *kSpectralPTShadowMissShaderName   = "SpectralPTShadowMiss";
auto const *kSpectralPTAnyHitShaderName       = "SpectralPTAnyHit";
auto const *kSpectralPTShadowAnyHitShaderName = "SpectralPTShadowAnyHit";
auto const *kSpectralPTClosestHitShaderName   = "SpectralPTClosestHit";
auto const *kSpectralPTHitGroupName           = "SpectralPTHitGroup";
auto const *kSpectralPTShadowHitGroupName     = "SpectralPTShadowHitGroup";

namespace Capsaicin
{
SpectralPT::SpectralPT()
    : RenderTechnique("Spectral Path Tracer")
{}

SpectralPT::~SpectralPT()
{
    SpectralPT::terminate();
}

RenderOptionList SpectralPT::getRenderOptions() noexcept
{
    RenderOptionList newOptions;
    newOptions.emplace(RENDER_OPTION_MAKE(brdf_model, options));
    newOptions.emplace(RENDER_OPTION_MAKE(spectral_pt_bounce_count, options));
    newOptions.emplace(RENDER_OPTION_MAKE(spectral_pt_min_rr_bounces, options));
    newOptions.emplace(RENDER_OPTION_MAKE(spectral_pt_sample_count, options));
    newOptions.emplace(RENDER_OPTION_MAKE(spectral_pt_disable_albedo_materials, options));
    newOptions.emplace(RENDER_OPTION_MAKE(spectral_pt_disable_direct_lighting, options));
    newOptions.emplace(RENDER_OPTION_MAKE(spectral_pt_disable_specular_materials, options));
    newOptions.emplace(RENDER_OPTION_MAKE(spectral_pt_disable_alpha_testing, options));
    newOptions.emplace(RENDER_OPTION_MAKE(spectral_pt_nee_only, options));
    newOptions.emplace(RENDER_OPTION_MAKE(spectral_pt_disable_nee, options));
    newOptions.emplace(RENDER_OPTION_MAKE(spectral_pt_use_dxr10, options));
    newOptions.emplace(RENDER_OPTION_MAKE(spectral_pt_accumulate, options));
    return newOptions;
}

SpectralPT::RenderOptions SpectralPT::convertOptions(RenderOptionList const &options) noexcept
{
    RenderOptions newOptions;
    RENDER_OPTION_GET(brdf_model, newOptions, options)
    RENDER_OPTION_GET(spectral_pt_bounce_count, newOptions, options)
    RENDER_OPTION_GET(spectral_pt_min_rr_bounces, newOptions, options)
    RENDER_OPTION_GET(spectral_pt_sample_count, newOptions, options)
    RENDER_OPTION_GET(spectral_pt_disable_albedo_materials, newOptions, options)
    RENDER_OPTION_GET(spectral_pt_disable_direct_lighting, newOptions, options)
    RENDER_OPTION_GET(spectral_pt_disable_specular_materials, newOptions, options)
    RENDER_OPTION_GET(spectral_pt_disable_alpha_testing, newOptions, options)
    RENDER_OPTION_GET(spectral_pt_nee_only, newOptions, options)
    RENDER_OPTION_GET(spectral_pt_disable_nee, newOptions, options)
    RENDER_OPTION_GET(spectral_pt_use_dxr10, newOptions, options)
    RENDER_OPTION_GET(spectral_pt_accumulate, newOptions, options)
    return newOptions;
}

ComponentList SpectralPT::getComponents() const noexcept
{
    ComponentList components;
    components.emplace_back(COMPONENT_MAKE(LightSamplerSwitcher));
    components.emplace_back(COMPONENT_MAKE(StratifiedSampler));
    components.emplace_back(COMPONENT_MAKE(RandomNumberGenerator));
    return components;
}

SharedTextureList SpectralPT::getSharedTextures() const noexcept
{
    SharedTextureList textures;
    textures.push_back({"Color", SharedTexture::Access::Write});
    return textures;
}

bool SpectralPT::init(CapsaicinInternal const &capsaicin) noexcept
{
    rez           = sRGBToSpectrumTable_Res;
    rayCameraData = gfxCreateBuffer<RayCamera>(gfx_, 1, nullptr, kGfxCpuAccess_Write);
    rayCameraData.setName("Capsaicin_PT_RayCamera");
    accumulationBuffer =
        capsaicin.createRenderTexture(DXGI_FORMAT_R32G32B32A32_FLOAT, "PT_AccumulationBuffer");
    std::vector<glm::vec4> flattened(rez * rez * rez);
    for (int i = 0; i < 3; i++)
    {
        rgb2SpecLUT[i] = gfxCreateTexture2D(
            gfx_, rez, rez * rez, DXGI_FORMAT_R32G32B32A32_FLOAT, 1, nullptr, D3D12_RESOURCE_FLAG_NONE);

        

        for (uint32_t z = 0; z < rez; z++)
        {
            for (uint32_t y = 0; y < rez; y++)
            {
                for (uint32_t x = 0; x < rez; x++)
                {
                    uint32_t dstIndex = x + rez * (y + rez * z);

                    flattened[dstIndex] = glm::vec4(sRGBToSpectrumTable_Data[i][z][y][x][0],
                        sRGBToSpectrumTable_Data[i][z][y][x][1], sRGBToSpectrumTable_Data[i][z][y][x][2],1.0f);
                }
            }
        }
        
        GfxBuffer upload = gfxCreateBuffer(gfx_, 
            flattened.size() * sizeof(glm::vec4), 
            flattened.data(),  
            kGfxCpuAccess_Write);
        gfxCommandCopyBufferToTexture(gfx_, rgb2SpecLUT[i], upload);
        gfxTextureSetResourceState(gfx_, rgb2SpecLUT[i], D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE);
    }

    zNodes = gfxCreateTexture2D(gfx_,
        rez, // width
        1,  // height
        DXGI_FORMAT_R32G32B32A32_FLOAT,
        1,       // mip levels
        nullptr, // clear value
        D3D12_RESOURCE_FLAG_NONE);
    std::vector<glm::vec4> zNodesData(rez);
    for (uint32_t i = 0; i < rez; i++)
    {
        zNodesData[i] = glm::vec4(sRGBToSpectrumTable_Scale[i], 0, 0, 0);
    }
    GfxBuffer uploadZ = gfxCreateBuffer(gfx_, zNodesData.size() * sizeof(glm::vec4), // rez * 16 bytes
        zNodesData.data(), kGfxCpuAccess_Write);
    gfxCommandCopyBufferToTexture(gfx_, zNodes, uploadZ);
    gfxTextureSetResourceState(gfx_, zNodes, D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE);

    cieXbuf = gfxCreateBuffer(gfx_, 95 * sizeof(float), CIE_X);
    cieYbuf = gfxCreateBuffer(gfx_, 95 * sizeof(float), CIE_Y);
    cieZbuf = gfxCreateBuffer(gfx_, 95 * sizeof(float), CIE_Z);
    cieD65  = gfxCreateBuffer(gfx_, 95 * sizeof(float), cie_d65);

    spectral_pt_program_ = capsaicin.createProgram(getProgramName());
    return initKernels(capsaicin);
}

void SpectralPT::render(CapsaicinInternal &capsaicin) noexcept
{
    RenderOptions const newOptions         = convertOptions(capsaicin.getOptions());
    auto const          lightSampler       = capsaicin.getComponent<LightSamplerSwitcher>();
    auto const          lightBuilder       = capsaicin.getComponent<LightBuilder>();
    auto const          stratified_sampler = capsaicin.getComponent<StratifiedSampler>();
    auto const          rng                = capsaicin.getComponent<RandomNumberGenerator>();

    // Check if options change requires kernel recompile
    bool const recompile = needsRecompile(capsaicin, newOptions);

    // Check if we can continue to accumulate samples
    auto const renderDimensions = capsaicin.getRenderDimensions();
    bool const accumulate = options.spectral_pt_accumulate && !recompile && !capsaicin.getAnimationUpdated()
                         && !capsaicin.getRenderDimensionsUpdated() && !capsaicin.getCameraUpdated()
                         && options.spectral_pt_bounce_count == newOptions.spectral_pt_bounce_count
                         && options.spectral_pt_min_rr_bounces == newOptions.spectral_pt_min_rr_bounces
                         && !capsaicin.getMeshesUpdated() && !capsaicin.getTransformsUpdated()
                         && !lightBuilder->getLightsUpdated()
                         && !lightSampler->getLightSettingsUpdated(capsaicin)
                         && capsaicin.getFrameIndex() > 0;

    // Update the history
    options = newOptions;

    if (!accumulate)
    {
        auto const camera = capsaicin.getCamera();
        cameraData        = caclulateRayCamera(
            {camera.eye, camera.center, camera.up, camera.aspect, camera.fovY, camera.nearZ, camera.farZ},
            renderDimensions);
    }

    if (recompile)
    {
        gfxDestroyKernel(gfx_, spectral_pt_kernel_);
        gfxDestroySbt(gfx_, spectral_pt_sbt_);
        initKernels(capsaicin);
    }

    if (capsaicin.getRenderDimensionsUpdated())
    {
        accumulationBuffer = capsaicin.resizeRenderTexture(accumulationBuffer, false);
    }

    // Bind the shader parameters
    uint2 const bufferDimensions = capsaicin.getRenderDimensions();
    gfxProgramSetParameter(gfx_, spectral_pt_program_, "g_BufferDimensions", bufferDimensions);
    gfxProgramSetParameter(gfx_, spectral_pt_program_, "g_FrameIndex", capsaicin.getFrameIndex());
    gfxProgramSetParameter(gfx_, spectral_pt_program_, "g_RayCamera", cameraData);
    gfxProgramSetParameter(gfx_, spectral_pt_program_, "g_BounceCount", options.spectral_pt_bounce_count);
    gfxProgramSetParameter(
        gfx_, spectral_pt_program_, "g_BounceRRCount", options.spectral_pt_min_rr_bounces);
    gfxProgramSetParameter(gfx_, spectral_pt_program_, "g_SampleCount", options.spectral_pt_sample_count);
    gfxProgramSetParameter(gfx_, spectral_pt_program_, "g_Accumulate", accumulate ? 1 : 0);

    gfxProgramSetTexture(gfx_, spectral_pt_program_, "g_RGB2SpecLUT0", rgb2SpecLUT[0]);
    gfxProgramSetTexture(gfx_, spectral_pt_program_, "g_RGB2SpecLUT1", rgb2SpecLUT[1]);
    gfxProgramSetTexture(gfx_, spectral_pt_program_, "g_RGB2SpecLUT2", rgb2SpecLUT[2]);
    gfxProgramSetParameter(gfx_, spectral_pt_program_, "g_ZNodes", zNodes);
    gfxProgramSetParameter(gfx_, spectral_pt_program_, "g_Res", rez);

    gfxProgramSetParameter(gfx_, spectral_pt_program_, "g_CIE_X", cieXbuf);
    gfxProgramSetParameter(gfx_, spectral_pt_program_, "g_CIE_Y", cieYbuf);
    gfxProgramSetParameter(gfx_, spectral_pt_program_, "g_CIE_Z", cieZbuf);
    gfxProgramSetParameter(gfx_, spectral_pt_program_, "g_CieD65", cieD65);

    stratified_sampler->addProgramParameters(capsaicin, spectral_pt_program_);
    rng->addProgramParameters(capsaicin, spectral_pt_program_);

    gfxProgramSetParameter(gfx_, spectral_pt_program_, "g_InstanceBuffer", capsaicin.getInstanceBuffer());
    gfxProgramSetParameter(gfx_, spectral_pt_program_, "g_TransformBuffer", capsaicin.getTransformBuffer());
    gfxProgramSetParameter(gfx_, spectral_pt_program_, "g_IndexBuffer", capsaicin.getIndexBuffer());
    gfxProgramSetParameter(gfx_, spectral_pt_program_, "g_VertexBuffer", capsaicin.getVertexBuffer());
    gfxProgramSetParameter(gfx_, spectral_pt_program_, "g_VertexDataIndex", capsaicin.getVertexDataIndex());
    gfxProgramSetParameter(gfx_, spectral_pt_program_, "g_MaterialBuffer", capsaicin.getMaterialBuffer());

    gfxProgramSetParameter(gfx_, spectral_pt_program_, "g_AccumulationBuffer", accumulationBuffer);
    gfxProgramSetParameter(
        gfx_, spectral_pt_program_, "g_OutputBuffer", capsaicin.getSharedTexture("Color"));

    gfxProgramSetParameter(gfx_, spectral_pt_program_, "g_Scene", capsaicin.getAccelerationStructure());

    gfxProgramSetParameter(
        gfx_, spectral_pt_program_, "g_EnvironmentBuffer", capsaicin.getEnvironmentBuffer());
    auto const &textures = capsaicin.getTextures();
    gfxProgramSetParameter(gfx_, spectral_pt_program_, "g_TextureMaps", textures.data(),
        static_cast<uint32_t>(textures.size()));

    gfxProgramSetParameter(gfx_, spectral_pt_program_, "g_TextureSampler", capsaicin.getLinearWrapSampler());

    lightSampler->addProgramParameters(capsaicin, spectral_pt_program_);

    // Render a reference for the current scene
    if (options.spectral_pt_use_dxr10)
    {
        setupSbt(capsaicin);
        gfxCommandBindKernel(gfx_, spectral_pt_kernel_);
        gfxCommandDispatchRays(gfx_, spectral_pt_sbt_, bufferDimensions.x, bufferDimensions.y, 1);
    }
    else
    {
        TimedSection const timed_section(*this, "SpectralPT");

        uint32_t const *num_threads  = gfxKernelGetNumThreads(gfx_, spectral_pt_kernel_);
        uint32_t const  num_groups_x = (bufferDimensions.x + num_threads[0] - 1) / num_threads[0];
        uint32_t const  num_groups_y = (bufferDimensions.y + num_threads[1] - 1) / num_threads[1];

        gfxCommandBindKernel(gfx_, spectral_pt_kernel_);
        gfxCommandDispatch(gfx_, num_groups_x, num_groups_y, 1);
    }
}

void SpectralPT::terminate() noexcept
{
    gfxDestroyBuffer(gfx_, rayCameraData);
    rayCameraData = {};
    gfxDestroyTexture(gfx_, accumulationBuffer);
    accumulationBuffer = {};

    gfxDestroyTexture(gfx_, zNodes);
    zNodes = {};
    gfxDestroyTexture(gfx_, rgb2SpecLUT[0]);
    gfxDestroyTexture(gfx_, rgb2SpecLUT[1]);
    gfxDestroyTexture(gfx_, rgb2SpecLUT[2]);
    rgb2SpecLUT[0] = {};
    rgb2SpecLUT[1] = {};
    rgb2SpecLUT[2] = {};

    gfxDestroyProgram(gfx_, spectral_pt_program_);
    spectral_pt_program_ = {};
    gfxDestroyKernel(gfx_, spectral_pt_kernel_);
    spectral_pt_kernel_ = {};
    gfxDestroySbt(gfx_, spectral_pt_sbt_);
    spectral_pt_sbt_ = {};
}

void SpectralPT::renderGUI(CapsaicinInternal &capsaicin) const noexcept
{
    ImGui::DragInt("Samples Per Pixel",
        reinterpret_cast<int32_t *>(&capsaicin.getOption<uint32_t>("spectral_pt_sample_count")), 1, 1, 30);
    auto &bounces = capsaicin.getOption<uint32_t>("spectral_pt_bounce_count");
    ImGui::DragInt("Bounces", reinterpret_cast<int32_t *>(&bounces), 1, 1, 30);
    auto &minBounces = capsaicin.getOption<uint32_t>("spectral_pt_min_rr_bounces");
    ImGui::DragInt(
        "Min Bounces", reinterpret_cast<int32_t *>(&minBounces), 1, 1, static_cast<int32_t>(bounces));
    minBounces = glm::min(minBounces, bounces);
    ImGui::Checkbox(
        "Disable Albedo Textures", &capsaicin.getOption<bool>("spectral_pt_disable_albedo_materials"));
    ImGui::Checkbox(
        "Disable Direct Lighting", &capsaicin.getOption<bool>("spectral_pt_disable_direct_lighting"));
    ImGui::Checkbox("NEE Only", &capsaicin.getOption<bool>("spectral_pt_nee_only"));
    ImGui::Checkbox("Disable NEE", &capsaicin.getOption<bool>("spectral_pt_disable_nee"));
    ImGui::Checkbox(
        "Disable Specular Materials", &capsaicin.getOption<bool>("spectral_pt_disable_specular_materials"));
    ImGui::Checkbox(
        "Disable Alpha Testing", &capsaicin.getOption<bool>("spectral_pt_disable_alpha_testing"));
    ImGui::Checkbox("Enable Accumulation", &capsaicin.getOption<bool>("spectral_pt_accumulate"));
}

bool SpectralPT::initKernels(CapsaicinInternal const &capsaicin) noexcept
{
    // Set up the base defines based on available features
    auto const                lightSampler = capsaicin.getComponent<LightSamplerSwitcher>();
    std::vector const         baseDefines(lightSampler->getShaderDefines(capsaicin));
    std::vector<char const *> defines;
    defines.reserve(baseDefines.size());
    for (auto const &i : baseDefines)
    {
        defines.push_back(i.c_str());
    }
    if (options.spectral_pt_disable_albedo_materials)
    {
        defines.push_back("DISABLE_ALBEDO_MATERIAL");
    }
    if (options.spectral_pt_disable_direct_lighting)
    {
        defines.push_back("DISABLE_DIRECT_LIGHTING");
    }
    if (options.spectral_pt_disable_specular_materials)
    {
        defines.push_back("DISABLE_SPECULAR_MATERIALS");
    }
    if (options.spectral_pt_disable_alpha_testing)
    {
        defines.push_back("DISABLE_ALPHA_TESTING");
    }
    if (options.spectral_pt_nee_only)
    {
        defines.push_back("DISABLE_NON_NEE");
    }
    if (options.spectral_pt_disable_nee)
    {
        defines.push_back("DISABLE_NEE");
    }
    if (options.spectral_pt_use_dxr10)
    {
        std::vector<char const *>                     exports;
        std::vector<char const *>                     subobjects;
        std::vector<std::string>                      defines_str;
        std::vector<std::string>                      exports_str;
        std::vector<std::string>                      subobjects_str;
        std::vector<GfxLocalRootSignatureAssociation> local_root_signature_associations;
        setupPTKernel(capsaicin, local_root_signature_associations, defines_str, exports_str, subobjects_str);
        for (auto &i : defines_str)
        {
            defines.push_back(i.c_str());
        }
        exports.reserve(exports_str.size());
        for (auto &i : exports_str)
        {
            exports.push_back(i.c_str());
        }
        subobjects.reserve(subobjects_str.size());
        for (auto &i : subobjects_str)
        {
            subobjects.push_back(i.c_str());
        }

        spectral_pt_kernel_ = gfxCreateRaytracingKernel(gfx_, spectral_pt_program_,
            local_root_signature_associations.data(),
            static_cast<uint32_t>(local_root_signature_associations.size()), exports.data(),
            static_cast<uint32_t>(exports.size()), subobjects.data(),
            static_cast<uint32_t>(subobjects.size()), defines.data(), static_cast<uint32_t>(defines.size()));

        uint32_t entry_count[kGfxShaderGroupType_Count] {
            capsaicin.getSbtStrideInEntries(kGfxShaderGroupType_Raygen),
            capsaicin.getSbtStrideInEntries(
                kGfxShaderGroupType_Miss), // two miss shaders for scattered and shadow ray
            gfxSceneGetInstanceCount(capsaicin.getScene())
                * capsaicin.getSbtStrideInEntries(
                    kGfxShaderGroupType_Hit), // two sets of hit groups for scattered and shadow ray
            capsaicin.getSbtStrideInEntries(kGfxShaderGroupType_Callable)};
        GfxKernel sbt_kernels[] {spectral_pt_kernel_};
        spectral_pt_sbt_ = gfxCreateSbt(gfx_, sbt_kernels, ARRAYSIZE(sbt_kernels), entry_count);
    }
    else
    {
        spectral_pt_kernel_ = gfxCreateComputeKernel(gfx_, spectral_pt_program_, "SpectralPT",
            defines.data(), static_cast<uint32_t>(defines.size()));
        spectral_pt_sbt_    = {};
    }
    return !!spectral_pt_program_;
}

bool SpectralPT::needsRecompile(
    CapsaicinInternal const &capsaicin, RenderOptions const &newOptions) const noexcept
{
    auto const lightSampler = capsaicin.getComponent<LightSamplerSwitcher>();

    // Check if options change requires kernel recompile
    bool const recompile =
        lightSampler->needsRecompile(capsaicin)
        || options.spectral_pt_disable_albedo_materials != newOptions.spectral_pt_disable_albedo_materials
        || options.spectral_pt_disable_direct_lighting != newOptions.spectral_pt_disable_direct_lighting
        || options.spectral_pt_disable_specular_materials
               != newOptions.spectral_pt_disable_specular_materials
        || options.spectral_pt_disable_alpha_testing != newOptions.spectral_pt_disable_alpha_testing
        || options.spectral_pt_nee_only != newOptions.spectral_pt_nee_only
        || options.spectral_pt_disable_nee != newOptions.spectral_pt_disable_nee
        || options.spectral_pt_use_dxr10 != newOptions.spectral_pt_use_dxr10;
    return recompile;
}

void SpectralPT::setupSbt(CapsaicinInternal const &capsaicin) const noexcept
{
    // Populate shader binding table
    gfxSbtSetShaderGroup(
        gfx_, spectral_pt_sbt_, kGfxShaderGroupType_Raygen, 0, kSpectralPTRaygenShaderName);
    gfxSbtSetShaderGroup(gfx_, spectral_pt_sbt_, kGfxShaderGroupType_Miss, 0, kSpectralPTMissShaderName);
    gfxSbtSetShaderGroup(
        gfx_, spectral_pt_sbt_, kGfxShaderGroupType_Miss, 1, kSpectralPTShadowMissShaderName);

    for (uint32_t i = 0; i < capsaicin.getRaytracingPrimitiveCount(); i++)
    {
        gfxSbtSetShaderGroup(gfx_, spectral_pt_sbt_, kGfxShaderGroupType_Hit,
            i * capsaicin.getSbtStrideInEntries(kGfxShaderGroupType_Hit) + 0, kSpectralPTHitGroupName);
        gfxSbtSetShaderGroup(gfx_, spectral_pt_sbt_, kGfxShaderGroupType_Hit,
            i * capsaicin.getSbtStrideInEntries(kGfxShaderGroupType_Hit) + 1, kSpectralPTShadowHitGroupName);
    }
}

void SpectralPT::setupPTKernel([[maybe_unused]] CapsaicinInternal const &capsaicin,
    [[maybe_unused]] std::vector<GfxLocalRootSignatureAssociation>       &local_root_signature_associations,
    [[maybe_unused]] std::vector<std::string> &defines, std::vector<std::string> &exports,
    std::vector<std::string> &subobjects) noexcept
{
    exports.emplace_back(kSpectralPTRaygenShaderName);
    exports.emplace_back(kSpectralPTMissShaderName);
    exports.emplace_back(kSpectralPTShadowMissShaderName);
    exports.emplace_back(kSpectralPTAnyHitShaderName);
    exports.emplace_back(kSpectralPTShadowAnyHitShaderName);
    exports.emplace_back(kSpectralPTClosestHitShaderName);

    subobjects.emplace_back("MyShaderConfig");
    subobjects.emplace_back("MyPipelineConfig");
    subobjects.emplace_back(kSpectralPTHitGroupName);
    subobjects.emplace_back(kSpectralPTShadowHitGroupName);
}

char const *SpectralPT::getProgramName() noexcept
{
    return "render_techniques/spectral_path_tracer/spectral_path_tracer";
}
} // namespace Capsaicin
