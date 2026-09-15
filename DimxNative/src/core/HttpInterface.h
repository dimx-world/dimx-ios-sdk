#ifndef HTTP_INTERFACE_H_INCLUDED
#define HTTP_INTERFACE_H_INCLUDED

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// The Swift side's answer to an engine HTTP request (SwiftEngine.httpRequest,
// served by HttpClient.swift): the status and body, or the error, under the
// id the request carried. Safe from any thread; the engine's callback runs on
// its own thread.
void Http_onResponse(uint64_t id, int status, const char* body, const char* error);

#ifdef __cplusplus
}
#endif

#endif // HTTP_INTERFACE_H_INCLUDED
