#pragma once
#include <Common.h>
#include "../JsFunction.h"
#include <config/Config.h>
#include <quickjspp.hpp>
#include <Transform.h>
#include <DateTime.h>
#include "../JsEnv.h"
#include <array>

//////////////////////////////////////////////////////////////////////////////////

struct JSValueGuard
{
    JSContext* ctx{ nullptr };
    JSValue val;

    JSValueGuard(JSContext* c, JSValue v) : ctx(c), val(v) {}

    ~JSValueGuard() {
        if (!JS_IsUndefined(val)) {
            JS_FreeValue(ctx, val);
        }
    }
};

template <typename T>
T getJSCallback(JSContext* ctx, JSValue val, const char* name)
{
    JSValueGuard prop{ctx, JS_GetPropertyStr(ctx, val, name)};
    if(!JS_IsUndefined(prop.val)) {
        return qjs::js_traits<T>::unwrap(ctx, prop.val);
    }
    return {};
}

template <typename T>
T JsAnyToFunc(const std::any& any)
{
    if (any.has_value()) {
        const qjs::Value& jsval = std::any_cast<const qjs::Value&>(any);
        if (JS_IsNull(jsval.v) || JS_IsUndefined(jsval.v) || JS_IsUninitialized(jsval.v)) {
            return {};
        }
        return qjs::js_traits<T>::unwrap(jsval.ctx, jsval.v);
    }

    return {};
}

template <typename T>
T JsValToFunc(qjs::Value jsCallback)
{
    if (JS_IsFunction(jsCallback.ctx, jsCallback.v)) {
        return jsCallback.as<T>();
    }
    return {};
}

template <typename T>
T JsConfigToFunc(const Config& config)
{
    if (!config.isAny()) {
        return {};
    }

    return JsValToFunc<T>(config.getAny<const qjs::Value&>());
}

//////////////////////////////////////////////////////////////////////////////////

template <typename Signature>
JsFunction<Signature> JsFuncFromConfig(const Config& config)
{
    if (!config.isAny<qjs::Value>()) {
        return {};
    }
    return JsFunction<Signature>(config.getAny<const qjs::Value&>());
}

template <typename Signature>
JsFunction<Signature> JsFuncFromConfig(const Config& config, const std::string& key)
{
    if (const Config* cfg = config.get<const Config*>(key)) {
        return JsFuncFromConfig<Signature>(*cfg);
    }
    return {};
}

template <size_t N>
bool readArrayComponents(JSContext* ctx, JSValueConst value, std::array<double, N>& out)
{
    if (!JS_IsArray(ctx, value)) {
        return false;
    }

    JSValue lengthValue = JS_GetPropertyStr(ctx, value, "length");
    if (JS_IsException(lengthValue)) {
        return false;
    }
    JSValueGuard lengthGuard{ctx, lengthValue};

    int64_t length = 0;
    if (JS_ToInt64(ctx, &length, lengthValue) != 0 || length < static_cast<int64_t>(N)) {
        return false;
    }

    for (size_t i = 0; i < N; ++i) {
        JSValue element = JS_GetPropertyUint32(ctx, value, static_cast<uint32_t>(i));
        if (JS_IsException(element)) {
            return false;
        }
        JSValueGuard elementGuard{ctx, element};

        double component = 0.0;
        if (JS_ToFloat64(ctx, &component, element) != 0) {
            return false;
        }

        out[i] = component;
    }

    return true;
}

namespace qjs {

template <>
struct js_traits<Vec2>
{
    static Vec2 unwrap(JSContext* ctx, JSValueConst value)
    {
        Vec2 result{};
        if (JsEnv* env = JsEnv::fromContext(ctx)) {
            qjs::Value jsValue(ctx, JS_DupValue(ctx, value));
            if (env->coreFromJsValue(jsValue, result)) {
                return result;
            }
        }

        std::array<double, 2> components{};
        if (readArrayComponents(ctx, value, components)) {
            result.x = static_cast<float>(components[0]);
            result.y = static_cast<float>(components[1]);
            return result;
        }
        return result;
    }

    static JSValue wrap(JSContext* ctx, const Vec2& value)
    {
        if (JsEnv* env = JsEnv::fromContext(ctx)) {
            qjs::Value jsValue = env->coreToJsValue(value);
            return jsValue.release();
        }
        return JS_UNDEFINED;
    }
};

template <>
struct js_traits<Vec3>
{
    static Vec3 unwrap(JSContext* ctx, JSValueConst value)
    {
        Vec3 result{};
        if (JsEnv* env = JsEnv::fromContext(ctx)) {
            qjs::Value jsValue(ctx, JS_DupValue(ctx, value));
            if (env->coreFromJsValue(jsValue, result)) {
                return result;
            }
        }

        std::array<double, 3> components{};
        if (readArrayComponents(ctx, value, components)) {
            result.x = static_cast<float>(components[0]);
            result.y = static_cast<float>(components[1]);
            result.z = static_cast<float>(components[2]);
            return result;
        }
        return result;
    }

    static JSValue wrap(JSContext* ctx, const Vec3& value)
    {
        if (JsEnv* env = JsEnv::fromContext(ctx)) {
            qjs::Value jsValue = env->coreToJsValue(value);
            return jsValue.release();
        }
        return JS_UNDEFINED;
    }
};

template <>
struct js_traits<Vec4>
{
    static Vec4 unwrap(JSContext* ctx, JSValueConst value)
    {
        Vec4 result{};
        if (JsEnv* env = JsEnv::fromContext(ctx)) {
            qjs::Value jsValue(ctx, JS_DupValue(ctx, value));
            if (env->coreFromJsValue(jsValue, result)) {
                return result;
            }
        }

        std::array<double, 4> components{};
        if (readArrayComponents(ctx, value, components)) {
            result.x = static_cast<float>(components[0]);
            result.y = static_cast<float>(components[1]);
            result.z = static_cast<float>(components[2]);
            result.w = static_cast<float>(components[3]);
            return result;
        }
        return result;
    }

    static JSValue wrap(JSContext* ctx, const Vec4& value)
    {
        if (JsEnv* env = JsEnv::fromContext(ctx)) {
            qjs::Value jsValue = env->coreToJsValue(value);
            return jsValue.release();
        }
        return JS_UNDEFINED;
    }
};

template <>
struct js_traits<Quat>
{
    static Quat unwrap(JSContext* ctx, JSValueConst value)
    {
        Quat result{};
        if (JsEnv* env = JsEnv::fromContext(ctx)) {
            qjs::Value jsValue(ctx, JS_DupValue(ctx, value));
            if (env->coreFromJsValue(jsValue, result)) {
                return result;
            }
        }

        std::array<double, 4> components{};
        if (readArrayComponents(ctx, value, components)) {
            result.x = static_cast<float>(components[0]);
            result.y = static_cast<float>(components[1]);
            result.z = static_cast<float>(components[2]);
            result.w = static_cast<float>(components[3]);
            return result;
        }
        return result;
    }

    static JSValue wrap(JSContext* ctx, const Quat& value)
    {
        if (JsEnv* env = JsEnv::fromContext(ctx)) {
            qjs::Value jsValue = env->coreToJsValue(value);
            return jsValue.release();
        }
        return JS_UNDEFINED;
    }
};

template <>
struct js_traits<Transform>
{
    static Transform unwrap(JSContext* ctx, JSValueConst value)
    {
        Transform result;
        if (JsEnv* env = JsEnv::fromContext(ctx)) {
            qjs::Value jsValue(ctx, JS_DupValue(ctx, value));
            if (env->coreFromJsValue(jsValue, result)) {
                return result;
            }
        }
        return result;
    }

    static JSValue wrap(JSContext* ctx, const Transform& value)
    {
        if (JsEnv* env = JsEnv::fromContext(ctx)) {
            qjs::Value jsValue = env->coreToJsValue(value);
            return jsValue.release();
        }
        return JS_UNDEFINED;
    }
};

template <>
struct js_traits<Ray>
{
    static Ray unwrap(JSContext* ctx, JSValueConst value)
    {
        Ray result{};
        if (JsEnv* env = JsEnv::fromContext(ctx)) {
            qjs::Value jsValue(ctx, JS_DupValue(ctx, value));
            if (env->coreFromJsValue(jsValue, result)) {
                return result;
            }
        }
        return result;
    }

    static JSValue wrap(JSContext* ctx, const Ray& value)
    {
        if (JsEnv* env = JsEnv::fromContext(ctx)) {
            qjs::Value jsValue = env->coreToJsValue(value);
            return jsValue.release();
        }
        return JS_UNDEFINED;
    }
};

template <>
struct js_traits<DateTime>
{
    static DateTime unwrap(JSContext* ctx, JSValueConst value)
    {
        DateTime result;
        if (JsEnv* env = JsEnv::fromContext(ctx)) {
            qjs::Value jsValue(ctx, JS_DupValue(ctx, value));
            if (env->coreFromJsValue(jsValue, result)) {
                return result;
            }
        }
        return result;
    }

    static JSValue wrap(JSContext* ctx, const DateTime& value)
    {
        if (JsEnv* env = JsEnv::fromContext(ctx)) {
            qjs::Value jsValue = env->coreToJsValue(value);
            return jsValue.release();
        }
        return JS_UNDEFINED;
    }
};

} // namespace qjs

