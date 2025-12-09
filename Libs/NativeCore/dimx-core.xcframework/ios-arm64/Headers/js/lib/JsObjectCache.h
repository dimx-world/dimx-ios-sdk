#pragma once
#include <Common.h>
#include "JsObject.h"
#include <quickjspp.hpp>

class JsEnv;
class JsObjectCache
{
public:
    JsObjectCache(JsEnv* env);
    void setLocation(JsLocation* loc) { mLocation = loc; }

    JsObject* get(Object* object);
    JsObject* get(ObjectId id);
    JsObject* get(const std::string& name);
    void remove(ObjectId id);

private:
    JsEnv* mEnv{nullptr};
    JsLocation* mLocation{nullptr};
    std::map<ObjectId, JsObject> mObjects;
    std::map<std::string, ObjectId> mNameToId;
};