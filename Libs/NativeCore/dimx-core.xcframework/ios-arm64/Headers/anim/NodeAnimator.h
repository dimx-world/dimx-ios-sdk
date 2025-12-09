#pragma once

#include <ecs/Component.h>
#include <anim/AnimationSource.h>

class Animator;
class NodeAnimator
{
public:
    NodeAnimator(Animator* animator);

    void evaluate(double normalizedTime);
    const Transform& getTransform(size_t track) const;

    void setAnimation(const AnimationSourcePtr& anim);

private:
    Animator* mAnimator = nullptr;
    AnimationSourcePtr mAnimation;
    std::vector<Transform> mCurrentKeys;
};
