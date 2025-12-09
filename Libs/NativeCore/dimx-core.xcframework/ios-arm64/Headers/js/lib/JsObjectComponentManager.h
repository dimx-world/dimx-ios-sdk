#pragma once
#include <Common.h>
#include <EventSubscriber.h>

#include <quickjspp.hpp>

class JsEnv;
class Object;
class ObjectComponentManager;
class ObjectComponent;

class JsDummy;
class JsImage;
class JsText;
class JsModel;
class JsAudioPlayer;
class JsVideoPlayer;
class JsTrigger;
class JsUIScreen;
class JsObjectPhysics;
class JsMarker;

class JsObjectComponentManager
{
public:
    JsObjectComponentManager(JsEnv* env, ObjectComponentManager* manager);
    ~JsObjectComponentManager();

    qjs::Value add(const std::string& name, qjs::Value config);
    qjs::Value get(const std::string& name);
    void remove(const std::string& name);

    const qjs::Value& jsValue() const { return mJsObject; }

    qjs::Value ui();
    qjs::Value physics();

    static void registerClass(qjs::Context::Module& module) {
        module.class_<JsObjectComponentManager>("ObjectComponentManager")
        .fun<&JsObjectComponentManager::add>("add")
        .fun<&JsObjectComponentManager::get>("get")
        .fun<&JsObjectComponentManager::remove>("remove");
    }

private:
    void registerStandardComponents();
    void registerComponent(ObjectComponent* comp);
    void registerComponent(const std::string& name, qjs::Value jsValue);
    void unregisterComponent(ObjectComponent* comp);

    void registerProperty(const std::string& name, const qjs::Value& value);
    void clearProperty(const std::string& name);

private:
    JsEnv* mEnv{nullptr};
    ObjectComponentManager* mManager{nullptr};
    std::map<std::string, qjs::Value> mComponents;
    qjs::Value mJsObject;

    std::unique_ptr<JsDummy> mDummy;
    std::unique_ptr<JsImage> mImage;
    std::unique_ptr<JsText> mText;
    std::unique_ptr<JsAudioPlayer> mAudioPlayer;
    std::unique_ptr<JsVideoPlayer> mVideoPlayer;
    std::unique_ptr<JsTrigger> mTrigger;
    std::unique_ptr<JsUIScreen> mUIScreen;
    std::unique_ptr<JsObjectPhysics> mPhysics;
    std::unique_ptr<JsMarker> mMarker;

    EventSubscriber mSubscriber; // last
};
