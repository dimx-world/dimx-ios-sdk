#pragma once
#include "Common.h"
#include <quickjspp.hpp>
#include "JsPromise.h"
#include <CommonMath.h>
#include <Transform.h>
#include <DateTime.h>

#include <thread>
#include <mutex>
#include <unordered_map>

class Config;
class Buffer;

DECLARE_PTR(JsEnv)
class JsEnv
{
    using FileLoader = std::function<std::shared_ptr<Buffer>(const std::string&)>;

    struct TypedConstructors {
        TypedConstructors(JSContext * ctx):
            date(ctx, JS_NULL),
            vec2(ctx, JS_NULL),
            vec3(ctx, JS_NULL),
            vec4(ctx, JS_NULL),
            quat(ctx, JS_NULL),
            transform(ctx, JS_NULL),
            ray(ctx, JS_NULL)
        {}
        bool initialized{ false };
        qjs::Value date;
        qjs::Value vec2;
        qjs::Value vec3;
        qjs::Value vec4;
        qjs::Value quat;
        qjs::Value transform;
        qjs::Value ray;
    };

public:
    JsEnv(const std::string& name, FileLoader loader = {});
    ~JsEnv();

    qjs::Value eval(std::string_view buffer, const char * filename = "<eval>", unsigned int flags = 0);
    qjs::Value evalFile(const std::string& filename, unsigned int flags = JS_EVAL_TYPE_MODULE);

    qjs::Context::Module& dimxModule() {
        ASSERT(std::this_thread::get_id() == mCreationThreadId, "JsEnv bad thread: " << std::this_thread::get_id());
        ASSERT(mContext.modules.size() == 1, "Expected only one module in js context!. Actual: " << mContext.modules.size());
        return mContext.modules[0];
    };

    JSContext* jsContext() const {
        //ASSERT(std::this_thread::get_id() == mCreationThreadId, "JsEnv bad thread: " << std::this_thread::get_id());
        return mContext.ctx;
    }

    qjs::Value global() { return mContext.global(); }

    qjs::Value newObject() { return mContext.newObject(); }

    std::shared_ptr<JsPromise> createPromise() { return std::make_shared<JsPromise>(this, false); }

    template <typename T> bool isCoreType(const qjs::Value& value);

    template <typename T>
    qjs::Value coreToJsValue(const T& value);

    template <typename T>
    bool coreFromJsValue(qjs::Value& jsValue, T& outValue);

    void registerClusterModule(const std::string& clusterName, const std::string& filePath);
    std::string getClusterModulePath(const std::string& clusterName) const;

    // Unprotected calls!
    Config jsValueToConfig(qjs::Value value);         // these calls are originated from javascript
    qjs::Value configToJsValue(const Config& config); // must always be done within safeCall()

    void update(const FrameContext& frameContext);

    static JsEnv* fromContext(JSContext* ctx);

    template <typename Call, typename... Args>
    void safeCall(Call call, Args&&... args) {
        std::lock_guard<std::recursive_mutex> lock(mMutex);
        try {
            call(std::forward<decltype(args)>(args)...);
            if (!JS_IsNull(JS_PeekException(mContext.ctx))) {
                handleCurrentException();
            }
        } catch (qjs::exception) {
            handleCurrentException();
        }
    }

    template <typename Call, typename... Args>
    std::invoke_result_t<Call> safeCallRet(Call call, Args&&... args) {
        std::lock_guard<std::recursive_mutex> lock(mMutex);
        try {
            auto res = call(std::forward<decltype(args)>(args)...);
            if (!JS_IsNull(JS_PeekException(mContext.ctx))) {
                handleCurrentException();
                return {};
            }
            return res;
        } catch (qjs::exception) {
            handleCurrentException();
        }
        return {};
    }

    qjs::Value undefined() { return qjs::Value{mContext.ctx, JS_UNDEFINED}; }
    qjs::Value null()      { return qjs::Value{mContext.ctx, JS_NULL}; }

    template<typename T> qjs::Value ptrToJsValue(T* ptr);
    template<typename T> T* ptrFromJsValue(qjs::Value& jsValue);

private:
    std::string loadTextFile(const std::string& filePath);
    void handleCurrentException(size_t depth = 0);
    bool parseTypedValue(qjs::Value& jsValue, Config& outConfig);
    const TypedConstructors& getTypedCtors();

private:
    std::thread::id mCreationThreadId;
    std::recursive_mutex mMutex;
    FileLoader mFileLoader;
    qjs::Runtime mRuntime;
    qjs::Context mContext;
    TypedConstructors mTypedCtors;

    // Registry for cluster modules that can be imported by name
    std::unordered_map<std::string, std::string> mClusterModules;
};

template<typename T>
qjs::Value JsEnv::ptrToJsValue(T* ptr)
{
    if (ptr == nullptr) {
        return qjs::Value{mContext.ctx, JS_NULL};
    }
    return qjs::Value{mContext.ctx, ptr};
}
template<typename T> T* JsEnv::ptrFromJsValue(qjs::Value& jsValue)
{
    if (JS_IsNull(jsValue.v) || JS_IsUndefined(jsValue.v) || JS_IsUninitialized(jsValue.v)) {
        return nullptr;
    }

    try {
        return jsValue.as<T*>();
    } catch (...) {
        LOGE("JsEnv::ptrFromJsValue: Failed to convert JSValue to pointer");
        return nullptr;
    }

    return nullptr;
}

template <typename T>
qjs::Value JsEnv::coreToJsValue(const T&)
{
    static_assert(sizeof(T) == 0, "Unsupported type for coreToJsValue");
    return {mContext.ctx, JS_UNDEFINED};
}

template <typename T>
bool JsEnv::coreFromJsValue(qjs::Value&, T&)
{
    static_assert(sizeof(T) == 0, "Unsupported type for coreFromJsValue");
    return false;
}

template <> qjs::Value JsEnv::coreToJsValue<qjs::Value>(const qjs::Value& value);
template <> bool JsEnv::coreFromJsValue<qjs::Value>(qjs::Value& jsValue, qjs::Value& outValue);

template <> qjs::Value JsEnv::coreToJsValue<double>(const double& value);
template <> bool JsEnv::coreFromJsValue<double>(qjs::Value& jsValue, double& outValue);

template <> qjs::Value JsEnv::coreToJsValue<Vec2>(const Vec2& value);
template <> bool JsEnv::coreFromJsValue<Vec2>(qjs::Value& jsValue, Vec2& outValue);

template <> bool JsEnv::isCoreType<Vec3>(const qjs::Value& value);
template <> qjs::Value JsEnv::coreToJsValue<Vec3>(const Vec3& value);
template <> bool JsEnv::coreFromJsValue<Vec3>(qjs::Value& jsValue, Vec3& outValue);

template <> qjs::Value JsEnv::coreToJsValue<Vec4>(const Vec4& value);
template <> bool JsEnv::coreFromJsValue<Vec4>(qjs::Value& jsValue, Vec4& outValue);

template <> qjs::Value JsEnv::coreToJsValue<Quat>(const Quat& value);
template <> bool JsEnv::coreFromJsValue<Quat>(qjs::Value& jsValue, Quat& outValue);

template <> qjs::Value JsEnv::coreToJsValue<Transform>(const Transform& value);
template <> bool JsEnv::coreFromJsValue<Transform>(qjs::Value& jsValue, Transform& outValue);

template <> qjs::Value JsEnv::coreToJsValue<Ray>(const Ray& value);
template <> bool JsEnv::coreFromJsValue<Ray>(qjs::Value& jsValue, Ray& outValue);

template <> qjs::Value JsEnv::coreToJsValue<DateTime>(const DateTime& value);
template <> bool JsEnv::coreFromJsValue<DateTime>(qjs::Value& jsValue, DateTime& outValue);