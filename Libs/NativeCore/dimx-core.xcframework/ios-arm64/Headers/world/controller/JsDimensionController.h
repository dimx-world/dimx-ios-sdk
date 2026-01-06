#pragma once
#include "DimensionController.h"
#include <js/JsEnv.h>
#include <quickjspp.hpp>
#include <Counter.h>
#include <Input.h>

class ResourceManager;
class JsTimer;
class JsDimension;
class JsMath;
class JsLogger;
class JsAccount;
class JsLocalStorage;
class JsUI;
class JsUtils;
class JsCluster;
class JsNetwork;
class JsApp;
class JsInput;
class JsCamera;

class JsDimensionController: public DimensionController
{

private:
    struct ClusterInfo {
        qjs::Value jsValue;
        JsCluster* cluster{nullptr};
    };

public:
    JsDimensionController(Dimension* dim, CounterPtr initCounter);
    ~JsDimensionController();

    JsEnv* jsEnv() const {return mJsEnv.get(); }
    JsDimension* jsDimension() const { return mJsDimension.get(); }

    void update(const FrameContext& frameContext) override;

    void onEnter() override;
    void onExit() override;
    void onAddLocation(Location* loc) override;
    void onRemoveLocation(Location* loc) override;
    void onIntent(const std::string& params) override;

    void onRemoteClientMesssage(const Config& msg) override;

    qjs::Value getQJSCluster(const std::string& name) const;

private:
   void onInputEvent(const InputEvent& event);
   void initClusters();
   void initCluster(const std::string& clusterFilePath);
   void initDimxNamespace();

private:
    std::unique_ptr<JsEnv> mJsEnv;
    std::unique_ptr<JsTimer> mTimer;
    std::unique_ptr<JsDimension> mJsDimension;
    std::unique_ptr<JsLogger> mLogger;
    std::unique_ptr<JsAccount> mAccount;
    std::unique_ptr<JsLocalStorage> mLocalStorage;
    std::unique_ptr<JsUtils> mUtils;
    std::unique_ptr<JsUI> mUI;
    std::unique_ptr<JsNetwork> mNetwork;
    std::unique_ptr<JsApp> mApp;
    std::unique_ptr<JsInput> mInput;
    std::unique_ptr<JsCamera> mCamera;

    std::map<std::string, ClusterInfo> mClusters;
};
