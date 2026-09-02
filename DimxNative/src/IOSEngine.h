#ifndef IOS_ENGINE_H_INCLUDED
#define IOS_ENGINE_H_INCLUDED

#include <stdbool.h>

//---------------------------------------------------------------
#ifdef __cplusplus
extern "C" {
#endif // __cplusplus

// Swift entry points the engine calls into. Everything here is invoked from the
// engine thread, so anything touching UIKit must hop to the main queue on the
// Swift side of the table (see Context.initEngineCallbacks).
struct SwiftEngine
{
    void (*showKeyboard)();
    void (*hideKeyboard)();
    void (*showAppScreen)(const char*);
    void (*openUrlExternal)(const char*);
    void (*requestGeolocationUpdate)();
    void (*beaconsRegisterUuid)(const char*);
    void (*beaconsStopScanning)();
    void (*updateGeolocation)(const char*);
    void (*moveToExtMediaFile)(const char* src, const char* dst);
    void (*shareExtMediaFile)(const char*);

    // Blocks until every command buffer the renderer has committed has
    // completed. The one callback that is deliberately synchronous: the loop
    // calls it on its way into a background park, and the whole point is that
    // no GPU work is still in flight when the park is acknowledged.
    void (*waitForGpuIdle)();
};
struct SwiftEngine* g_swiftEngine();

// Creates the engine and starts its thread. The engine lives as long as the
// process from here on - screens only lend it a surface. No url/settings/account
// here: a screen brings those with it, through reloadEngineSession.
//
// screenWidth/screenHeight seed the display, which builds UI frames from the
// moment the engine starts, long before any layer is attached.
void initEngine(const char* appInstanceId,
                const char* appDataPath,
                const char* localStoragePath,
                const char* cachePath,
                const char* extMediaPath,
                const char* appConfigData,
                long screenWidth,
                long screenHeight);
void reloadEngineSession(const char* url, const char* settingsData, const char* accountData);
void deinitEngine();
const void* getEngineConfig();

// Whether the AR screen has handed the renderer a layer to draw into, and
// whether that screen is actually on top. Live mode needs both (plus a
// foregrounded app). Safe from the main thread.
void engineSetSurfaceAttached(bool attached);
void engineSetScreenVisible(bool visible);

// App lifecycle. engineEnterBackground BLOCKS until the update loop has stopped
// and the GPU has drained - see IOSEngine::enterBackground.
void engineEnterBackground();
void engineEnterForeground();

void setKeyboardTop(float top);
void processApplink(const char* rawLink);
void processQRCode(const char* code);
void processGeolocationUpdate(double lat, double lng, double alt, double hacc, double vacc);
void requestGeolocationUpdate();
void processBeaconObservation(const char* uuid, int major, int minor, int rssi, int measuredPower);
void getAnchorsTrackingStatus(const char* dimension, void* outStringObj);
void cppConvertAppUrlToWebUrl(const char* webAppHost, const char* appUrl, void* outStringObj);

#ifdef __cplusplus
} // extern "C"
#endif // __cplusplus
//---------------------------------------------------------------

#ifdef __cplusplus
#include <Engine.h>

#include <pthread.h>
#include <sys/qos.h>

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <mutex>
#include <thread>

// The engine lives as long as the process, not as long as a screen. It runs on
// its own thread and keeps updating whether or not anything is on screen: with a
// layer attached and the AR screen up it draws and the presented drawable paces
// the loop, without one it carries on at a reduced rate out of live mode, and
// with the app off screen entirely it drains what it has and parks.
//
// The parking handshake is where this differs from AndEngine. On Android parking
// is a battery optimisation and the notification returns immediately. On iOS
// submitting GPU work after didEnterBackground gets the app killed, so
// enterBackground() blocks until the loop confirms it has stopped.
class IOSEngine: public Engine
{
public:
    using TimePoint = std::chrono::steady_clock::time_point;

    IOSEngine(ConfigPtr config);
    ~IOSEngine() override;

    // Seeded from UIScreen before the thread starts, read by IOSDisplay on it.
    void setScreenSize(int width, int height) { mScreenWidth = width; mScreenHeight = height; }
    int screenWidth() const { return mScreenWidth; }
    int screenHeight() const { return mScreenHeight; }

    // Starts the engine thread. Separate from the constructor so that the
    // instance is fully published before the loop touches it.
    void start();

    // Stops the loop and joins the thread, deinitializing the engine on it.
    void shutdown();

    // Brings the update loop out of a park, or cuts an idle frame short. Safe
    // from any thread.
    void wakeLoop();

    void processCommand(const std::string& command, ConfigPtr arguments = {}) override;

    void setSurfaceAttached(bool attached);
    void setScreenVisible(bool visible);

    // Blocks until the loop has parked and the GPU is idle. Must be called from
    // the main thread, from didEnterBackground and nowhere else.
    void enterBackground();
    void enterForeground();

private:
    static void* threadEntry(void* self);
    void engineThreadFunc();
    void updateLiveMode();
    void throttleFrame(TimePoint frameStart);
    void parkUntilForeground(TimePoint frameStart);
    void onEventPushed() override;

private:
    int mScreenWidth{0};
    int mScreenHeight{0};

    // A pthread rather than std::thread purely so the stack size can be set.
    // std::thread cannot, and Darwin's default for a non-main thread is 512 KB -
    // half of what quickjs is told it may use (kJsMaxStackSize in JsEnv.cpp,
    // whose comment assumes bionic's 1 MB). On the main thread, where the engine
    // used to run, that just about fit; here it would smash the stack before
    // quickjs's own overflow guard ever tripped.
    pthread_t mThread{};
    bool mThreadStarted{false};
    std::atomic_bool mRunning{false};

    // What the update loop parks on when there is nothing to do.
    std::mutex mLoopLock;
    std::condition_variable mLoopCv;
    bool mWakeRequested{false};

    // The other half of the background handshake: the loop signals it here,
    // enterBackground() waits on it.
    std::condition_variable mParkedCv;
    bool mParked{false};

    // How long the loop may keep draining pending work once the app has gone
    // off screen. Android drains until hasPendingWork() goes false with no
    // deadline; here the main thread is blocked on this and the watchdog is
    // counting, so whatever does not make the deadline stays queued for the
    // next foreground.
    TimePoint mDrainDeadline;

    // Set while the loop is waiting - parked, or sitting out an idle frame - so
    // that pushEvent() only pays for a lock and a notify when there is actually
    // someone to wake.
    std::atomic_bool mSleeping{false};

    // The engine is created while the app is on screen.
    std::atomic_bool mAppInForeground{true};

    // The AR screen's layer, and whether that screen is on top.
    std::atomic_bool mSurfaceAttached{false};
    std::atomic_bool mScreenVisible{false};

    double mIdleFrameSec{0.1};
    double mLoadingFrameSec{1.0 / 60.0};
    // Worst case for didEnterBackground is this plus a second of slack for a
    // frame already in flight (nextDrawable blocks for up to a second once the
    // app loses the screen). The watchdog allows a handful of seconds.
    double mBackgroundDrainSec{1.5};
};

inline IOSEngine& g_iosEngine() { return static_cast<IOSEngine&>(g_engine()); }
#endif // __cplusplus

#endif // IOS_ENGINE_H_INCLUDED
