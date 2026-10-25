#include "OfflineInterface.h"
#include <Engine.h>
#include <res/ResourceInterface.h>
#include <tracking/MapTracker.h>

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

void Offline_prefetchMap(const char* dimension)
{
    if (!Engine::valid() || !dimension) {
        return;
    }
    const std::optional<ObjectId> dimId = ObjectId::tryParse(dimension);
    if (!dimId) {
        LOGW("Offline_prefetchMap: not a dimension id");
        return;
    }
    // On the engine thread: the prefetch is the map tracker's cache, which that thread owns.
    g_engine().pushEvent([id = *dimId] { MapTracker::prefetch(id); });
}

void Offline_requestMapVisit(const char* dimension)
{
    if (!Engine::valid() || !dimension) {
        return;
    }
    const std::optional<ObjectId> dimId = ObjectId::tryParse(dimension);
    if (!dimId) {
        LOGW("Offline_requestMapVisit: not a dimension id");
        return;
    }
    // On the engine thread, which the trackers are; the answer comes back as MAP_VISIT.
    g_engine().pushEvent([id = *dimId] { MapTracker::publishVisit(id); });
}
