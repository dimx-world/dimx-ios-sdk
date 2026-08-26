#ifndef MATERIAL_INTERFACE_H_INCLUDED
#define MATERIAL_INTERFACE_H_INCLUDED

#include <simd/simd.h>

#ifdef __cplusplus
extern "C" {
#endif

bool Material_transparent(const void* ptr);

// Render state, resolved through the material's parent chain as the GL
// renderer reads it: the blend that is in effect (0 opaque, 1 cutout,
// 2 alpha, 3 additive, 4 multiply - the values the shader switches on),
// the cutout threshold, whether the draw writes depth, the cull mode
// (0 back, 1 front, 2 off) and the sort priority among blended meshes.
long Material_effectiveBlend(const void* ptr);
float Material_alphaCutoff(const void* ptr);
bool Material_depthWrite(const void* ptr);
long Material_cullMode(const void* ptr);
long Material_sortPriority(const void* ptr);

const void* Material_getTexture(const void* ptr, const char* name);
long Material_nativeId(const void* ptr);

bool Material_hasParam(const void* ptr, const char* key);
bool Material_getParamBool(const void* ptr, const char* key);
float Material_getParamFloat(const void* ptr, const char* key);
void Material_getParamVec4(const void* ptr, const char* key, void* outBuf);
void Material_getParamMat3(const void* ptr, const char* key, simd_float3x3* out);

long Material_stencilMode(const void* ptr);
long Material_stencilFunction(const void* ptr);
long Material_stencilRefValue(const void* ptr);

#ifdef __cplusplus
}
#endif

#endif // MATERIAL_INTERFACE_H_INCLUDED
