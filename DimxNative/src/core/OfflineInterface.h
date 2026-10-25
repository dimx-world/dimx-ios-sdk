#ifndef OFFLINE_INTERFACE_H_INCLUDED
#define OFFLINE_INTERFACE_H_INCLUDED

#ifdef __cplusplus
extern "C" {
#endif

// Dimensions kept for offline use (res/OfflineStore), as the web view asks through
// WebViewCtrl: everything the engine needs of a dimension fetched into its cache and held
// there, dropped again, and the list of what is kept. The answers come back through the
// SwiftEngine callbacks offlineProgress and offlineDimensions. Safe from any thread; nothing
// happens while no engine runs.
void Offline_saveDimension(const char* dimension);
void Offline_removeDimension(const char* dimension, const char* env);
void Offline_requestDimensions(void);
// The dimension's map index and the packs around the device into the engine's cache, ahead of
// a visit (MapTracker::prefetch) - what the page asks as a dimension's page opens.
void Offline_prefetchMap(const char* dimension);
// The dimension's map visit - the tiles loaded and the ones the fixes matched in
// (MapTracker::publishVisit) - for the studio's map; the answer comes through the SwiftEngine
// callback mapVisit.
void Offline_requestMapVisit(const char* dimension);

#ifdef __cplusplus
}
#endif

#endif // OFFLINE_INTERFACE_H_INCLUDED
