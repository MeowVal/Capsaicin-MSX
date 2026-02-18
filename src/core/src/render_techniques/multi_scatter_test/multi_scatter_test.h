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
        //bool CookTorrance = true; /**< Example option to toggle between Cook-Torrance and Blinn-Phong BRDFs */
        int  brdf_model   = 0; // 0=CookTorrance, 1=Fast-MSX, 2=Heitz, 3= GGX
    };

    /**
     * Convert render options to internal options format.
     * @param options Current render options.
     * @return The options converted.
     */
    static RenderOptions convertOptions(RenderOptionList const &options) noexcept;

    /**
     * Gets a list of any shared components used by the current render technique.
     * @return A list of all supported components.
     */
    [[nodiscard]] ComponentList getComponents() const noexcept override;

    /**
     * Gets a list of any shared buffers used by the current render technique.
     * @return A list of all supported buffers.
     */
    [[nodiscard]] SharedBufferList getSharedBuffers() const noexcept override;

    /**
     * Gets the required list of shared textures needed for the current render technique.
     * @return A list of all required shared textures.
     */
    [[nodiscard]] SharedTextureList getSharedTextures() const noexcept override;

    /**
     * Gets a list of any debug views provided by the current render technique.
     * @return A list of all supported debug views.
     */
    [[nodiscard]] DebugViewList getDebugViews() const noexcept override;
    
    /**
     * Initialise any internal data or state.
     * @note This is automatically called by the framework after construction and should be used to create
     * any required CPU|GPU resources.
     * @param capsaicin Current framework context.
     * @return True if initialisation succeeded, False otherwise.
     */
    bool init(CapsaicinInternal const &capsaicin) noexcept override;

    /**
     * Perform render operations.
     * @param [in,out] capsaicin The current capsaicin context.
     */
    void render(CapsaicinInternal &capsaicin) noexcept override;

    /**
     * Render GUI options.
     * @param [in,out] capsaicin The current capsaicin context.
     */
    void renderGUI(CapsaicinInternal &capsaicin) const noexcept override;

    /**
     * Destroy any used internal resources and shutdown.
     */
    void terminate() noexcept override;
    

protected:
    /***** Internal member data can be added here *****/
    /***** Example:                               *****/
    RenderOptions options_;
    GfxProgram    shadingProgram_; // fullscreen BRDF shading
    GfxKernel     shadingKernel_;  // if you run it as a compute/fullscreen kernel
    GfxBuffer     frameCB_;        // constant/uniform buffer for options + frame data
    std::string_view debug_view_;
    GfxTexture       depth_buffer_;
    GfxTexture       irradiance_buffer_;
    GfxBuffer        draw_command_buffer_;
    GfxBuffer        dispatch_command_buffer_;

};
} // namespace Capsaicin
