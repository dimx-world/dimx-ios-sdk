#pragma once
#include <Common.h>
#include <quickjspp.hpp>
#include <LifeWatcher.h>
#include "JsObjectComponentManager.h"
#include "JsAudioPlayer.h"
#include "JsVideoPlayer.h"
#include "JsObjectTransform.h"
#include "JsObjectMaterials.h"
#include <EventSubscriber.h>

class JsEnv;
class Object;
class JsLocation;
class JsModel;
class JsTimer;
class JsObject: public LifeWatcher
{
public:
    JsObject(JsLocation* loc, Object* obj);
    ~JsObject();

    Object* core() { return mObject; }

    bool alive() const;
    std::string id() const;
    const std::string& name() const;

    JsObject* getParent();
    void setParent(qjs::Value parent);
    std::vector<JsObject*> children();

    void onUpdate(const FrameContext& frameContext);

    bool isVisible() const;
    void setVisible(bool visible);

    void setScale(double value);

    qjs::Value jsComponents();
    qjs::Value jsModel();
    qjs::Value transform();

    qjs::Value getMaterials();
    qjs::Value jsAnimator();

    qjs::Value location();
    qjs::Value timer();
    qjs::Value input();
    qjs::Value ui();
    qjs::Value physics();

    static void registerClass(qjs::Context::Module& module) {
        module.class_<JsObject>("JsObject")
        .property<&JsObject::alive>("alive")
        .property<&JsObject::id>("id")
        .property<&JsObject::name>("name")
        .property<&JsObject::getParent, &JsObject::setParent>("parent")
        .property<&JsObject::children>("children")
        .property<&JsObject::jsComponents>("components")
        .property<&JsObject::isVisible, &JsObject::setVisible>("visible")
        .property<&JsObject::transform>("transform")
        .property<&JsObject::location>("location")
        .property<&JsObject::getMaterials>("materials")
        .property<&JsObject::jsAnimator>("animator")
        .property<&JsObject::jsModel>("model")
        .property<&JsObject::timer>("timer")
        .property<&JsObject::input>("input")
        .property<&JsObject::ui>("ui")
        .property<&JsObject::physics>("physics");
        //.property<&JsObject::getMaterials>("meshes")
        //.property<&JsObject::getMaterials>("nodes")
    }

    void clearObject();

private:
    JsObjectComponentManager& getComponentManager();
    JsModel* getModel();

private:
    JsLocation* mLocation{nullptr};
    JsEnv* mEnv{nullptr};
    Object* mObject{nullptr};
    std::unique_ptr<JsModel> mModel;
    std::unique_ptr<JsObjectComponentManager> mObjectComponentManager;
    std::unique_ptr<JsObjectTransform> mTransform;
    std::unique_ptr<JsObjectMaterials> mMaterials;
    std::unique_ptr<JsTimer> mTimer;

    EventSubscriber mSubscriber; // last
};
