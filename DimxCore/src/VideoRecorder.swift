//
//  VideoRecorder.swift
//  DimxCore
//
//  The iOS video encoder behind the engine's recordings (MediaCapture,
//  IOSVideoEncoder): the renderer's capture texture, converted on the GPU into
//  a pixel buffer and appended to an AVAssetWriter with the frame's host time,
//  plus the microphone (MicrophoneCapture, below) when the recording was
//  started with audio. Nothing is read back to the CPU.
//

import Foundation
import AVFoundation
import Metal
import MetalPerformanceShaders
import QuartzCore
import DimxNative

final class VideoRecorder {
    static let shared = VideoRecorder()
    private init() {}

    private let lock = NSLock()
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var textureCache: CVMetalTextureCache?
    private var converter: MPSImageConversion?
    private var sessionStarted = false
    private var sessionStart = CMTime.invalid
    private var running = false
    private var width = 0
    private var height = 0
    private var framesAppended = 0
    private var framesDropped = 0
    private var audioAppended = 0
    private let appendQueue = DispatchQueue(label: "world.dimx.video-recorder")
    private let microphone = MicrophoneCapture()

    var isRecording: Bool {
        lock.lock(); defer { lock.unlock() }
        return running
    }

    // About 0.13 bits per pixel per frame: 10 Mbit/s for a 1170x2532 screen.
    private func bitRate(_ w: Int, _ h: Int) -> Int {
        let bps = Double(w * h) * 30.0 * 0.13
        return Int(min(max(bps, 4.0e6), 20.0e6))
    }

    /// Opens the file and the inputs and starts the microphone when asked for
    /// sound. Engine thread; the first frame starts the session.
    func start(path: String, width: Int, height: Int, audio: Bool) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if running {
            Logger.error("VideoRecorder: already recording")
            return false
        }
        // Encoders want even dimensions.
        let w = width & ~1
        let h = height & ~1
        let url = URL(fileURLWithPath: path)
        try? FileManager.default.removeItem(at: url)
        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        } catch {
            Logger.error("VideoRecorder: cannot create the writer for [\(path)]: \(error)")
            return false
        }

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: w,
            AVVideoHeightKey: h,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitRate(w, h),
                AVVideoExpectedSourceFrameRateKey: 30,
                AVVideoMaxKeyFrameIntervalKey: 30,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            ],
        ]
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = true
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoInput, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: w,
            kCVPixelBufferHeightKey as String: h,
            kCVPixelBufferMetalCompatibilityKey as String: true,
        ])
        guard writer.canAdd(videoInput) else {
            Logger.error("VideoRecorder: the writer refuses the video input")
            return false
        }
        writer.add(videoInput)

        // The writer converts what the microphone delivers (MicrophoneCapture:
        // the input's own format, 48 kHz mono on the phones) into this.
        var audioInput: AVAssetWriterInput? = nil
        if audio {
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48000,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 96000,
            ]
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            input.expectsMediaDataInRealTime = true
            if writer.canAdd(input) {
                writer.add(input)
                audioInput = input
            } else {
                Logger.warn("VideoRecorder: the writer refuses the audio input - recording without sound")
            }
        }

        guard writer.startWriting() else {
            Logger.error("VideoRecorder: startWriting failed: \(String(describing: writer.error))")
            return false
        }

        let device = Renderer.instance.device!
        var cache: CVMetalTextureCache?
        if CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache) != kCVReturnSuccess {
            Logger.error("VideoRecorder: CVMetalTextureCacheCreate failed")
            writer.cancelWriting()
            return false
        }

        self.writer = writer
        self.videoInput = videoInput
        self.audioInput = audioInput
        self.adaptor = adaptor
        self.textureCache = cache
        self.converter = MPSImageConversion(device: device)
        self.width = w
        self.height = h
        self.sessionStarted = false
        self.sessionStart = .invalid
        self.framesAppended = 0
        self.framesDropped = 0
        self.audioAppended = 0
        self.running = true
        Logger.info("VideoRecorder: recording \(w)x\(h) @ \(bitRate(w, h) / 1000) kbit/s\(audioInput != nil ? " with audio" : " without audio") to [\(path)]")
        if audioInput != nil {
            microphone.start { [weak self] sampleBuffer in
                self?.appendAudio(sampleBuffer)
            }
        }
        return true
    }

    /// The renderer's capture of this frame (Renderer.endFrame): converted into a
    /// pool pixel buffer on the frame's command buffer and appended once the GPU
    /// has written it. Engine thread.
    func encode(_ capture: MTLTexture, commandBuffer: MTLCommandBuffer) {
        lock.lock()
        guard running, let adaptor = adaptor, let videoInput = videoInput, let pool = adaptor.pixelBufferPool,
              let cache = textureCache, let converter = converter else {
            lock.unlock()
            return
        }
        guard videoInput.isReadyForMoreMediaData else {
            framesDropped += 1
            lock.unlock()
            return
        }
        var pixelBuffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBuffer) == kCVReturnSuccess, let pb = pixelBuffer else {
            framesDropped += 1
            lock.unlock()
            return
        }
        var cvTexture: CVMetalTexture?
        guard CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, cache, pb, nil, .bgra8Unorm, width, height, 0, &cvTexture) == kCVReturnSuccess,
              let cvTex = cvTexture, let target = CVMetalTextureGetTexture(cvTex) else {
            framesDropped += 1
            lock.unlock()
            return
        }
        lock.unlock()

        // RGBA8 capture to the BGRA8 pixel buffer: a conversion pass does the
        // channel order, which a blit cannot. The capture may be larger than
        // the even-sized encoder frame by a pixel; the conversion scales.
        converter.encode(commandBuffer: commandBuffer, sourceTexture: capture, destinationTexture: target)

        let time = CMClockGetTime(CMClockGetHostTimeClock())
        commandBuffer.addCompletedHandler { [weak self] _ in
            // The texture wrapper is kept until the GPU is done with it.
            _ = cvTex
            self?.appendQueue.async {
                self?.append(pb, at: time)
            }
        }
    }

    private func append(_ pixelBuffer: CVPixelBuffer, at time: CMTime) {
        lock.lock(); defer { lock.unlock() }
        guard running, let writer = writer, let adaptor = adaptor, let videoInput = videoInput else {
            return
        }
        if !sessionStarted {
            writer.startSession(atSourceTime: time)
            sessionStarted = true
            sessionStart = time
        }
        if !videoInput.isReadyForMoreMediaData {
            framesDropped += 1
            return
        }
        if adaptor.append(pixelBuffer, withPresentationTime: time) {
            framesAppended += 1
        } else {
            framesDropped += 1
            if writer.status == .failed {
                Logger.error("VideoRecorder: the writer failed: \(String(describing: writer.error))")
            }
        }
    }

    /// The microphone's sound (MicrophoneCapture). Any thread.
    private func appendAudio(_ sampleBuffer: CMSampleBuffer) {
        appendQueue.async { [self] in
            lock.lock(); defer { lock.unlock() }
            guard running, sessionStarted, let audioInput = audioInput, audioInput.isReadyForMoreMediaData else {
                return
            }
            // Sound from before the first frame would start the file early.
            if CMTimeCompare(CMSampleBufferGetPresentationTimeStamp(sampleBuffer), sessionStart) < 0 {
                return
            }
            if audioInput.append(sampleBuffer) {
                audioAppended += 1
            }
        }
    }

    /// Ends the file; `VideoRecorder_onFinished(id)` tells the engine once it is complete.
    func stop(id: UInt64) {
        lock.lock()
        guard running, let writer = writer else {
            lock.unlock()
            VideoRecorder_onFinished(id)
            return
        }
        running = false
        let frames = framesAppended
        let dropped = framesDropped
        let audioBuffers = audioAppended
        let videoInput = self.videoInput
        let audioInput = self.audioInput
        let started = sessionStarted
        lock.unlock()

        if audioInput != nil {
            microphone.stop()
        }
        Logger.info("VideoRecorder: finishing after \(frames) frames (\(dropped) dropped)\(audioInput != nil ? " and \(audioBuffers) audio buffers" : "")")
        // Behind the appends already queued, so the last frames land before the end.
        appendQueue.async { [self] in
            videoInput?.markAsFinished()
            audioInput?.markAsFinished()
            let finish = {
                if writer.status == .failed {
                    Logger.error("VideoRecorder: finishWriting failed: \(String(describing: writer.error))")
                } else {
                    Logger.info("VideoRecorder: file complete [\(writer.outputURL.path)]")
                }
                self.lock.lock()
                self.writer = nil
                self.videoInput = nil
                self.audioInput = nil
                self.adaptor = nil
                self.textureCache = nil
                self.converter = nil
                self.lock.unlock()
                VideoRecorder_onFinished(id)
            }
            if started {
                writer.finishWriting(completionHandler: finish)
            } else {
                // Not a single frame: there is no file worth keeping.
                writer.cancelWriting()
                finish()
            }
        }
    }
}

/// The microphone for a recording with sound: AVAudioEngine's input, each
/// buffer handed over as a sample buffer stamped with its host time - the
/// clock the video frames carry - under a play-and-record audio session that
/// lasts as long as the recording. Started and stopped on a queue of its own:
/// an audio session switch and an engine start each take a moment, which
/// neither the engine thread nor the main queue (ARKit's delegate queue, the
/// camera frames' road) should spend.
///
/// Not ARKit's microphone (ARConfiguration.providesAudioData): that one is
/// switched by re-running the AR session in the middle of Live View, and on
/// the iPhone XR the camera frames stopped a few frames into every recording
/// that did it - on the screen and in the file - and no sound arrived. With
/// this one ARKit goes on delivering its 60 frames a second through the
/// recording and the file has its sound.
final class MicrophoneCapture {
    private let queue = DispatchQueue(label: "world.dimx.video-recorder.microphone")
    private var engine: AVAudioEngine?

    func start(_ deliver: @escaping (CMSampleBuffer) -> Void) {
        queue.async { [self] in
            let began = CACurrentMediaTime()
            let audioSession = AVAudioSession.sharedInstance()
            do {
                // The sound stays on the loudspeaker (play and record would
                // otherwise route it to the earpiece) and on Bluetooth headphones.
                try audioSession.setCategory(.playAndRecord, mode: .videoRecording, options: [.defaultToSpeaker, .allowBluetoothA2DP])
                try audioSession.setActive(true)
            } catch {
                Logger.warn("VideoRecorder: the audio session refuses recording - the video is recorded without sound: \(error)")
                restorePlayback()
                return
            }
            let engine = AVAudioEngine()
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                Logger.warn("VideoRecorder: no microphone input (\(format)) - the video is recorded without sound")
                restorePlayback()
                return
            }
            var description: CMAudioFormatDescription?
            guard CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: format.streamDescription,
                                                 layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil,
                                                 extensions: nil, formatDescriptionOut: &description) == noErr,
                  let formatDescription = description else {
                Logger.warn("VideoRecorder: cannot describe the microphone's format (\(format)) - the video is recorded without sound")
                restorePlayback()
                return
            }
            let sampleRate = CMTimeScale(format.sampleRate)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, when in
                if let sampleBuffer = MicrophoneCapture.sampleBuffer(buffer, when, formatDescription, sampleRate) {
                    deliver(sampleBuffer)
                }
            }
            engine.prepare()
            do {
                try engine.start()
            } catch {
                input.removeTap(onBus: 0)
                Logger.warn("VideoRecorder: the microphone does not start - the video is recorded without sound: \(error)")
                restorePlayback()
                return
            }
            self.engine = engine
            Logger.info("VideoRecorder: microphone on, \(Int(format.sampleRate)) Hz x \(format.channelCount), in \(Int((CACurrentMediaTime() - began) * 1000)) ms")
        }
    }

    func stop() {
        queue.async { [self] in
            guard let engine = engine else {
                return
            }
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            self.engine = nil
            restorePlayback()
            Logger.info("VideoRecorder: microphone off")
        }
    }

    // Back to the app's own audio session (Context.initializeInternal).
    private func restorePlayback() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playback)
            try audioSession.setActive(true)
        } catch {
            Logger.warn("VideoRecorder: cannot set the audio session back to playback: \(error)")
        }
    }

    // The engine reuses its buffer once the tap returns: the samples are
    // copied into the sample buffer's own block.
    private static func sampleBuffer(_ buffer: AVAudioPCMBuffer, _ when: AVAudioTime,
                                     _ formatDescription: CMAudioFormatDescription, _ sampleRate: CMTimeScale) -> CMSampleBuffer? {
        let frames = CMItemCount(buffer.frameLength)
        if frames == 0 {
            return nil
        }
        let time = when.isHostTimeValid ? CMClockMakeHostTimeFromSystemUnits(when.hostTime)
                                        : CMClockGetTime(CMClockGetHostTimeClock())
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: sampleRate),
                                        presentationTimeStamp: time, decodeTimeStamp: .invalid)
        var sampleBuffer: CMSampleBuffer?
        guard CMSampleBufferCreate(allocator: kCFAllocatorDefault, dataBuffer: nil, dataReady: false,
                                   makeDataReadyCallback: nil, refcon: nil, formatDescription: formatDescription,
                                   sampleCount: frames, sampleTimingEntryCount: 1, sampleTimingArray: &timing,
                                   sampleSizeEntryCount: 0, sampleSizeArray: nil, sampleBufferOut: &sampleBuffer) == noErr,
              let result = sampleBuffer else {
            return nil
        }
        guard CMSampleBufferSetDataBufferFromAudioBufferList(result, blockBufferAllocator: kCFAllocatorDefault,
                                                             blockBufferMemoryAllocator: kCFAllocatorDefault,
                                                             flags: 0, bufferList: buffer.audioBufferList) == noErr else {
            return nil
        }
        return result
    }
}
