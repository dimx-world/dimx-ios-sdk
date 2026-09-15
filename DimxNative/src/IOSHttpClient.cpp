#include "IOSHttpClient.h"
#include "IOSEngine.h"

bool IOSHttpClient::available() const
{
    return g_swiftEngine()->httpRequest != nullptr;
}

void IOSHttpClient::sendRequest(uint64_t id, const HttpRequest& request)
{
    g_swiftEngine()->httpRequest(id, request.method.c_str(), request.url.c_str(), headersJson(request).c_str(), request.body.c_str());
}
