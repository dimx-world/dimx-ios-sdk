#pragma once
#include <Common.h>
#include <ObjectId.h>
#include "JsObject.h"
#include "JsObjectCache.h"
#include "JsTimer.h"
#include <quickjspp.hpp>

class JsDimension;
class JsEnv;
class Location;
class JsLocationUI;
class JsLocation: public std::enable_shared_from_this<JsLocation>
{
    using VoidCb = std::function<void()>;
    using ValueCb = std::function<void(qjs::Value)>;

public:
    JsLocation(JsDimension* jsDim, Location* loc);
    ~JsLocation();

    JsEnv* env() { return mEnv; }

    Location& core() { return *mLocation; }

    std::string id() const;
    const std::string& name() const;
    qjs::Value createObject(qjs::Value jsConfig);
    //void createMarker(qjs::Value jsConfig, qjs::Value jsCallback);
    qjs::Value root();
    qjs::Value transform();

    JsObject* getObject(const std::string& id);
    JsObject* getObjectById(ObjectId id);
    JsObject* getJsObject(Object* object);
    void deleteObject(std::string id);

    //qjs::Value createUIScreen(qjs::Value jsConfig);
    //void deleteUIScreen(const std::string& strId);
    qjs::Value timer();
    qjs::Value ui();

    void subscribe(std::string event, qjs::Value callback);

    void onUpdate(const FrameContext& frameContext);

    qjs::Value raycast(qjs::Value jsRay, qjs::Value jsOptions);
    
    static void registerClass(qjs::Context::Module& module) {
        module.class_<JsLocation>("JsLocation")
            .property<&JsLocation::id>("id")
            .property<&JsLocation::name>("name")
            .property<&JsLocation::root>("root")
            .property<&JsLocation::transform>("transform")
            .property<&JsLocation::timer>("timer")
            .property<&JsLocation::ui>("ui")
            .fun<&JsLocation::createObject>("createObject")
            .fun<&JsLocation::getObject>("getObject")
            .fun<&JsLocation::deleteObject>("deleteObject")
            .fun<&JsLocation::subscribe>("on")
            .fun<&JsLocation::raycast>("raycast");

            //.fun<&JsLocation::createMarker>("createMarker") ///////////////////////////////
            //.fun<&JsLocation::createUIScreen>("createUIScreen") ///////////////////////////////
            //.fun<&JsLocation::deleteUIScreen>("deleteUIScreen") ///////////////////////////////
    }

private:
    void onStateChange(LocationState state);
    void onEnter();
    void onExit();
    void onTrackingStatus(bool tracked);
    void onObjectAdded(Object* object);
    void onObjectRemoved(Object* object);

private:
    JsDimension* mJsDimension{nullptr};
    JsEnv* mEnv{nullptr};
    Location* mLocation{nullptr};
    JsObjectCache mObjectCache;

    //std::vector<std::unique_ptr<JsUIScreen>> mUIScreens;
    std::unique_ptr<JsTimer> mTimer;
    std::shared_ptr<JsLocationUI> mUI;

    std::vector<VoidCb> mEnterCb;
    std::vector<VoidCb> mExitCb;
    std::vector<VoidCb> mShowCb;
};
