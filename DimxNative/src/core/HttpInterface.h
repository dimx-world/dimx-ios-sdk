#ifndef HTTP_INTERFACE_H_INCLUDED
#define HTTP_INTERFACE_H_INCLUDED

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// The Swift side's answer to an engine HTTP request (SwiftEngine.httpRequest,
// served by HttpClient.swift): the status and body, or the error, under the
// id the request carried. The body is bytes and their count - a map's pack is
// binary, which a C string would end at its first zero byte. Safe from any
// thread; the engine's callback runs on its own thread.
void Http_onResponse(uint64_t id, int status, const void* body, size_t bodyLength, const char* error);

#ifdef __cplusplus
}
#endif

#endif // HTTP_INTERFACE_H_INCLUDED
