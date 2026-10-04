#include "IOSVideoEncoder.h"
#include "IOSEngine.h"
#include <Engine.h>
#include <render/Renderer.h>

#include <map>
#include <mutex>

namespace {

// The stops in flight, by id: the answer comes from Swift on its own queue.
std::mutex g_stopsMutex;
std::map<uint64_t, std::function<void()>> g_stops;
uint64_t g_nextStopId = 1;

} // namespace

IOSVideoEncoder::IOSVideoEncoder(const std::string& outFilePath, int width, int height)
: VideoEncoder(outFilePath, width, height)
{
}

IOSVideoEncoder::~IOSVideoEncoder()
{
    if (mStarted && !mFinalized) {
        g_renderer().removeCaptureSink(this);
        if (g_swiftEngine()->videoRecorderStop) {
            g_swiftEngine()->videoRecorderStop(0);
        }
    }
}

bool IOSVideoEncoder::start(bool audio)
{
    if (mStarted || !g_swiftEngine()->videoRecorderStart) {
        return false;
    }
    if (!g_swiftEngine()->videoRecorderStart(outFilePath().c_str(), width(), height(), audio)) {
        return false;
    }
    mStarted = true;
    g_renderer().addCaptureSink(this);
    return true;
}

void IOSVideoEncoder::finalize(std::function<void()> callback)
{
    if (!mStarted || mFinalized) {
        if (callback) {
            callback();
        }
        return;
    }
    mFinalized = true;
    g_renderer().removeCaptureSink(this);

    uint64_t id = 0;
    {
        std::lock_guard<std::mutex> lock(g_stopsMutex);
        id = g_nextStopId++;
        g_stops.emplace(id, std::move(callback));
    }
    g_swiftEngine()->videoRecorderStop(id);
}

void IOSVideoEncoder::onFinished(uint64_t stopId)
{
    std::function<void()> callback;
    {
        std::lock_guard<std::mutex> lock(g_stopsMutex);
        auto iter = g_stops.find(stopId);
        if (iter == g_stops.end()) {
            return;
        }
        callback = std::move(iter->second);
        g_stops.erase(iter);
    }
    if (callback) {
        g_engine().pushEvent(std::move(callback));
    }
}

std::unique_ptr<VideoEncoder> IOSMultimediaManager::createVideoEncoder(const std::string& outFilePath, int width, int height)
{
    return std::make_unique<IOSVideoEncoder>(outFilePath, width, height);
}

// --- C, for Swift

void VideoRecorder_onFinished(uint64_t stopId)
{
    IOSVideoEncoder::onFinished(stopId);
}

void Engine_onPermissionResult(uint64_t requestId, bool granted)
{
    if (Engine::valid()) {
        g_engine().onPermissionResult(requestId, granted);
    }
}
