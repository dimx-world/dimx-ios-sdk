#pragma once
#include <Common.h>
#include <quickjspp.hpp>
#include "JsAnimator.h"
#include <LifeWatcher.h>

class JsEnv;
class Object;
class Location;
class JsUIScreen;
class JsLocationUI: public std::enable_shared_from_this<JsLocationUI>
{
public:
    JsLocationUI(JsEnv* env, Location* location);
    ~JsLocationUI();

    const qjs::Value& jsValue() const { return mJsValue; }

    qjs::Value createScreen(qjs::Value jsConfig);
    qjs::Value getScreen(const std::string& strId);
    void deleteScreen(const std::string& strId);

    static void registerClass(qjs::Context::Module& module) {
        module.class_<JsLocationUI>("JsLocationUI")
        .fun<&JsLocationUI::createScreen>("createScreen")
        .fun<&JsLocationUI::getScreen>("getScreen")
        .fun<&JsLocationUI::deleteScreen>("deleteScreen");
    }

private:
    JsEnv* mEnv{nullptr};
    Location* mLocation{nullptr};
    qjs::Value mJsValue;
    std::map<ObjectId, std::unique_ptr<JsUIScreen>> mUIScreens;

};
