#pragma once
#include <res/HttpClient.h>

/**
 * The iOS HTTP: Swift's HttpClient (a URLSession). A request goes to the
 * SwiftEngine table's httpRequest (Context.initEngineCallbacks), and the
 * answer comes back by id through Http_onResponse (core/HttpInterface.h) into
 * HttpClient::complete. The callback is set before the engine starts; without
 * it the client is not available and the engine reports nothing, saying so.
 */
class IOSHttpClient: public HttpClient
{
public:
    bool available() const override;

protected:
    void sendRequest(uint64_t id, const HttpRequest& request) override;
};
