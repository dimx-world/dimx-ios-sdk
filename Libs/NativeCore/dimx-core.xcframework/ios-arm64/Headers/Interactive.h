#pragma once

#ifndef DIMX_CORE_INTERACTIVE_H
#define DIMX_CORE_INTERACTIVE_H

#include <ecs/Component.h>
#include <EventPublisher.h>
#include <Input.h>

DECL_ENUM(InteractiveEvent,  PointerDown,   PointerUp,   Click,   LongPress,   Select,   Deselect,   Drag,   DragBegin,   DragEnd,   Swipe,   Rotate,   RotateBegin,   RotateEnd);
DECL_ESTR(InteractiveEvent, "PointerDown", "PointerUp", "Click", "LongPress", "Select", "Deselect", "Drag", "DragBegin", "DragEnd", "Swipe", "Rotate", "RotateBegin", "RotateEnd");

DECL_ENUM(InteractiveDragConstraint,  Floor,   View,   Vertical);
DECL_ESTR(InteractiveDragConstraint, "Floor", "View", "Vertical");

DECL_ENUM(InteractiveDragOrientation,  Relative,   Fixed);
DECL_ESTR(InteractiveDragOrientation, "Relative", "Fixed");

class DragHandler;
class RotateHandler;
class SwipeHandler;
class LongPressHandler;

class Interactive: public Component
{
    DECLARE_COMPONENT(Interactive)
    DECLARE_EVENTS(InteractiveEvent)

    friend class DragHandler;
    friend class RotateHandler;
    friend class SwipeHandler;
    friend class LongPressHandler;

public:
    Interactive(Object* ent, const Config& config);
    ~Interactive();
    void serialize(Config& out) override;
    void update(const FrameContext& frameContext);
    bool processInputEvent(const InputEvent& event);

    void setSelected(bool selected);
    bool isSelected() const { return mSelected; }

    void setDraggable(bool enabled);
    bool draggable() const { return (bool)mDragHandler; }

    void setDragConstraint(InteractiveDragConstraint constraint);
    InteractiveDragConstraint dragConstraint() const;

    void setDragOrientation(InteractiveDragOrientation orientation);
    InteractiveDragOrientation orientation() const;

    void setRotatable(bool enabled);
    bool rotatable() const { return (bool)mRotateHandler; }
    void setRotateSpeed(float speed);
    float rotateSpeed() const;

    void setSwipable(bool enabled);
    bool swipable() const { return (bool)mSwipeHandler; }

    // Get the swipe velocity (only valid during/after Swipe event)
    Vec2 swipeVelocity() const;
    float swipeVelocityScalar() const;
    Vec3 swipeDirection3D() const;
    
    // Get the rotation angle in radians (only valid during/after Rotate event)
    float rotationDelta() const;
    float rotationVelocity() const;

private:
    bool mSelected{false};

    std::unique_ptr<DragHandler> mDragHandler;
    std::unique_ptr<RotateHandler> mRotateHandler;
    std::unique_ptr<SwipeHandler> mSwipeHandler;
    std::unique_ptr<LongPressHandler> mLongPressHandler;

    bool mPressed{false};
};

#endif // DIMX_CORE_INTERACTIVE_H