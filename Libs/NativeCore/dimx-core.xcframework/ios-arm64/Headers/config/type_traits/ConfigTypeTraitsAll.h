#pragma once

#include "ConfigTypeTraits.h"

#include <CommonMath.h>
#include <Transform.h>

template <>
struct ConfigTypeTraits<Vec3>
{
    static bool isType(const Config& config);
    static Vec3 getConfigValue(const Config& config);
    static void setConfigValue(Config& config, const Vec3& value);
    static void readFromJson(Config& config, Json::Value& jnode);
    static std::ostream& writeToTextStream(const Config& config, std::ostream& os);
    static void writeToBufferStream(const Config& config, OBufferStream& stream);
    static void readFromBufferStream(Config& config, IBufferStream& stream);
};

template <>
struct ConfigTypeTraits<Vec2>
{
    static bool isType(const Config& config);
    static Vec2 getConfigValue(const Config& config);
    static void setConfigValue(Config& config, const Vec2& value);
    static void readFromJson(Config& config, Json::Value& jnode);
    static std::ostream& writeToTextStream(const Config& config, std::ostream& os);
    static void writeToBufferStream(const Config& config, OBufferStream& stream);
    static void readFromBufferStream(Config& config, IBufferStream& stream);
};

template <>
struct ConfigTypeTraits<Vec4>
{
    static bool isType(const Config& config);
    static Vec4 getConfigValue(const Config& config);
    static void setConfigValue(Config& config, const Vec4& value);
    static void readFromJson(Config& config, Json::Value& jnode);
    static std::ostream& writeToTextStream(const Config& config, std::ostream& os);
    static void writeToBufferStream(const Config& config, OBufferStream& stream);
    static void readFromBufferStream(Config& config, IBufferStream& stream);
};

template <>
struct ConfigTypeTraits<Quat>
{
    static bool isType(const Config& config);
    static Quat getConfigValue(const Config& config);
    static void setConfigValue(Config& config, const Quat& value);
    static void readFromJson(Config& config, Json::Value& jnode);
    static std::ostream& writeToTextStream(const Config& config, std::ostream& os);
    static void writeToBufferStream(const Config& config, OBufferStream& stream);
    static void readFromBufferStream(Config& config, IBufferStream& stream);
};

template <>
struct ConfigTypeTraits<Transform>
{
    static bool isType(const Config& config);
    static Transform getConfigValue(const Config& config);
    static void setConfigValue(Config& config, const Transform& value);
    static void readFromJson(Config& config, Json::Value& jnode);
    static std::ostream& writeToTextStream(const Config& config, std::ostream& os);
    static void writeToBufferStream(const Config& config, OBufferStream& stream);
    static void readFromBufferStream(Config& config, IBufferStream& stream);
};