#pragma once
#include <Common.h>
#include <quickjspp.hpp>
#include <Input.h>
#include <js/JsFunction.h>

#include <optional>

class JsEnv;
class JsDimensionController;
class JsInput
{
    using ValueCb = std::function<void(qjs::Value)>;
    using ValueRBoolCb = std::function<bool(qjs::Value)>;

public:
    JsInput(JsDimensionController* controller);

    void subscribe(std::string event, qjs::Value jsCallback);

    void onInputEvent(const InputEvent& event);
    void update(const FrameContext& frameContext);

    static void registerClass(qjs::Context::Module& module) {
        module.class_<JsInput>("Input")
        .fun<&JsInput::subscribe>("on");
    }

private:
    bool processInputEvent(const InputEvent& event);

private:
    JsDimensionController* mController{nullptr};

    bool mButton1Tracked{false};
    std::optional<InputEvent> mCursorMoveEvent;

    std::vector<JsFunction<void(qjs::Value)>> mButtonPressedCb;
    std::vector<JsFunction<void(qjs::Value)>> mButtonReleasedCb;
    std::vector<JsFunction<void(qjs::Value)>> mCursorMovedCb;
};
