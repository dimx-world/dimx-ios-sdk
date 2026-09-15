#include "HttpInterface.h"
#include <Engine.h>
#include <res/ResourceInterface.h>
#include <res/HttpClient.h>

void Http_onResponse(uint64_t id, int status, const char* body, const char* error)
{
    g_resourceInterface().http().complete(id, status, body ? body : "", error ? error : "");
}
