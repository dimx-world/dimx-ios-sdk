#pragma once
#include <anim/Animation.h>
#include <anim/NodeAnimator.h>
#include <anim/SkelAnimator.h>
#include <anim/MorphAnimator.h>
#include <js/JsFunction.h>
#include <LifeWatcher.h>

class ModelNode;
class Animator
{
    struct AnimatorEvent {
        JsFunction<void()> callback;
        double time = 0.0;
    };

    struct PlayOptions {
        bool loop = false;
        double speed = 1.0;
        JsFunction<void()> onEnd;
    };

public:
    Animator(ModelNode* modelNode, const Config& config);
    ~Animator();
    void serialize(Config& out);
    std::shared_ptr<edit::Property> createEditableProperty();
    void update(const FrameContext& frameContext);

    const std::string& startupAnimation() const { return mStartupAnimation; }
    void setStartupAnimation(const std::string& name);

    const std::map<std::string, AnimationPtr>& modelAnimations() const;

    bool tryPlayAnimation(const std::string& name, const Config& options = {});

    void resetAnimation();

    bool looped() const { return mLooped; }
    void setLooped(bool value) { mLooped = value;}

    double speed() const { return mSpeed; }
    void setSpeed(double speed) { mSpeed = speed; }

    void onModelAddAnimation(Animation* anim);

    void subscribe(const std::string& animation, double time, JsFunction<void()> callback);
    void subscribe(const std::string& event, JsFunction<void()> callback);

private:
    void setupAnimatorLinks(const Animation& animation, bool active);

private:
    ModelNode* mModelNode = nullptr;
    std::string mStartupAnimation;
    std::string mPendingAnimation;

    AnimationPtr mActiveAnimation;

    double mAnimationTime = 0.0;

    std::vector<std::string> mAnimationsList;

    std::unique_ptr<NodeAnimator> mNodeAnimator;
    std::unique_ptr<SkelAnimator> mSkelAnimator;
    std::unique_ptr<MorphAnimator> mMorphAnimator;

    NodeAnimator* mActiveNodeAnimator = nullptr;
    SkelAnimator* mActiveSkelAnimator = nullptr;
    MorphAnimator* mActiveMorphAnimator = nullptr;

    bool mLooped = false;
    double mSpeed{1.0};

    std::map<std::string, std::vector<AnimatorEvent>> mSubscriptions;
    const std::vector<AnimatorEvent>* mActiveSubscriptions{nullptr};

    PlayOptions mActivePlayOptions;

    bool mInsideUpdate{false};

    LifeWatcher mLifeWatcher; // last
};
