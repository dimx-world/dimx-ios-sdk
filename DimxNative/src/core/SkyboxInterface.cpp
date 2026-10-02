#include "SkyboxInterface.h"
#include <Skybox.h>
#include <Texture.h>

const void* Skybox_irradianceMap(const void* ptr)
{
    const Skybox* skybox = reinterpret_cast<const Skybox*>(ptr);
    return skybox->irradianceMap().get();
}

const void* Skybox_radianceMap(const void* ptr)
{
    const Skybox* skybox = reinterpret_cast<const Skybox*>(ptr);
    return skybox->radianceMap().get();
}
