#pragma once
#include <Common.h>
#include <quickjspp.hpp>

class JsEnv;
class JsAccount
{
public:
    JsAccount(JsEnv* env);

    const std::string& id() const;
    const std::string& email() const;
    bool valid() const;
    static void registerClass(qjs::Context::Module& module) {
        module.class_<JsAccount>("Account")
        .property<&JsAccount::id>("id")
        .property<&JsAccount::email>("email")
        .property<&JsAccount::valid>("valid");
    }

private:
    JsEnv* mEnv{nullptr};
};
