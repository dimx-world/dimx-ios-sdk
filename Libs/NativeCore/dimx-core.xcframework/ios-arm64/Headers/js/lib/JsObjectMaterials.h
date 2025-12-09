#pragma once
#include <Common.h>
#include "JsMaterial.h"
#include <quickjspp.hpp>

class JsEnv;
class Object;
class JsMaterialAll;
class JsObjectMaterials
{
public:
    JsObjectMaterials(JsEnv* env, Object* obj);
    ~JsObjectMaterials();

    std::map<std::string, JsMaterial>& getJsMaterials();

    std::vector<JsMaterial*> list();
    qjs::Value get(qjs::Value key);
    qjs::Value all();

    static void registerClass(qjs::Context::Module& module) {
        module.class_<JsObjectMaterials>("JsObjectMaterials")
        .fun<&JsObjectMaterials::list>("list")
        .fun<&JsObjectMaterials::get>("get")
        .property<&JsObjectMaterials::all, nullptr>("all");
    }

private:
    JsEnv* mEnv{nullptr};
    Object* mObject{nullptr};

    std::map<std::string, JsMaterial> mJsMaterials;
    std::unique_ptr<JsMaterialAll> mJsMaterialAll;
};
