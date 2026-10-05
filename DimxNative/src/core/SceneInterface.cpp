#include "SceneInterface.h"
#include <Lighting.h>
#include <Scene.h>
#include <Skybox.h>
#include <render/GroundShadow.h>

#include <cstring>

namespace {

const GroundShadow& groundShadow(const void* ptr)
{
    return reinterpret_cast<const Scene*>(ptr)->groundShadow();
}

// Mat4 and simd_float4x4 share their layout (SimdConvert.h).
simd_float4x4 toSimd4x4(const Mat4& mat)
{
    simd_float4x4 out;
    std::memcpy(&out, &mat, sizeof(out));
    return out;
}

} // namespace

unsigned long Scene_id(const void* ptr)
{
    return reinterpret_cast<const Scene*>(ptr)->id().toUInt64();
}

unsigned long Scene_renderId(const void* ptr)
{
    return reinterpret_cast<const Scene*>(ptr)->renderId();
}

const void* Scene_lighting(const void* ptr)
{
    return &reinterpret_cast<const Scene*>(ptr)->lighting();
}

const void* Scene_skybox(const void* ptr)
{
    const Scene* scene = reinterpret_cast<const Scene*>(ptr);
    return scene->skybox().get();
}

bool Scene_groundShadowActive(const void* ptr)
{
    return groundShadow(ptr).active();
}

unsigned long long Scene_groundShadowRevision(const void* ptr)
{
    return groundShadow(ptr).revision();
}

long Scene_groundShadowTextureSize(const void* ptr)
{
    return groundShadow(ptr).textureSize();
}

float Scene_groundShadowBlurTexels(const void* ptr)
{
    return groundShadow(ptr).blurTexels();
}

float Scene_groundShadowOpacity(const void* ptr)
{
    return groundShadow(ptr).opacity();
}

simd_float4x4 Scene_groundShadowCasterViewProj(const void* ptr)
{
    return toSimd4x4(groundShadow(ptr).casterViewProj());
}

simd_float4x4 Scene_groundShadowQuadTransform(const void* ptr)
{
    return toSimd4x4(groundShadow(ptr).quadTransform());
}
