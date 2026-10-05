#include "LightingInterface.h"
#include <Lighting.h>

bool Lighting_enabled(const void* ptr)
{
    return reinterpret_cast<const Lighting*>(ptr)->enabled();
}

void Lighting_direction(const void* ptr, void* outBuf)
{
    const Vec3& vec = reinterpret_cast<const Lighting*>(ptr)->direction();
    memcpy(outBuf, &vec, sizeof(Vec3));
}

void Lighting_ambientColor(const void* ptr, void* outBuf)
{
    const Vec3& vec = reinterpret_cast<const Lighting*>(ptr)->ambientColor();
    memcpy(outBuf, &vec, sizeof(Vec3));
}

void Lighting_diffuseColor(const void* ptr, void* outBuf)
{
    const Vec3& vec = reinterpret_cast<const Lighting*>(ptr)->diffuseColor();
    memcpy(outBuf, &vec, sizeof(Vec3));
}

void Lighting_specularColor(const void* ptr, void* outBuf)
{
    const Vec3& vec = reinterpret_cast<const Lighting*>(ptr)->specularColor();
    memcpy(outBuf, &vec, sizeof(Vec3));
}
