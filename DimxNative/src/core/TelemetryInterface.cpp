#include "TelemetryInterface.h"
#include "../utils/IString.h"
#include <Engine.h>
#include <telemetry/TelemetryManager.h>

// The engine's telemetry as the web view asks it (WebViewCtrl: getAppInfo,
// getTelemetryPolicy, setDiagnostics). The engine is created by Context
// (initEngine), before any web view that could ask.

void Telemetry_appInfoJson(void* outStringObj)
{
    String_assign(outStringObj, g_telemetry().appInfoJson().c_str());
}

void Telemetry_policyJson(void* outStringObj)
{
    String_assign(outStringObj, g_telemetry().policyJson().c_str());
}

void Telemetry_reportException(const char* type, const char* value, const char* contextJson, const char* framesJson)
{
    if (!Engine::valid()) {
        return;
    }
    g_telemetry().reportExternalException(type ? type : "", value ? value : "", contextJson ? contextJson : "", framesJson ? framesJson : "");
}

void Telemetry_reportEvent(const char* name, const char* attributesJson)
{
    if (!Engine::valid()) {
        return;
    }
    g_telemetry().reportExternalEvent(name ? name : "", attributesJson ? attributesJson : "");
}

void Telemetry_setLocalPolicy(double seconds)
{
    // The policy is the engine thread's, like every event of its own.
    g_engine().pushEvent([seconds] { g_telemetry().setLocalPolicy(seconds); });
}
