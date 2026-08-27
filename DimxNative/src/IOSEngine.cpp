#include "IOSEngine.h"

#include "IOSDisplay.h"
#include "IOSInput.h"
#include "render/IOSRenderer.h"
#include "IOSDeviceAR.h"
#include "IOSCloudAnchorSession.h"
#include "IOSAnalyticsManager.h"

#include <FileSystem.h>
#include <CrossFactory.h>
#include <WebResourceInterface.h>
#include <config/ConfigUtils.h>
#include <AvMultimediaManager.h>
#include <AlAudioDevice.h>
#include <ui/imgui/ImGuiManager.h>
#include <AppUtils.h>
#include <BeaconManager.h>
#include <Clock.h>
#include <GeolocationManager.h>
#include <world/World.h>
#include <world/LocationProximityManager.h>
#include <dimensions/app/AppDimension.h>
#include <Log.h>
#include <Profiler.h>

#include "utils/IString.h"

#include <algorithm>

struct SwiftEngine* g_swiftEngine()
{
    static struct SwiftEngine callbacks;
    return &callbacks;
}

// libobjc's pool primitives. @autoreleasepool is Objective-C syntax and this is a
// plain .cpp; these are the same thing underneath and are what the Swift runtime
// itself uses.
extern "C" {
void* objc_autoreleasePoolPush(void);
void  objc_autoreleasePoolPop(void* context);
}

namespace {

std::unique_ptr<IOSEngine> g_engine_instance;

// The engine thread is ours, not Cocoa's, so nothing drains autoreleased objects
// on it: a run loop would do it every turn, and a raw pthread never does. Left
// alone, everything the loop touches through ObjC - Metal command buffers and
// drawables, and above all the ARFrames snapshotted out of DeviceAR - stays
// alive for the life of the process. ARKit counts those as still held by its
// delegate, and once about a dozen pile up it stops delivering camera images
// altogether: the camera freezes while the loop carries on presenting the last
// texture at a perfectly healthy 60 fps.
//
// One pool per iteration, so a frame's garbage dies with the frame.
class AutoreleasePoolGuard
{
public:
    AutoreleasePoolGuard(): mPool(objc_autoreleasePoolPush()) {}
    ~AutoreleasePoolGuard() { objc_autoreleasePoolPop(mPool); }

    AutoreleasePoolGuard(const AutoreleasePoolGuard&) = delete;
    AutoreleasePoolGuard& operator=(const AutoreleasePoolGuard&) = delete;

private:
    void* mPool;
};

// The engine thread runs JS, and quickjs is configured to allow itself a 1 MB C
// stack (kJsMaxStackSize in JsEnv.cpp). Darwin gives a non-main thread 512 KB by
// default, so the JS budget alone would overrun the real stack before quickjs
// noticed - and native frames beneath the JS entry point spend from the same
// budget. Sized well clear of both.
constexpr size_t kEngineThreadStackSize = 4 * 1024 * 1024;

} // namespace

void initEngine(const char* appInstanceId,
                const char* appDataPath,
                const char* localStoragePath,
                const char* cachePath,
                const char* extMediaPath,
                const char* appConfigData,
                long screenWidth,
                long screenHeight)
{
    ASSERT(!g_engine_instance, "Engine already initialized!");

    g_crossFactory().registerTypeOverride<Display, IOSDisplay>(CrossType::Display);
    g_crossFactory().registerTypeOverride<Renderer, IOSRenderer>(CrossType::Renderer);
    g_crossFactory().registerTypeOverride<RemoteResourceInterface, WebResourceInterface>(CrossType::RemoteResourceInterface);
    g_crossFactory().registerTypeOverride<DeviceAR, IOSDeviceAR>(CrossType::DeviceAR);
    g_crossFactory().registerTypeOverride<NativeCloudAnchorSession, IOSCloudAnchorSession>(CrossType::NativeCloudAnchorSession);
    // Physics is not overridden here: dimx-core registers its Jolt backend
    // itself when built with it (CrossFactory.cpp); the Jolt xcframework is a
    // dependency of this target in Package.swift.
    g_crossFactory().registerTypeOverride<AnalyticsManager, IOSAnalyticsManager>(CrossType::AnalyticsManager);
    g_crossFactory().registerTypeOverride<Input, IOSInput>(CrossType::Input);
    g_crossFactory().registerTypeOverride<MultimediaManager, AvMultimediaManager>(CrossType::MultimediaManager);
    g_crossFactory().registerTypeOverride<AudioDevice, AlAudioDevice>(CrossType::AudioDevice);


    Settings::setAppInstanceId(appInstanceId);
    std::string appConfigStr(appConfigData);
    Settings::setAppConfig(ConfigUtils::parseText(appConfigStr.c_str(), appConfigStr.size()));

    // No url/settings/account: the engine is created with the app now, not with
    // a screen. Whichever screen wants a session brings one through
    // reloadEngineSession.
    g_engine_instance = AppUtils::createEngine<IOSEngine>(appDataPath,
                                                          localStoragePath,
                                                          cachePath,
                                                          extMediaPath,
                                                          /*url*/ {},
                                                          /*settingsData*/ {},
                                                          /*accountData*/ {});

    g_engine_instance->setScreenSize(static_cast<int>(screenWidth), static_cast<int>(screenHeight));
    g_engine_instance->start();
}

void reloadEngineSession(const char* url, const char* settingsData, const char* accountData)
{
    if (!g_engine_instance) { return; }

    // Deferred to the engine thread: this reloads settings, the account and the
    // world, all of which belong to it. AfterInit keeps it in order while the
    // engine is still starting up - the same as AndEngine::onActivityResume.
    g_engine_instance->pushEvent([url = std::string(url),
                                  settingsData = std::string(settingsData),
                                  accountData = std::string(accountData)] {
        AppUtils::mobileSessionReload(url, settingsData, accountData);
    }, ExecOpts::AfterInit);
}

void deinitEngine()
{
    g_engine_instance.reset();
}

const void* getEngineConfig()
{
    return &g_engine_instance->config();
}

void engineSetSurfaceAttached(bool attached)
{
    if (!g_engine_instance) { return; }
    g_engine_instance->setSurfaceAttached(attached);
}

void engineSetScreenVisible(bool visible)
{
    if (!g_engine_instance) { return; }
    g_engine_instance->setScreenVisible(visible);
}

void engineEnterBackground()
{
    if (!g_engine_instance) { return; }
    g_engine_instance->enterBackground();
}

void engineEnterForeground()
{
    if (!g_engine_instance) { return; }
    g_engine_instance->enterForeground();
}

void setKeyboardTop(float top)
{
    if (!g_engine_instance) { return; }
    g_imgui().setKeyboardTop(top);
}

void processApplink(const char* rawLink)
{
    ASSERT(g_engine_instance, "processLink: null engine instance!");
    g_engine_instance->processUrl(std::string(rawLink));
}

void processQRCode(const char* code)
{
    if (!g_engine_instance || !code || !*code) { return; }
    // Called from the Swift QR-scanner background queue; pushEvent is mutex-guarded and the
    // lambda runs later on the engine's event-drain thread.
    g_engine_instance->pushEvent([s = std::string(code)]() {
        g_world().appDimension()->onQRCode(s);
    });
}

void processGeolocationUpdate(double lat, double lng, double alt, double hacc, double vacc)
{
    if (!g_engine_instance) { return; }

    // CoreLocation delivers on the main thread; the geolocation manager belongs
    // to the engine thread.
    g_engine_instance->pushEvent([lat, lng, alt, hacc, vacc]() {
        g_geolocation().onDeviceLocationUpdate({lat, lng, alt, hacc, vacc, std::nullopt, GeoCoordsSource::System});
    });
}

void processBeaconObservation(const char* uuid,
                              int major,
                              int minor,
                              int rssi,
                              int measuredPower)
{
    if (!g_engine_instance || !uuid || !*uuid) { return; }

    g_engine_instance->pushEvent([uuid = std::string(uuid), major, minor, rssi, measuredPower]() mutable {
        g_beacons().onObservation(std::move(uuid), major, minor, rssi, measuredPower);
    });
}

void getAnchorsTrackingStatus(const char* dimension,  void* outStringObj)
{
    if (!g_engine_instance) { return; }
    std::string res = g_world().proximityManager()->getAnchorsTrackingStatus(ObjectId::fromString(dimension));
    String_assign(outStringObj, res.c_str());
}

void cppConvertAppUrlToWebUrl(const char* webAppHost, const char* appUrl, void* outStringObj)
{
    std::string res = AppUtils::convertAppUrlToWebUrl(webAppHost, appUrl);
    String_assign(outStringObj, res.c_str());
}

//---------------------------------------------------------------------

IOSEngine::IOSEngine(ConfigPtr config)
: Engine(config)
{
    const double idleFps = this->config().get("engine.idle_fps", 10.0);
    mIdleFrameSec = 1.0 / std::max(idleFps, 1.0);
    mBackgroundDrainSec = this->config().get("engine.background_drain_sec", mBackgroundDrainSec);
}

IOSEngine::~IOSEngine()
{
    shutdown();
}

//------------------------------- Engine thread ------------------------------//

void* IOSEngine::threadEntry(void* self)
{
    pthread_setname_np("dimx-engine");
    static_cast<IOSEngine*>(self)->engineThreadFunc();
    return nullptr;
}

void IOSEngine::start()
{
    ASSERT(!mRunning, "IOSEngine: already started");

    pthread_attr_t attr;
    pthread_attr_init(&attr);
    pthread_attr_setstacksize(&attr, kEngineThreadStackSize);

    // This thread drives the display at 60 Hz. Left at the default it is an
    // ordinary worker as far as the scheduler is concerned and gets demoted
    // under contention or thermal pressure - which the engine never was while it
    // ran on the main thread. Same band as the main thread, for the same reason.
    pthread_attr_set_qos_class_np(&attr, QOS_CLASS_USER_INTERACTIVE, 0);

    mRunning = true;
    const int rc = pthread_create(&mThread, &attr, &IOSEngine::threadEntry, this);
    pthread_attr_destroy(&attr);

    ASSERT(rc == 0, "IOSEngine: failed to create the engine thread [" << rc << "]");
    mThreadStarted = (rc == 0);
    if (!mThreadStarted) {
        mRunning = false;
        return;
    }

    LOGI("IOSEngine: engine thread created with a " << (kEngineThreadStackSize / 1024) << " KB stack");
}

void IOSEngine::shutdown()
{
    if (!mThreadStarted) {
        return;
    }

    LOGI("IOSEngine: shutting down");
    mRunning = false;

    // The loop may be parked with nothing else coming to wake it.
    wakeLoop();

    pthread_join(mThread, nullptr);
    mThreadStarted = false;
    LOGI("IOSEngine: shutdown complete");
}

void IOSEngine::engineThreadFunc()
{
    LOGI("IOSEngine: engine thread started");

    while (mRunning) {
        // First thing in the iteration, so it covers every path out of it -
        // including the `continue` that a presented frame takes.
        AutoreleasePoolGuard autoreleasePool;

        PROFILER_SCOPE("EngineIteration");

        const auto frameStart = std::chrono::steady_clock::now();

        updateLiveMode();

        // Asked, not assumed. Only a presented drawable paces the loop to the
        // display refresh (CAMetalLayer blocks in nextDrawable once the pool is
        // empty); a frame the renderer dropped for want of a layer or a drawable
        // blocks on nothing, and treating it as presented would spin this thread
        // flat out. Everything that did not present has to pace itself below.
        auto& iosRenderer = static_cast<IOSRenderer&>(renderer());
        iosRenderer.clearFramePresented();

        updateMain();

        if (iosRenderer.framePresented()) {
            continue;
        }

        if (mAppInForeground) {
            throttleFrame(frameStart);
        } else {
            parkUntilForeground(frameStart);
        }
    }

    // Has to happen here, on the thread that owns the engine's state and that
    // every Metal object was created and used from.
    {
        AutoreleasePoolGuard autoreleasePool;
        deinitialize();
    }

    // Nothing will ever park again; release anyone still waiting on the
    // background handshake.
    {
        std::lock_guard<std::mutex> lock(mLoopLock);
        mParked = true;
        mParkedCv.notify_all();
    }

    LOGI("IOSEngine: engine thread finished");
}

void IOSEngine::throttleFrame(TimePoint frameStart)
{
    // Nothing is being presented, so nothing paces the loop. While the engine is
    // still loading it should run as fast as it reasonably can; once it is up
    // and merely ticking behind a screen it does not own, it should stay out of
    // the way.
    const double targetSec = currentState() == EngineState::Running ? mIdleFrameSec : mLoadingFrameSec;

    const auto target = std::chrono::duration_cast<std::chrono::steady_clock::duration>(
        std::chrono::duration<double>(targetSec));
    const auto elapsed = std::chrono::steady_clock::now() - frameStart;

    if (elapsed >= target) {
        return;
    }

    // Sleeping on the loop condition rather than plain sleep_for: an arriving AR
    // screen must not wait out an idle frame, and neither must an event that is
    // about to bring the engine back to life, a backgrounding, or shutdown.
    std::unique_lock<std::mutex> lock(mLoopLock);

    mSleeping = true;
    mLoopCv.wait_for(lock, target - elapsed, [this] {
        return mWakeRequested || !mRunning || !mAppInForeground;
    });
    mSleeping = false;
    mWakeRequested = false;
}

void IOSEngine::parkUntilForeground(TimePoint frameStart)
{
    // The app is off screen, but whatever it has already queued still has to
    // come out: keep ticking until the engine has drained. Unlike Android this
    // drain is on a deadline - the main thread is sitting in didEnterBackground
    // waiting for the park, and the watchdog is counting. Work that does not
    // make the deadline stays queued and resumes on the next foreground.
    bool mayDrain = false;
    {
        std::lock_guard<std::mutex> lock(mLoopLock);
        mayDrain = std::chrono::steady_clock::now() < mDrainDeadline;
    }

    if (mayDrain && hasPendingWork()) {
        throttleFrame(frameStart);
        return;
    }

    // Live mode is already off, so nothing new is being submitted; wait for what
    // is still in flight. This is the whole reason enterBackground() blocks -
    // once it returns, the app must not have GPU work outstanding.
    if (g_swiftEngine()->waitForGpuIdle) {
        g_swiftEngine()->waitForGpuIdle();
    }

    std::unique_lock<std::mutex> lock(mLoopLock);

    mSleeping = true;

    // Everything is re-checked under the lock: a foregrounding that landed
    // between the check above and here would otherwise be slept through.
    if (mRunning && !mAppInForeground) {
        LOGI("IOSEngine: app is in the background, parking the update loop");

        mParked = true;
        mParkedCv.notify_all();

        // The engine clock stops with the loop, so the frame that follows the
        // park sees an ordinary delta instead of the whole time spent asleep.
        StopClockGuard clockGuard(&clock());

        // Deliberately not woken by events, unlike AndEngine: an event that
        // arrives while the app is backgrounded is picked up on the next
        // foreground. iOS suspends the process a moment after this anyway, and
        // waking to run engine code in that window buys nothing.
        mLoopCv.wait(lock, [this] {
            return !mRunning || mAppInForeground;
        });

        mParked = false;
        LOGI("IOSEngine: update loop woken");
    }

    mSleeping = false;
    mWakeRequested = false;
}

void IOSEngine::onEventPushed()
{
    // Called on every pushEvent from every thread, so the common case - a
    // running loop that will see the event on its own - must stay free.
    if (!mSleeping) {
        return;
    }
    wakeLoop();
}

void IOSEngine::wakeLoop()
{
    // Both the flag and the notify go under the lock: signalling outside it can
    // slip through the window between the loop testing its predicate and
    // actually parking, and the loop would then sleep with work waiting.
    std::lock_guard<std::mutex> lock(mLoopLock);
    mWakeRequested = true;
    mLoopCv.notify_all();
}

void IOSEngine::updateLiveMode()
{
    // Live mode needs somewhere to draw, a screen showing it, and an app that is
    // allowed to touch the GPU at all.
    setLiveMode(mSurfaceAttached && mScreenVisible && mAppInForeground);
}

//---------------------------- Screen lifecycle ------------------------------//

void IOSEngine::setSurfaceAttached(bool attached)
{
    LOGI("IOSEngine::setSurfaceAttached: " << attached);
    mSurfaceAttached = attached;
    wakeLoop();
}

void IOSEngine::setScreenVisible(bool visible)
{
    LOGI("IOSEngine::setScreenVisible: " << visible);
    mScreenVisible = visible;
    wakeLoop();
}

void IOSEngine::enterBackground()
{
    LOGI("IOSEngine::enterBackground");

    if (!mThreadStarted) {
        return;
    }

    const auto deadline = std::chrono::steady_clock::now() +
        std::chrono::duration_cast<std::chrono::steady_clock::duration>(
            std::chrono::duration<double>(mBackgroundDrainSec));

    std::unique_lock<std::mutex> lock(mLoopLock);

    // Deadline before the flag, both under the lock: the loop only looks at the
    // deadline once it has seen the flag, so this way it cannot read a stale one
    // and skip the drain.
    mDrainDeadline = deadline;
    mAppInForeground = false;
    mWakeRequested = true;
    mLoopCv.notify_all();

    // Block until the loop confirms it has stopped and the GPU has drained. The
    // watchdog gives us a few seconds; the drain deadline above is what keeps
    // this inside them. The extra second is slack for the frame that was already
    // in flight when the notification arrived.
    const auto waitUntil = deadline + std::chrono::seconds(1);
    if (!mParkedCv.wait_until(lock, waitUntil, [this] { return mParked || !mRunning; })) {
        LOGE("IOSEngine: timed out waiting for the update loop to park");
    }
}

void IOSEngine::enterForeground()
{
    LOGI("IOSEngine::enterForeground");
    mAppInForeground = true;
    wakeLoop();
}

//------------------------------ Engine commands -----------------------------//

void IOSEngine::processCommand(const std::string& command, ConfigPtr arguments)
{
    // Base now hands arguments as a ConfigPtr (may be null); read keys off a
    // null-safe empty node instead of a raw string.
    static const Config kEmpty;
    const Config& args = arguments ? *arguments : kEmpty;

    if (command == "BEACONS_REGISTER_UUID") {
        if (g_swiftEngine()->beaconsRegisterUuid) {
            g_swiftEngine()->beaconsRegisterUuid(args.get("uuid", "").c_str());
        }
        return;
    }

    if (command == "BEACONS_STOP_SCANNING") {
        if (g_swiftEngine()->beaconsStopScanning) {
            g_swiftEngine()->beaconsStopScanning();
        }
        return;
    }

    // All of these run on the engine thread and all of them end up in UIKit, so
    // the Swift side of the table dispatches to the main queue.
    if (command == "SHOW_APP_SCREEN") {
        g_swiftEngine()->showAppScreen(args.get("url", "").c_str());
        return;
    }

    if (command == "OPEN_URL") {
        g_swiftEngine()->openUrlExternal(args.get("url", "").c_str());
        return;
    }

    if (command == "REQUEST_GEOLOCATION_UPDATE") {
        g_swiftEngine()->requestGeolocationUpdate();
        return;
    }

    if (command == "MOVE_TO_EXT_MEDIA_FILE") {
        g_swiftEngine()->moveToExtMediaFile(args.get("src", "").c_str(), args.get("dst", "").c_str());
        return;
    }

    if (command == "SHARE_EXT_MEDIA_FILE") {
        g_swiftEngine()->shareExtMediaFile(args.get("path", "").c_str());
        return;
    }

    Engine::processCommand(command, arguments);
}
