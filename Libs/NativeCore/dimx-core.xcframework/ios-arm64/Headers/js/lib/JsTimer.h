#pragma once
#include <Common.h>
#include <js/JsFunction.h>
#include <quickjspp.hpp>

class JsEnv;
class JsTimer
{
    struct Event {
        ObjectId id;
        double interval{ 0.0 };
        double nextTime{0.0};
        size_t counter{0};
        JsFunction<void()> call;
        std::function<void()> stdCall;
    };

public:
    JsTimer(JsEnv* env);

    qjs::Value sleep(double seconds);

    std::string after(double delay, JsFunction<void()> func);
    std::string every(double interval, JsFunction<void()> func);
    std::string schedule(qjs::Value jsOptions, JsFunction<void()> func);
    void cancel(std::string id);
    void onUpdate(const FrameContext& frameContext);

    static void registerClass(qjs::Context::Module& module) {
        module.class_<JsTimer>("Timer")
        .fun<&JsTimer::sleep>("sleep")
        .fun<&JsTimer::after>("after")
        .fun<&JsTimer::every>("every")
        .fun<&JsTimer::schedule>("schedule")
        .fun<&JsTimer::cancel>("cancel");
    }

private:
    void addEvent(Event event);

private:
    JsEnv* mEnv{nullptr};
    std::vector<Event> mEvents;
    std::vector<Event> mPendingEvents;
    bool mInsideUpdate{false};
};
