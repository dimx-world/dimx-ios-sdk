#pragma once
#include <Common.h>
#include <quickjspp.hpp>
#include "ui/JsUiElement.h"

class JsEnv;
class Object;
class JsUIScreen
{
public:
    JsUIScreen(ObjectId id, JsEnv* env, ui::Element* uiRoot);

    const qjs::Value& jsValue() const { return mJsValue; }

    ObjectId id() { return mId; }
    std::string idStr() { return mId.toString(); }
    qjs::Value root();

    static void registerClass(qjs::Context::Module& module) {
        module.class_<JsUIScreen>("JsUIScreen")
        .property<&JsUIScreen::idStr>("id")
        .property<&JsUIScreen::root>("root");
    }

private:
    ObjectId mId;
    JsEnv* mEnv{nullptr};
    JsUiElement mRoot;

    qjs::Value mJsValue;
};
