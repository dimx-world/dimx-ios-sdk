#pragma once
#include <object_ecs/ObjectComponent.h>
#include <config/Config.h>

#include <memory>
#include <string>
#include <map>
#include <functional>


class ObjectComponentManager;
class ObjectComponentFactory
{
    using Func = std::function<std::unique_ptr<ObjectComponent>(ObjectComponentManager*, const Config&)>;

public:
    ObjectComponentFactory();

    static const ObjectComponentFactory& instance();

    std::unique_ptr<ObjectComponent> create(ObjectComponentManager* manager, const Config& config) const;

private:
    template <typename T>
    void registerType() {
        mRegistry.emplace(T::Type, [](ObjectComponentManager* manager, const Config& config) {
            return std::make_unique<T>(manager, config);
        });
    }

private:
    std::map<std::string, Func> mRegistry;
};
