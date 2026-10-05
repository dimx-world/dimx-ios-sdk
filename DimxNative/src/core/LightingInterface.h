#ifndef LIGHTING_INTERFACE_H_INCLUDED
#define LIGHTING_INTERFACE_H_INCLUDED

#ifdef __cplusplus
extern "C" {
#endif

bool Lighting_enabled(const void* ptr);
void Lighting_direction(const void* ptr, void* outBuf);
void Lighting_ambientColor(const void* ptr, void* outBuf);
void Lighting_diffuseColor(const void* ptr, void* outBuf);
void Lighting_specularColor(const void* ptr, void* outBuf);

#ifdef __cplusplus
}
#endif

#endif // LIGHTING_INTERFACE_H_INCLUDED
