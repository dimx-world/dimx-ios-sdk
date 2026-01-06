#pragma once
#include <Common.h>
#include <Input.h>
#include <world/Dimension.h>
#include "JsObject.h"
#include "JsLocation.h"
#include "JsCluster.h"
#include <quickjspp.hpp>

class JsEnv;
class Dimension;
class Location;
class JsDimensionController;

class JsDimension
{
    using VoidCb = std::function<void()>;
    using ValueCb = std::function<void(qjs::Value)>;
    using LocationCb = std::function<void(JsLocation*)>;

public:
    JsDimension(JsDimensionController* controller, Dimension* dim);
    ~JsDimension();
    std::string id() const { return mDimension->id().toString(); }
    const std::string& name() const { return mDimension->name(); }
    JsEnv* jsEnv() const { return mEnv; }

    void onUpdate(const FrameContext& frameContext);
    void onEnter();
    void onExit();
    void onAddLocation(Location* loc);
    void onRemoveLocation(Location* loc);

    void onAddDummy(JsObject* object);

    std::vector<const JsLocation*> locations() const;
    qjs::Value location(const std::string& id) const;
    qjs::Value locationById(ObjectId id) const;
    JsLocation* findLocation(ObjectId id);

    void enterLocation(qjs::Value jsOptions, qjs::Value jsCallback);
    void exitLocation(const std::string& id);

    void subscribe(std::string event, qjs::Value arg1, qjs::Value arg2);

    static void registerClass(qjs::Context::Module& module) {
        module.class_<JsDimension>("Dimension")
            .property<&JsDimension::id>("id")
            .property<&JsDimension::name>("name")
            .fun<&JsDimension::enterLocation>("enterLocation")
            .fun<&JsDimension::exitLocation>("exitLocation")
            .fun<&JsDimension::location>("getLocation")
            .fun<&JsDimension::subscribe>("on");
    }

private:
    JsDimensionController* mController{nullptr};
    JsEnv* mEnv{nullptr};
    Dimension* mDimension{nullptr};
    std::map<ObjectId, std::shared_ptr<JsLocation>> mLocations;

    std::vector<VoidCb> mEnterCb;
    std::vector<VoidCb> mExitCb;
    std::map<std::string, std::vector<ValueCb>> mDummyCb;
};
