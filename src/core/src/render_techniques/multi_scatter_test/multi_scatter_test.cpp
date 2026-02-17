#include "multi_scatter_test.h"
#include "capsaicin_internal.h"
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
    return textures;
}

DebugViewList MultiScatterTests::getDebugViews() const noexcept 
{
    DebugViewList views;
    /***** Push any desired Debug Views to the returned list here (else just 'return {}' or dont override)
     * *****/
    return views;
}

bool MultiScatterTests::init(CapsaicinInternal const &capsaicin) noexcept 
{
    /***** Perform any required initialisation operations here *****/
    return true;
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
}

void MultiScatterTests::terminate() noexcept 
{
    /***** Cleanup any created CPU or GPU resources                     *****/
}

void MultiScatterTests::renderGUI(CapsaicinInternal &capsaicin) const noexcept 
{
    /***** Add any UI drawing commands here                             *****/
}



} // namespace Capsaicin
