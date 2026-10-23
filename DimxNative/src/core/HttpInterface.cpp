#include "HttpInterface.h"
#include <Engine.h>
#include <res/ResourceInterface.h>
#include <res/HttpClient.h>

void Http_onResponse(uint64_t id, int status, const void* body, size_t bodyLength, const char* error)
{
    std::string bytes = body && bodyLength > 0 ? std::string(static_cast<const char*>(body), bodyLength) : std::string();
    g_resourceInterface().http().complete(id, status, std::move(bytes), error ? error : "");
}
