#pragma once
#include <Common.h>
#include <quickjspp.hpp>

class JsEnv;
class Dimension;
class JsUtils
{
public:
    JsUtils(JsEnv* env, Dimension* dim);

    void openUrl(const std::string& url);
    std::string platformName();

    bool validateResource(const std::string& type, const std::string& name);

    static void registerClass(qjs::Context::Module& module) {
        module.class_<JsUtils>("Utils")
        .property<&JsUtils::platformName>("platformName")
        .fun<&JsUtils::openUrl>("openUrl")
        .fun<&JsUtils::validateResource>("validateResource");
    }

private:
    JsEnv* mEnv{nullptr};
    Dimension* mDimension{nullptr};
};
