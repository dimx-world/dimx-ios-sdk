#ifndef TELEMETRY_INTERFACE_H_INCLUDED
#define TELEMETRY_INTERFACE_H_INCLUDED

#ifdef __cplusplus
extern "C" {
#endif

// The engine's telemetry as the Swift side asks it (telemetry/TelemetryManager):
// what the web view is told about this install and its diagnostics policy, and
// the holder's own switch. Safe from any thread; the strings are IString objects
// (String_create / String_cstr / String_delete), empty while no engine runs.
void Telemetry_appInfoJson(void* outStringObj);
void Telemetry_policyJson(void* outStringObj);
void Telemetry_setLocalPolicy(double seconds);
// What iOS said of a previous run's death (CrashReports.swift, MetricKit): an exception with its frames,
// as the compact JSON the crash marker uses ([{m, o, b, s, f, l}]), or an event - reported as that run's.
void Telemetry_reportException(const char* type, const char* value, const char* contextJson, const char* framesJson);
void Telemetry_reportEvent(const char* name, const char* attributesJson);

#ifdef __cplusplus
}
#endif

#endif // TELEMETRY_INTERFACE_H_INCLUDED
