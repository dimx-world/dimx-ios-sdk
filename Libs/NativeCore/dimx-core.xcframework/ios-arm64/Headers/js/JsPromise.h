#pragma once
#include <Common.h>
#include <quickjspp.hpp>
#include <string>

class JsEnv;
class JsPromise
{
    NO_COPY_MOVE(JsPromise)

public:
    JsPromise(JsEnv* env, bool captureStack = false);
    ~JsPromise();

    void resolve() const { resolve(JS_UNDEFINED); }
    
    template<typename T>
    void resolve(const T& value) const {
        if (mEnv) {
            JSValue jsValue = qjs::Value(mJsContext, value);
            JS_Call(mJsContext, mCallbacks[0], mPromise, 1, &jsValue);
            JS_FreeValue(mJsContext, jsValue);
        }
    }

    void reject(const std::string& error) const;

    qjs::Value jsValue() const;

private:
    JsEnv* mEnv{nullptr};
    JSContext* mJsContext{nullptr};
    JSValue mPromise{JS_UNDEFINED};
    JSValue mCallbacks[2]{JS_UNDEFINED, JS_UNDEFINED};
    std::string mCreationStack;

};
