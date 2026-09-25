#include "VariantInterface.h"
#include <variant/Variant.h>

// Every `path` here is a dotted path ("camera.minz"), walked with Variant::at: Swift
// reads nested engine settings by their full name.

int Variant_getStr(const void* config, const char* path, char* outBuf, unsigned int bufSize)
{
    const Variant* node = reinterpret_cast<const Variant*>(config)->findPath(path);
    if (!node) {
        return -1;
    }
    std::string strVal = node->get();

    size_t bytesToCopy = strVal.size() + 1;

    if (bytesToCopy > bufSize) {
        return -1;
    }

    std::memcpy(outBuf, strVal.c_str(), bytesToCopy);

    return static_cast<int>(bytesToCopy);
}

int Variant_getInt32(const void* config, const char* path)
{
    return reinterpret_cast<const Variant*>(config)->at(path).get<int>();
}

float Variant_getFloat(const void* config, const char* path)
{
    return reinterpret_cast<const Variant*>(config)->at(path).get<float>();
}

double Variant_getDouble(const void* config, const char* path)
{
    return reinterpret_cast<const Variant*>(config)->at(path).get<double>();
}

bool Variant_getBool(const void* config, const char* path)
{
    return reinterpret_cast<const Variant*>(config)->at(path).get<bool>();
}

void Variant_getVec3(const void* config, const char* path, void* outBuf)
{
    Vec3 tmp = reinterpret_cast<const Variant*>(config)->at(path).get<Vec3>();
    memcpy(outBuf, &tmp, sizeof(Vec3));
}

void Variant_getVec4(const void* config, const char* path, void* outBuf)
{
    Vec4 tmp = reinterpret_cast<const Variant*>(config)->at(path).get<Vec4>();
    memcpy(outBuf, &tmp, sizeof(Vec4));
}
