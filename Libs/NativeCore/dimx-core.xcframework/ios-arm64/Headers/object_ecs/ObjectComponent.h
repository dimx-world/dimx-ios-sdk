#pragma once
#include <Common.h>
#include <config/Config.h>

class ObjectComponentManager;
class ObjectComponent
{
public:
    ObjectComponent(ObjectComponentManager* manager, const Config& config);
    virtual ~ObjectComponent() = default;

    const std::string& name() const { return mName; }
    Object& object() const;
    ObjectComponentManager& manager() const { return *mManager; }
    
    virtual bool update(const FrameContext& frameContext) { return false; }
    virtual void postUpdate(const FrameContext& frameContext) {};
    virtual void onEnd() {}
    
private:
    std::string mName;
    ObjectComponentManager* mManager{nullptr};
};
