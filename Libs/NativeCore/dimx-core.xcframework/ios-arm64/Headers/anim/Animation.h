#pragma once
#include <Common.h>
#include <anim/AnimationSource.h>

DECLARE_PTR(Animation)
class Animation
{
public:
    Animation(std::string name, double startTime, double endTime, AnimationSourcePtr source);

    const AnimationSourcePtr& source() const { return mSource; }

    void addEvent(const std::string& name, double time) { mEvents[name] = time; }
    const std::map<std::string, double>& events() const { return mEvents; }

    const std::string& name() const { return mName; }
    double startTime() const { return mStartTime; }
    double endTime() const { return mEndTime; }
    double duration() const { return mDuration; }
    double frameRate() const { return mSource->frameRate(); }
    //uint32_t numFrames() const { return mNumFrames; }
/*
    const std::vector<AnimTransformNode>& transformNodes() const { return mSource->transformNodes(); }
    const std::vector<TransformTrack>& transformTracks() const { return mSource->transformTracks(); }

    const std::vector<uint32_t>& skelNodes() const { return mSource->skelNodes(); }
    const std::unique_ptr<ozz::animation::Animation>& skelAnimation() const { return mSource->skelAnimation(); }

    const std::vector<AnimMorphNode>& morphNodes() const { return mSource->morphNodes(); }
    const std::vector<FloatTrack>& morphTracks() const { return mSource->morphTracks(); }
*/
private:
    std::string mName;
    AnimationSourcePtr mSource;
    std::map<std::string, double> mEvents;

    double mStartTime = 0.0;
    double mEndTime = 0.0;
    double mDuration = 0.0;
    //uint32_t mNumFrames = 0;
};
