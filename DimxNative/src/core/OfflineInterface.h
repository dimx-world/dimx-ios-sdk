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

#ifdef __cplusplus
}
#endif

#endif // OFFLINE_INTERFACE_H_INCLUDED
