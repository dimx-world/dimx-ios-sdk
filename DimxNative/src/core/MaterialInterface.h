#ifndef MATERIAL_INTERFACE_H_INCLUDED
#define MATERIAL_INTERFACE_H_INCLUDED

#include <simd/simd.h>

#ifdef __cplusplus
extern "C" {
#endif

bool Material_transparent(const void* ptr);

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
