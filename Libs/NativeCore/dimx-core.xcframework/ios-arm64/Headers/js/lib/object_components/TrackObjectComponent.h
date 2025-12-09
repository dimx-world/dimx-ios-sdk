#pragma once
#include <Common.h>
#include "JsObjectComponent.h"
#include "ObjectComponentTrack.h"
#include <config/Config.h>
#include <FrameContext.h>
#include <algorithm>
#include <cmath>

DECL_ENUM(PathTrackMode,  Relative,   Absolute);
DECL_ESTR(PathTrackMode, "Relative", "Absolute");

template <typename T>
class TrackObjectComponent: public JsObjectComponent
{
public:
    TrackObjectComponent(ObjectComponentManager* manager, const Config& config)
    : JsObjectComponent(manager, config)
    , mTrack(config.get<const Config&>("track", {}))
    {
        mMode = config.get("mode", mMode);
        mLoop = config.get("loop", mLoop);
        mEaseOut = config.get("easeOut", mEaseOut);
        if (config.contains("duration")) {
            mDuration = config.get<float>("duration");
            if (mDuration <= 0.f) {
                // warn or throw?
                mDuration = mTrack.euclideanLength();
            }
            mSpeed = 1.f / mDuration;
        }
        if (config.contains("speed")) {
            mSpeed = config.get<float>("speed") / mTrack.euclideanLength();
            mDuration = mTrack.euclideanLength() * mSpeed;
        }

        mCurrentPosition = 0.f;
        mCurrentValue = mTrack.evaluate(mCurrentPosition);
    }
    
    bool update(const FrameContext& frameContext) override
    {
        mCurrentPosition += mSpeed * frameContext.frameDuration();

        if (mLoop) {
            if (mCurrentPosition > 1.f) {
                mCurrentPosition = std::fmod(mCurrentPosition, 1.f);
            }
        } else if (mCurrentPosition > 1.f) {
            mCurrentPosition = 1.f;
        }

        const float samplePosition = mEaseOut ? easeOutCubic(mCurrentPosition) : mCurrentPosition;
        mCurrentValue = mTrack.evaluate(samplePosition);

        return mLoop || mCurrentPosition < 1.f;
    }

    const T& currentValue() const { return mCurrentValue; }
    float currentPosition() const { return mCurrentPosition; }

    PathTrackMode mode() const { return mMode; }

private:
    static float easeOutCubic(float t)
    {
        t = std::clamp(t, 0.f, 1.f);
        const float inv = 1.f - t;
        return 1.f - inv * inv * inv;
    }

    ObjectComponentTrack<T> mTrack;
    PathTrackMode mMode{PathTrackMode::Absolute};
    bool mLoop{false};
    bool mEaseOut{false};
    float mDuration{0.f};
    float mSpeed{0.f};

    T mCurrentValue{};
    float mCurrentPosition{0};
};
