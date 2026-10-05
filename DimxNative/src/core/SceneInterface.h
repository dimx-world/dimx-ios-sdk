#ifndef SCENE_INTERFACE_H_INCLUDED
#define SCENE_INTERFACE_H_INCLUDED

#include <simd/simd.h>

#ifdef __cplusplus
extern "C" {
#endif

unsigned long Scene_id(const void* ptr);
unsigned long Scene_renderId(const void* ptr);
const void* Scene_lighting(const void* ptr);
const void* Scene_skybox(const void* ptr);

// The scene's ground shadow (GroundShadow), as of its last update.
bool Scene_groundShadowActive(const void* ptr);
unsigned long long Scene_groundShadowRevision(const void* ptr);
long Scene_groundShadowTextureSize(const void* ptr);
float Scene_groundShadowBlurTexels(const void* ptr);
float Scene_groundShadowOpacity(const void* ptr);
simd_float4x4 Scene_groundShadowCasterViewProj(const void* ptr);
simd_float4x4 Scene_groundShadowQuadTransform(const void* ptr);

#ifdef __cplusplus
}
#endif

#endif // SCENE_INTERFACE_H_INCLUDED
