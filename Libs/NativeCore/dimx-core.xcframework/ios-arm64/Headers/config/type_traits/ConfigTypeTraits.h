#pragma once
#include <iosfwd>

class Config;
class OBufferStream;
class IBufferStream;

namespace Json { class Value; }

template <typename T>
struct ConfigTypeTraits
{
    static bool isType(const Config& config);

    static T getConfigValue(const Config& config);

    static void setConfigValue(Config& config, const T& value);

    static void readFromJson(Config& config, Json::Value& jnode);

    static std::ostream& writeToTextStream(const Config& config, std::ostream& os);

    static void writeToBufferStream(const Config& config, OBufferStream& stream);

    static void readFromBufferStream(Config& config, IBufferStream& stream);
};
