#pragma once

#include <ecs/Component.h>
#include <EventPublisher.h>

DECL_ENUM(ObjectComponentManagerEvent,  AddComponent,   RemoveComponent);
DECL_ESTR(ObjectComponentManagerEvent, "AddComponent", "RemoveComponent");

class ObjectComponent;
class ObjectComponentManager: public Component
{
    DECLARE_COMPONENT(ObjectComponentManager)
    DECLARE_EVENTS(ObjectComponentManagerEvent)

public:
    ObjectComponentManager(Object* entity, const Config& config);
    ~ObjectComponentManager();
    void update(const FrameContext& frameContext);

    ObjectComponent* addComponent(const std::string& name, const Config& config);
    ObjectComponent* getComponent(const std::string& name);
    void removeComponent(const std::string& name);

    void forEachComponent(const std::function<void(ObjectComponent*)>& func) {
        for (const auto& comp: mComponents) {
            func(comp.get());
        }
    }

private:
    void addComponentInternal(std::unique_ptr<ObjectComponent> comp);
    void removeComponentInternal(const std::string& name);

private:
    std::vector<std::unique_ptr<ObjectComponent>> mComponents;

    bool mInsideUpdate{false};

    std::vector<std::unique_ptr<ObjectComponent>> mPendingAddComponents;
    std::vector<std::string> mPendingRemoveComponents;
};
