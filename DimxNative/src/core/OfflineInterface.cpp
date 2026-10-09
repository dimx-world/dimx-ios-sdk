#include "OfflineInterface.h"
#include <Engine.h>
#include <res/ResourceInterface.h>

// The page's text. ObjectId::fromString throws on anything but digits, and in the iOS app a
// catch of std::exception does not catch libc++'s exceptions - so it is never called on it.
void Offline_saveDimension(const char* dimension)
{
    if (!Engine::valid() || !dimension) {
        return;
    }
    const std::optional<ObjectId> dimId = ObjectId::tryParse(dimension);
    if (!dimId) {
        LOGW("Offline_saveDimension: not a dimension id");
        return;
    }
    g_resourceInterface().saveDimensionOffline(*dimId);
}

void Offline_removeDimension(const char* dimension, const char* env)
{
    if (!Engine::valid() || !dimension) {
        return;
    }
    const std::optional<ObjectId> dimId = ObjectId::tryParse(dimension);
    if (!dimId) {
        LOGW("Offline_removeDimension: not a dimension id");
        return;
    }
    g_resourceInterface().removeDimensionOffline(*dimId, env ? env : "");
}

void Offline_requestDimensions(void)
{
    if (!Engine::valid()) {
        return;
    }
    g_resourceInterface().publishOfflineDimensions();
}
