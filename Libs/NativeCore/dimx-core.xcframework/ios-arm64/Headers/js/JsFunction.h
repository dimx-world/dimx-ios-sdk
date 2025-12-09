#pragma once

#include "JsEnv.h"
#include <type_traits>
#include <utility>
#include <vector>

namespace qjs {
template <typename T, typename Enable>
struct js_traits;
}

// Wrapper around a JavaScript function value that keeps it alive and allows typed invocation.
template <typename Signature>
class JsFunction;

template <typename Return, typename... Args>
class JsFunction<Return(Args...)>
{
public:
    JsFunction() = default;

    JsFunction(const qjs::Value& function)
    {
        reset(JsEnv::fromContext(function.ctx), function);
    }

    JsFunction(const JsFunction& other)
    {
        copyFrom(other);
    }

    JsFunction& operator=(const JsFunction& other)
    {
        if (this != &other) {
            release();
            copyFrom(other);
        }
        return *this;
    }

    JsFunction(JsFunction&& other) noexcept
    {
        moveFrom(std::move(other));
    }

    JsFunction& operator=(JsFunction&& other) noexcept
    {
        if (this != &other) {
            release();
            moveFrom(std::move(other));
        }
        return *this;
    }

    ~JsFunction()
    {
        release();
    }

    void reset()
    {
        release();
        mEnv = nullptr;
    }

    void reset(JsEnv* env, const qjs::Value& function)
    {
        release();
        mEnv = env;
        if (mEnv && JS_IsFunction(mEnv->jsContext(), function.v)) {
            mFunction = JS_DupValue(mEnv->jsContext(), function.v);
        } else {
            mFunction = JS_UNDEFINED;
        }
    }

    JsFunction& operator=(const qjs::Value& function)
    {
        reset(mEnv, function);
        return *this;
    }

    bool isValid() const
    {
        return mEnv && !JS_IsUndefined(mFunction) && JS_IsFunction(mEnv->jsContext(), mFunction);
    }

    explicit operator bool() const { return isValid(); }

    JsEnv* env() const { return mEnv; }

    Return operator()(Args... args) const
    {
        if (!isValid()) {
            return;
        }

        if constexpr (std::is_void_v<Return>) {
            mEnv->safeCall([&]() {
                callImpl(std::forward<Args>(args)...);
            });
        } else {
            return mEnv->safeCallRet([&]() -> Return {
                return callImpl(std::forward<Args>(args)...);
            });
        }
    }

private:
    void release()
    {
        if (mEnv && !JS_IsUndefined(mFunction)) {
            JS_FreeValue(mEnv->jsContext(), mFunction);
        }
        mFunction = JS_UNDEFINED;
    }

    JSValue duplicateHandle(JSContext* ctx) const
    {
        if (!isValid()) {
            return JS_UNDEFINED;
        }
        ASSERT(ctx == mEnv->jsContext(), "JsFunction duplicateHandle called with mismatched context");
        return JS_DupValue(ctx, mFunction);
    }

    void copyFrom(const JsFunction& other)
    {
        mEnv = other.mEnv;
        if (mEnv && !JS_IsUndefined(other.mFunction)) {
            mFunction = JS_DupValue(mEnv->jsContext(), other.mFunction);
        } else {
            mFunction = JS_UNDEFINED;
        }
    }

    void moveFrom(JsFunction&& other)
    {
        mEnv = other.mEnv;
        mFunction = other.mFunction;
        other.mEnv = nullptr;
        other.mFunction = JS_UNDEFINED;
    }

    template <typename... CallArgs>
    Return callImpl(CallArgs&&... callArgs) const
    {
        JSContext* ctx = mEnv->jsContext();

        std::vector<qjs::Value> holders;
        holders.reserve(sizeof...(CallArgs));
        (holders.emplace_back(mEnv->coreToJsValue(std::forward<CallArgs>(callArgs))), ...);

        std::vector<JSValueConst> argv(holders.size());
        for (size_t i = 0; i < holders.size(); ++i) {
            argv[i] = holders[i].v;
        }

        qjs::Value result{ctx, JS_Call(ctx, mFunction, JS_UNDEFINED, static_cast<int>(argv.size()), argv.data())};

        if constexpr (std::is_void_v<Return>) {
            return;
        } else {
            return convertResult(result);
        }
    }

    template <typename R = Return>
    std::enable_if_t<!std::is_void_v<R>, R> convertResult(qjs::Value& result) const
    {
        if constexpr (std::is_same_v<R, qjs::Value>) {
            return result;
        } else {
            R out{};
            if constexpr (std::is_same_v<R, Vec2> || std::is_same_v<R, Vec3> || std::is_same_v<R, Vec4> ||
                          std::is_same_v<R, Quat> || std::is_same_v<R, DateTime>) {
                if (mEnv->coreFromJsValue(result, out)) {
                    return out;
                }
            }
            return result.as<R>();
        }
    }

private:
    JsEnv* mEnv{nullptr};
    JSValue mFunction{JS_UNDEFINED};

    template <typename, typename>
    friend struct qjs::js_traits;
};

namespace qjs {
template <typename Return, typename... Args>
struct js_traits<JsFunction<Return(Args...)>>
{
    static JsFunction<Return(Args...)> unwrap(JSContext* ctx, JSValueConst v)
    {
        JsEnv* env = JsEnv::fromContext(ctx);
        JsFunction<Return(Args...)> fn;
        if (!env || !JS_IsFunction(ctx, v)) {
            return fn;
        }

        qjs::Value jsValue{ctx, JS_DupValue(ctx, v)};
        fn.reset(env, jsValue);
        return fn;
    }

    static JSValue wrap(JSContext* ctx, const JsFunction<Return(Args...)>& fn)
    {
        if (!fn.isValid()) {
            return JS_UNDEFINED;
        }

        JsEnv* env = JsEnv::fromContext(ctx);
        if (env != fn.env()) {
            return JS_UNDEFINED;
        }

        return fn.duplicateHandle(ctx);
    }
};
}
