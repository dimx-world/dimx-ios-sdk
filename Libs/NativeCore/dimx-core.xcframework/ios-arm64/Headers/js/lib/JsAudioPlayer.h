#pragma once
#include <Common.h>
#include <quickjspp.hpp>

class JsEnv;
class Object;
class AudioPlayer;
class JsAudioPlayer
{
public:
    JsAudioPlayer(JsEnv* env, AudioPlayer* player);
    
    const qjs::Value& jsValue() const { return mJsValue; }
    const std::string& asset() const;

    void play();
    void pause();

    static void registerClass(qjs::Context::Module& module) {
        module.class_<JsAudioPlayer>("JsAudioPlayer")
        .property<&JsAudioPlayer::asset>("asset")
        .fun<&JsAudioPlayer::play>("play")
        .fun<&JsAudioPlayer::pause>("pause");
    }

private:
    JsEnv* mEnv{nullptr};
    AudioPlayer* mPlayer{nullptr};
    qjs::Value mJsValue;
};
