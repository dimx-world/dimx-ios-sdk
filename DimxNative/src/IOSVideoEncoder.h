#pragma once

#include <multimedia/VideoEncoder.h>
#include <multimedia/MultimediaManager.h>
#include <render/FrameCapture.h>
#include <AvMultimediaManager.h>

// The iOS video encoder, for the engine (MultimediaManager::createVideoEncoder,
// VideoRecorder): the Swift VideoRecorder does the work - AVAssetWriter fed
// from the renderer's capture texture on the GPU in Renderer.endFrame, the
// microphone through ARKit - and this is its handle. A capture sink only so
// that the renderer knows a capture is wanted; the frames go Swift to Swift.
class IOSVideoEncoder: public VideoEncoder, public FrameCaptureSink
{
public:
    IOSVideoEncoder(const std::string& outFilePath, int width, int height);
    ~IOSVideoEncoder() override;

    bool start(bool audio) override;
    void finalize(std::function<void()> callback) override;
    void onCaptureFrame(Renderer& renderer, const FrameContext& frameContext) override {}

    // Swift's word that the file named by a stop is complete (VideoRecorder_onFinished).
    static void onFinished(uint64_t stopId);

private:
    bool mStarted{false};
    bool mFinalized{false};
};

// FFmpeg's media inputs as everywhere, and the platform's own video encoder.
class IOSMultimediaManager: public AvMultimediaManager
{
public:
    std::unique_ptr<VideoEncoder> createVideoEncoder(const std::string& outFilePath, int width, int height) override;
};
