#ifndef VARIANT_INTERFACE_H_INCLUDED
#define VARIANT_INTERFACE_H_INCLUDED

#ifdef __cplusplus
extern "C" {
#endif

int Variant_getStr(const void* config, const char* path, char* outBuf, unsigned int bufSize);
int Variant_getInt32(const void* config, const char* path);
float Variant_getFloat(const void* config, const char* path);
double Variant_getDouble(const void* config, const char* path);
bool Variant_getBool(const void* config, const char* path);

void Variant_getVec3(const void* config, const char* path, void* outBuf);
void Variant_getVec4(const void* config, const char* path, void* outBuf);

#ifdef __cplusplus
}
#endif

#endif // VARIANT_INTERFACE_H_INCLUDED
