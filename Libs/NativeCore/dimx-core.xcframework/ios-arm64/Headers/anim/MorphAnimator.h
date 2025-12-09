#pragma once

#include <Common.h>
#include <anim/AnimationSource.h>

class Animator;
class MorphAnimator
{
    struct NodeState {
        std::vector<int32_t> targetIds;
        std::vector<int32_t> trackIds;
        std::vector<float> targetWeights;
    };

public:
    MorphAnimator(Animator* animator);
    Animator* animator() const;

    void evaluate(double normalizedTime);

    const std::vector<int32_t>& activeTargetIds(size_t nodeIndex) const;
    const std::vector<float>& activeTargetWeights(size_t nodeIndex) const;

    void setAnimation(const AnimationSourcePtr& anim);

private:
    Animator* mAnimator = nullptr;
    AnimationSourcePtr mActiveAnimation;

    std::vector<float> mFloatCache;
    std::vector<NodeState> mNodeStates;

    std::vector<int32_t> mActiveTargetIds;
    std::vector<float> mActiveTargetWeights;
};
