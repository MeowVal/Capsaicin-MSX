#include "atmosphere/atmosphere.h"
#include "auto_exposure/auto_exposure.h"
#include "bloom/bloom.h"
#include "combine/combine.h"
#include "fsr/fsr.h"
#include "lens/lens.h"
#include "multi_scatter_test/multi_scatter_test.h"
#include "renderer.h"
#include "skybox/skybox.h"
#include "ssgi/ssgi.h"
#include "tone_mapping/tone_mapping.h"
#include "visibility_buffer/visibility_buffer.h"

/***** Include and headers for used render techniques here *****/

namespace Capsaicin
{
class MultiScatterRenderer
    : public Renderer
    , public RendererFactory::Registrar<MultiScatterRenderer>
{
public:
    /***** Must define unique name to represent new type *****/
    static constexpr std::string_view Name = "Multi-Scatter Test Renderer";

    /***** Must have empty constructor *****/
    MultiScatterRenderer() noexcept {}

    std::vector<std::unique_ptr<RenderTechnique>> setupRenderTechniques(
        RenderOptionList const &renderOptions) noexcept override
    {
        std::vector<std::unique_ptr<RenderTechnique>> render_techniques;
        /***** Emplace any desired render techniques to the returned list here *****/
        render_techniques.emplace_back(std::make_unique<VisibilityBuffer>());
        render_techniques.emplace_back(std::make_unique<SSGI>());
        render_techniques.emplace_back(std::make_unique<MultiScatterTests>());
        render_techniques.emplace_back(std::make_unique<Atmosphere>());
        render_techniques.emplace_back(std::make_unique<Skybox>());
        render_techniques.emplace_back(std::make_unique<Combine>());
        render_techniques.emplace_back(std::make_unique<FSR>());
        render_techniques.emplace_back(std::make_unique<AutoExposure>());
        render_techniques.emplace_back(std::make_unique<Bloom>());
        render_techniques.emplace_back(std::make_unique<ToneMapping>());
        render_techniques.emplace_back(std::make_unique<Lens>());
        return render_techniques;
    }

private:
};
} // namespace Capsaicin
