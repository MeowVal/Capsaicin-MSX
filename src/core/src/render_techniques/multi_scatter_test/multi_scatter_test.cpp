#include "multi_scatter_test.h"
#include "capsaicin_internal.h"
#include "components/brdf_lut/brdf_lut.h"
#include "components/light_sampler/light_sampler_switcher.h"
#include "components/random_number_generator/random_number_generator.h"

namespace Capsaicin
{

/***** Must call base class giving unique string name for this technique *****/
MultiScatterTests::MultiScatterTests()
    : RenderTechnique("MultiScatterTests")
{}

MultiScatterTests::~MultiScatterTests() 
{
    /***** Must clean-up any created member variables/data               *****/
    terminate();
}

RenderOptionList MultiScatterTests::getRenderOptions() noexcept 
{
    RenderOptionList newOptions;
    /***** Push any desired options to the returned list here (else just 'return {}')  *****/
    /***** Example (using provided helper RENDER_OPTION_MAKE):                         *****/
    /*****  newOptions.emplace(RENDER_OPTION_MAKE(my_technique_enable, options));      *****/
    newOptions.emplace(RENDER_OPTION_MAKE(brdf_model, options_));
    return newOptions;
}


MultiScatterTests::RenderOptions MultiScatterTests::convertOptions(RenderOptionList const &options) noexcept
{
    /***** Optional function only required if actually providing RenderOptions *****/
    RenderOptions newOptions;
    /***** Used to convert options between external string/variant and internal data type 'RenderOptions'
     * *****/
    /***** Example: (using provided helper RENDER_OPTION_GET): *****/
    /*****  RENDER_OPTION_GET(my_technique_enable, newOptions, options); *****/
    RENDER_OPTION_GET(brdf_model, newOptions, options);
    return newOptions;
}

ComponentList MultiScatterTests::getComponents() const noexcept 
{
    ComponentList components;
    /***** Push any desired Components to the returned list here (else just 'return {}' or dont override)
     * *****/
    /***** Example: if corresponding header is already included (using provided helper COMPONENT_MAKE):
     * *****/
    /*****  components.emplace_back(COMPONENT_MAKE(TypeOfComponent)); *****/
    components.emplace_back(COMPONENT_MAKE(LightSamplerSwitcher));
    components.emplace_back(COMPONENT_MAKE(RandomNumberGenerator));
    components.emplace_back(COMPONENT_MAKE(BrdfLut));
    return components;
}

SharedBufferList MultiScatterTests::getSharedBuffers() const noexcept 
{
    SharedBufferList buffers;
    /***** Push any desired Buffers to the returned list here (else just 'return {}' or dont override)
     * *****/
    return buffers;
}

SharedTextureList MultiScatterTests::getSharedTextures() const noexcept 
{
    SharedTextureList textures;
    /***** Push any desired shared textures to the returned list here (else just 'return {}' or dont
     * override) *****/
    textures.push_back({.name = "GBufferNormal",
        .access               = SharedTexture::Access::Write,
        .flags                = SharedTexture::Flags::None,
        .format               = DXGI_FORMAT_R16G16B16A16_FLOAT});
    textures.push_back({.name = "GBufferAlbedo",
        .access               = SharedTexture::Access::Write,
        .flags                = SharedTexture::Flags::None,
        .format               = DXGI_FORMAT_R16G16B16A16_FLOAT});
    textures.push_back({.name = "GBufferMaterial",
        .access               = SharedTexture::Access::Write,
        .flags                = SharedTexture::Flags::None,
        .format               = DXGI_FORMAT_R16G16B16A16_FLOAT});
    textures.push_back({.name = "Depth", .access = SharedTexture::Access::ReadWrite});
    return textures;
}

DebugViewList MultiScatterTests::getDebugViews() const noexcept 
{
    DebugViewList views;
    /***** Push any desired Debug Views to the returned list here (else just 'return {}' or dont override)
     * *****/
    views.emplace_back("GBufferNormal");
    views.emplace_back("GBufferAlbedo");
    views.emplace_back("GBufferMaterial");
    return views;
}

bool MultiScatterTests::init(CapsaicinInternal const &capsaicin) noexcept 
{
    /***** Perform any required initialisation operations here *****/
    // Programs (Capsaicin auto-loads .vert/.frag/.hlsl)
    gbufferProgram_ = capsaicin.createProgram("render_techniques/multi_scatter_test/gbuffer");
    shadingProgram_ = capsaicin.createProgram("render_techniques/multi_scatter_test/brdf_shading");

    if (!gbufferProgram_ || !shadingProgram_)
    {
        return false;
    }

    // G-buffer draw state
    GfxDrawState gbufState;
    gfxDrawStateSetColorTarget(gbufState, 0, capsaicin.getSharedTexture("GBufferNormal").getFormat());
    gfxDrawStateSetColorTarget(gbufState, 1, capsaicin.getSharedTexture("GBufferAlbedo").getFormat());
    gfxDrawStateSetColorTarget(gbufState, 2, capsaicin.getSharedTexture("GBufferMaterial").getFormat());
    gfxDrawStateSetDepthStencilTarget(gbufState, capsaicin.getSharedTexture("Depth").getFormat());
    gfxDrawStateSetPrimitiveTopologyType(gbufState, D3D12_PRIMITIVE_TOPOLOGY_TYPE_TRIANGLE);
    gbufferKernel_ = gfxCreateGraphicsKernel(gfx_, gbufferProgram_, gbufState);

    // Shading draw state (fullscreen)
    GfxDrawState shadeState;
    gfxDrawStateSetColorTarget(shadeState, 0, capsaicin.getSharedTexture("Color").getFormat());
    gfxDrawStateSetPrimitiveTopologyType(shadeState, D3D12_PRIMITIVE_TOPOLOGY_TYPE_TRIANGLE);
    shadingKernel_ = gfxCreateGraphicsKernel(gfx_, shadingProgram_, shadeState);

    frameCB_ = gfxCreateBuffer(capsaicin.getGfx(), sizeof(RenderOptions), nullptr, kGfxCpuAccess_Write);
    frameCB_.setStride(sizeof(RenderOptions));

    /*auto const                light_sampler = capsaicin.getComponent<LightSampler>();
    std::vector const         defines(light_sampler->getShaderDefines(capsaicin));
    std::vector<char const *> base_defines;
    base_defines.reserve(defines.size());
    for (auto const &i : defines)
    {
        base_defines.push_back(i.c_str());
    }
    if (capsaicin.hasSharedTexture("OcclusionAndBentNormal"))
    {
        base_defines.push_back("HAS_OCCLUSION");
    }*/

    
    return !!gbufferKernel_ && !!shadingKernel_ && !!frameCB_;
}

void MultiScatterTests::render(CapsaicinInternal &capsaicin) noexcept 
{
    /***** If any options are provided they should be checked for changes here *****/
    /***** Example:                                                            *****/
    /*****  RenderOptions newOptions = convertOptions(capsaicin.getOptions()); *****/
    /*****  Check for changes and handle accordingly                           *****/
    /*****  options = newOptions;                                              *****/
    /***** Perform any required rendering operations here                      *****/
    /***** Debug Views can be checked with 'capsaicin.getCurrentDebugView()'   *****/

    RenderOptions options = convertOptions(capsaicin.getOptions());
    auto const debug_view = capsaicin.getCurrentDebugView();
    options_    = options;

    debug_view_              = debug_view;

    if (frameCB_.getCpuAccess() == kGfxCpuAccess_Write)
    {
        auto *ptr = gfxBufferGetData<RenderOptions>(gfx_, frameCB_);
        *ptr      = options_;
    }
    
    uint2 dim = capsaicin.getRenderDimensions();

    // ---------- G-BUFFER PASS ----------
    gfxCommandBindColorTarget(gfx_, 0, capsaicin.getSharedTexture("GBufferNormal"));
    gfxCommandBindColorTarget(gfx_, 1, capsaicin.getSharedTexture("GBufferAlbedo"));
    gfxCommandBindColorTarget(gfx_, 2, capsaicin.getSharedTexture("GBufferMaterial"));
    gfxCommandBindDepthStencilTarget(gfx_, capsaicin.getSharedTexture("Depth"));
    gfxCommandSetViewport(gfx_, 0.0f, 0.0f, (float)dim.x, (float)dim.y);
    gfxCommandSetScissorRect(gfx_, 0, 0, (int32_t)dim.x, (int32_t)dim.y);
    gfxCommandBindKernel(gfx_, gbufferKernel_);
    gfxCommandBindVertexBuffer(gfx_, capsaicin.getVertexBuffer());
    gfxCommandBindIndexBuffer(gfx_, capsaicin.getIndexBuffer());
    gfxCommandDrawIndexed(gfx_, capsaicin.getTriangleCount() * 3);

    // ---------- SHADING PASS ----------
    gfxCommandBindColorTarget(gfx_, 0, capsaicin.getSharedTexture("Color"));
    gfxCommandBindDepthStencilTarget(gfx_, GfxTexture {}); // no depth

    gfxCommandSetViewport(gfx_, 0.0f, 0.0f, (float)dim.x, (float)dim.y);
    gfxCommandSetScissorRect(gfx_, 0, 0, (int32_t)dim.x, (int32_t)dim.y);
    gfxCommandBindKernel(gfx_, shadingKernel_);
    gfxProgramSetParameter(gfx_, shadingProgram_, "GNormal", capsaicin.getSharedTexture("GBufferNormal"));
    gfxProgramSetParameter(gfx_, shadingProgram_, "GAlbedo", capsaicin.getSharedTexture("GBufferAlbedo"));
    gfxProgramSetParameter(gfx_, shadingProgram_, "GMaterial", capsaicin.getSharedTexture("GBufferMaterial"));
    gfxProgramSetParameter(gfx_, shadingProgram_, "FrameCB", frameCB_);

    gfxProgramSetParameter(gfx_, shadingProgram_, "g_BufferDimensions", dim);
    gfxProgramSetParameter(gfx_, shadingProgram_, "g_Camera", capsaicin.getCamera());

    gfxCommandDraw(gfx_, 3);
}

void MultiScatterTests::terminate() noexcept 
{
    /***** Cleanup any created CPU or GPU resources                     *****/
    gfxDestroyProgram(gfx_, gbufferProgram_);
    gfxDestroyProgram(gfx_, shadingProgram_);
    gfxDestroyKernel(gfx_, shadingKernel_);
    gfxDestroyBuffer(gfx_, frameCB_);
    gfxDestroyTexture(gfx_, depth_buffer_);
    gfxDestroyTexture(gfx_, irradiance_buffer_);
    gfxDestroyBuffer(gfx_, draw_command_buffer_);
    gfxDestroyBuffer(gfx_, dispatch_command_buffer_);

}

void MultiScatterTests::renderGUI(CapsaicinInternal &capsaicin) const noexcept 
{
    /***** Add any UI drawing commands here                             *****/
    int model = options_.brdf_model;
    if (ImGui::Combo("BRDF Model", &model, "CookTorrance\0Fast-MSX\0Heitz\0GGX\0"))
    {
        capsaicin.setOption("brdf_model", model);
    }
}

} // namespace Capsaicin
