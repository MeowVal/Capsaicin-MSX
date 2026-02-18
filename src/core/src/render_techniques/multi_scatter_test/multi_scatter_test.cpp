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
	textures.push_back({.name = "MSXColor",
		.access               = SharedTexture::Access::Write,
		.flags                = SharedTexture::Flags::None,
		.format               = DXGI_FORMAT_R16G16B16A16_FLOAT});
	/*textures.push_back({.name = "Depth",
		.access               = SharedTexture::Access::ReadWrite,
		.flags                = SharedTexture::Flags::None,
		.format               = DXGI_FORMAT_D32_FLOAT});*/
	return textures;
}

DebugViewList MultiScatterTests::getDebugViews() const noexcept 
{
	DebugViewList views;
	/***** Push any desired Debug Views to the returned list here (else just 'return {}' or dont override)
	 * *****/
	views.emplace_back("MSXColor");
	return views;
}

bool MultiScatterTests::init(CapsaicinInternal const &capsaicin) noexcept 
{
	/***** Perform any required initialisation operations here *****/
	// Programs (Capsaicin auto-loads .vert/.frag/.hlsl)
	shadingProgram_ = capsaicin.createProgram("render_techniques/multi_scatter_test/brdf_shading");

	if (!shadingProgram_)
	{
		return false;
	}

	// Shading draw state (fullscreen)
	GfxDrawState shadeState;
	//gfxDrawStateSetDepthStencilTarget(shadeState, capsaicin.getSharedTexture("Depth").getFormat());
	gfxDrawStateSetColorTarget(shadeState, 0, capsaicin.getSharedTexture("MSXColor").getFormat());
	gfxDrawStateSetPrimitiveTopologyType(shadeState, D3D12_PRIMITIVE_TOPOLOGY_TYPE_TRIANGLE);
	shadingKernel_ = gfxCreateGraphicsKernel(gfx_, shadingProgram_, shadeState);

	frameCB_ = gfxCreateBuffer(capsaicin.getGfx(), sizeof(FrameCBData), nullptr, kGfxCpuAccess_Write);
    frameCB_.setStride(sizeof(FrameCBData));
	//auto depth = capsaicin.getSharedTexture("Depth");
	auto color = capsaicin.getSharedTexture("MSXColor");
	//assert(depth);
	assert(color);

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

	
	return !!shadingKernel_ && !!frameCB_;
}

void MultiScatterTests::render([[maybe_unused]] CapsaicinInternal &capsaicin) noexcept
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
		auto *ptr = gfxBufferGetData<FrameCBData>(gfx_, frameCB_);

		ptr->brdf_model = options_.brdf_model;

		auto const &cam = capsaicin.getCameraMatrices(capsaicin.getOption<bool>("taa_enable"));

		ptr->view_proj_inv = cam.inv_view_projection;
	}
	
	uint2 dim = capsaicin.getRenderDimensions();

	// ---------- SHADING PASS ----------
	//auto d     = capsaicin.getSharedTexture("Depth");
	auto color = capsaicin.getSharedTexture("MSXColor");
	assert(color);
	//assert(d);
	gfxCommandBindColorTarget(gfx_, 0, capsaicin.getSharedTexture("MSXColor"));
	//gfxCommandBindDepthStencilTarget(gfx_, capsaicin.getSharedTexture("Depth")); // no depth

	gfxCommandSetViewport(gfx_, 0.0f, 0.0f, (float)dim.x, (float)dim.y);
	gfxCommandSetScissorRect(gfx_, 0, 0, (int32_t)dim.x, (int32_t)dim.y);
	gfxCommandBindKernel(gfx_, shadingKernel_);
	gfxProgramSetParameter(gfx_, shadingProgram_, "FrameCB", frameCB_);
	gfxProgramSetParameter(gfx_, shadingProgram_, "g_BufferDimensions", dim);
	gfxProgramSetParameter(gfx_, shadingProgram_, "g_Camera", capsaicin.getCamera());

	gfxCommandDraw(gfx_, 3);
}

void MultiScatterTests::terminate() noexcept 
{
	/***** Cleanup any created CPU or GPU resources                     *****/
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
