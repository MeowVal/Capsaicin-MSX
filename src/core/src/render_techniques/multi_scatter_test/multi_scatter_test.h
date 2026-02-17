#pragma once

#include "render_technique.h"

namespace Capsaicin
{
class MultiScatterTests : public RenderTechnique
{
public:
    /***** Must call base class giving unique string name for this technique *****/
    MultiScatterTests();

    ~MultiScatterTests() override;
  
    

    RenderOptionList getRenderOptions() noexcept override;
    

    struct RenderOptions
    {
        /***** Any member variable options can be added here.         *****/
        /***** This struct can be entirely omitted if not being used. *****/
        /***** This represent the internal format of options where as 'RenderOptionList' has these stored as
         * strings and variants *****/
        /***** Example: bool my_technique_enable;                     *****/
        bool CookTorrance = true; /**< Example option to toggle between Cook-Torrance and Blinn-Phong BRDFs */
    };

    static RenderOptions convertOptions(RenderOptionList const &options) noexcept;
    
    ComponentList getComponents() const noexcept override;
    

    SharedBufferList getSharedBuffers() const noexcept override;
    

    SharedTextureList getSharedTextures() const noexcept override;
   
    DebugViewList getDebugViews() const noexcept override;
    

    bool init(CapsaicinInternal const &capsaicin) noexcept override;
  

    void render(CapsaicinInternal &capsaicin) noexcept override;
    

    void terminate() noexcept override;
    

    void renderGUI(CapsaicinInternal &capsaicin) const noexcept override;
    

protected:
    /***** Internal member data can be added here *****/
    /***** Example:                               *****/
    RenderOptions options_;
};
} // namespace Capsaicin
