#pragma once
#include <Common.h>
#include "JsObjectComponent.h"
#include <config/Config.h>
#include <js/JsFunction.h>
#include <quickjspp.hpp>

class JsInteractiveObjectComponent: public JsObjectComponent
{
    MAKE_JS_VALUE(JsInteractiveObjectComponent)
    JS_OBJECT_COMPONENT_BASE_METHODS()

public:
    static constexpr const char* Type = "Input";

public:
    JsInteractiveObjectComponent(ObjectComponentManager* manager, const Config& config);

    bool update(const FrameContext& frameContext) override;

    const JsFunction<void()>& getOnPointerDown() const { return mOnPointerDown; }
    void setOnPointerDown(const JsFunction<void()>& func) { mOnPointerDown = func; }

    const JsFunction<void()>& getOnPointerUp() const { return mOnPointerUp; }
    void setOnPointerUp(const JsFunction<void()>& func) { mOnPointerUp = func; }

    const JsFunction<void()>& getOnClick() const { return mOnClick; }
    void setOnClick(const JsFunction<void()>& func) { mOnClick = func; }

    const JsFunction<void()>& getOnLongPress() const { return mOnLongPress; }
    void setOnLongPress(const JsFunction<void()>& func) { mOnLongPress = func; }

    const JsFunction<void()>& getOnSelect() const { return mOnSelect; }
    void setOnSelect(const JsFunction<void()>& func) { mOnSelect = func; }

    const JsFunction<void()>& getOnDeselect() const { return mOnDeselect; }
    void setOnDeselect(const JsFunction<void()>& func) { mOnDeselect = func; }

    // Drag events
    bool getDragEnabled() const;
    void setDragEnabled(bool enabled);

    const JsFunction<void()>& getOnDragBegin() const { return mOnDragBegin; }
    void setOnDragBegin(const JsFunction<void()>& func) { mOnDragBegin = func; }

    const JsFunction<void()>& getOnDrag() const { return mOnDrag; }
    void setOnDrag(const JsFunction<void()>& func) { mOnDrag = func; }

    const JsFunction<void()>& getOnDragEnd() const { return mOnDragEnd; }
    void setOnDragEnd(const JsFunction<void()>& func) { mOnDragEnd = func; }

    // Rotate events
    bool getRotateEnabled() const;
    void setRotateEnabled(bool enabled);
    const JsFunction<void()>& getOnRotateBegin() const { return mOnRotateBegin; }
    void setOnRotateBegin(const JsFunction<void()>& func) { mOnRotateBegin = func; }

    const JsFunction<void()>& getOnRotate() const { return mOnRotate; }
    void setOnRotate(const JsFunction<void()>& func) { mOnRotate = func; }

    const JsFunction<void()>& getOnRotateEnd() const { return mOnRotateEnd; }
    void setOnRotateEnd(const JsFunction<void()>& func) { mOnRotateEnd = func; }

    // Swipe events
    bool getSwipeEnabled() const;
    void setSwipeEnabled(bool enabled);
    const JsFunction<void(Vec3, double)>& getOnSwipe() const { return mOnSwipe; }
    void setOnSwipe(const JsFunction<void(Vec3, double)>& func) { mOnSwipe = func; }

    static void registerClass(qjs::Context::Module& module) {
        auto cls = module.class_<JsInteractiveObjectComponent>("InteractiveObjectComponent");
        registerBaseProperties<JsInteractiveObjectComponent>(module, cls);

        cls.property<&JsInteractiveObjectComponent::getOnPointerDown, &JsInteractiveObjectComponent::setOnPointerDown>("onPointerDown");
        cls.property<&JsInteractiveObjectComponent::getOnPointerUp, &JsInteractiveObjectComponent::setOnPointerUp>("onPointerUp");
        cls.property<&JsInteractiveObjectComponent::getOnClick, &JsInteractiveObjectComponent::setOnClick>("onClick");
        cls.property<&JsInteractiveObjectComponent::getOnLongPress, &JsInteractiveObjectComponent::setOnLongPress>("onLongPress");
        cls.property<&JsInteractiveObjectComponent::getOnSelect, &JsInteractiveObjectComponent::setOnSelect>("onSelect");
        cls.property<&JsInteractiveObjectComponent::getOnDeselect, &JsInteractiveObjectComponent::setOnDeselect>("onDeselect");

        // Drag events
        cls.property<&JsInteractiveObjectComponent::getDragEnabled, &JsInteractiveObjectComponent::setDragEnabled>("drag");
        cls.property<&JsInteractiveObjectComponent::getOnDragBegin, &JsInteractiveObjectComponent::setOnDragBegin>("onDragBegin");
        cls.property<&JsInteractiveObjectComponent::getOnDrag, &JsInteractiveObjectComponent::setOnDrag>("onDrag");
        cls.property<&JsInteractiveObjectComponent::getOnDragEnd, &JsInteractiveObjectComponent::setOnDragEnd>("onDragEnd");

        // Rotate events
        cls.property<&JsInteractiveObjectComponent::getRotateEnabled, &JsInteractiveObjectComponent::setRotateEnabled>("rotate");
        cls.property<&JsInteractiveObjectComponent::getOnRotateBegin, &JsInteractiveObjectComponent::setOnRotateBegin>("onRotateBegin");
        cls.property<&JsInteractiveObjectComponent::getOnRotate, &JsInteractiveObjectComponent::setOnRotate>("onRotate");
        cls.property<&JsInteractiveObjectComponent::getOnRotateEnd, &JsInteractiveObjectComponent::setOnRotateEnd>("onRotateEnd");

        // Swipe events
        cls.property<&JsInteractiveObjectComponent::getSwipeEnabled, &JsInteractiveObjectComponent::setSwipeEnabled>("swipe");
        cls.property<&JsInteractiveObjectComponent::getOnSwipe, &JsInteractiveObjectComponent::setOnSwipe>("onSwipe");
    }

private:
    JsFunction<void()> mOnPointerDown;
    JsFunction<void()> mOnPointerUp;

    JsFunction<void()> mOnClick;
    JsFunction<void()> mOnLongPress;

    JsFunction<void()> mOnSelect;
    JsFunction<void()> mOnDeselect;

    JsFunction<void()> mOnDragBegin;
    JsFunction<void()> mOnDrag;
    JsFunction<void()> mOnDragEnd;

    JsFunction<void()> mOnRotateBegin;
    JsFunction<void()> mOnRotate;
    JsFunction<void()> mOnRotateEnd;

    JsFunction<void(Vec3, double)> mOnSwipe;
};
