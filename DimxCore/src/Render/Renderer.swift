import UIKit
import Metal
import MetalKit
import ARKit
import CoreVideo
import DimxNative

func validateVertexAttributeEnum()
{
    /*
     See ShaderCommon.h
     VertexAttribute and FunctionConstant must match core VertexAttribType!
     This is required to match vertex attributes to shader inputs.
     */
    if (VertexAttribute.vPosition.rawValue      != VertexAttribType_index("vPosition"))            { fatalError("VertexAttribute mismatch") }
    if (VertexAttribute.vPosition.rawValue      != FunctionConstant.FCPositionAttr.rawValue)       { fatalError("VertexAttribute mismatch") }
    
    if (VertexAttribute.vPosition2.rawValue     != VertexAttribType_index("vPosition2"))           { fatalError("VertexAttribute mismatch") }
    if (VertexAttribute.vPosition2.rawValue     != FunctionConstant.FCPosition2Attr.rawValue)      { fatalError("VertexAttribute mismatch") }
    
    if (VertexAttribute.vNormal.rawValue        != VertexAttribType_index("vNormal"))              { fatalError("VertexAttribute mismatch") }
    if (VertexAttribute.vNormal.rawValue        != FunctionConstant.FCNormalAttr.rawValue)         { fatalError("VertexAttribute mismatch") }
    
    if (VertexAttribute.vTangent.rawValue       != VertexAttribType_index("vTangent"))             { fatalError("VertexAttribute mismatch") }
    if (VertexAttribute.vTangent.rawValue       != FunctionConstant.FCTangentAttr.rawValue)        { fatalError("VertexAttribute mismatch") }
    
    if (VertexAttribute.vBitangent.rawValue     != VertexAttribType_index("vBitangent"))           { fatalError("VertexAttribute mismatch") }
    if (VertexAttribute.vBitangent.rawValue     != FunctionConstant.FCBitangentAttr.rawValue)      { fatalError("VertexAttribute mismatch") }
    
    if (VertexAttribute.vTexCoord.rawValue      != VertexAttribType_index("vTexCoord"))            { fatalError("VertexAttribute mismatch") }
    if (VertexAttribute.vTexCoord.rawValue      != FunctionConstant.FCTexCoordAttr.rawValue)       { fatalError("VertexAttribute mismatch") }
    
    if (VertexAttribute.vColor.rawValue         != VertexAttribType_index("vColor"))               { fatalError("VertexAttribute mismatch") }
    if (VertexAttribute.vColor.rawValue         != FunctionConstant.FCColorAttr.rawValue)          { fatalError("VertexAttribute mismatch") }
    
    if (VertexAttribute.vColorUB.rawValue       != VertexAttribType_index("vColorUB"))             { fatalError("VertexAttribute mismatch") }
    if (VertexAttribute.vColorUB.rawValue       != FunctionConstant.FCColorUBAttr.rawValue)        { fatalError("VertexAttribute mismatch") }
    
    if (VertexAttribute.vJointIndex.rawValue    != VertexAttribType_index("vJointIndex"))          { fatalError("VertexAttribute mismatch") }
    if (VertexAttribute.vJointIndex.rawValue    != FunctionConstant.FCJointIndexAttr.rawValue)     { fatalError("VertexAttribute mismatch") }
    
    if (VertexAttribute.vJointIndices4.rawValue != VertexAttribType_index("vJointIndices4"))       { fatalError("VertexAttribute mismatch") }
    if (VertexAttribute.vJointIndices4.rawValue != FunctionConstant.FCJointIndices4Attr.rawValue)  { fatalError("VertexAttribute mismatch") }
    
    if (VertexAttribute.vJointWeights4.rawValue != VertexAttribType_index("vJointWeights4"))       { fatalError("VertexAttribute mismatch") }
    if (VertexAttribute.vJointWeights4.rawValue != FunctionConstant.FCJointWeights4Attr.rawValue)  { fatalError("VertexAttribute mismatch") }
    
    if (VertexAttribute.vNone.rawValue          != VertexAttribType_index("None"))                 { fatalError("VertexAttribute mismatch") }
    if (VertexAttribute.vNone.rawValue          != FunctionConstant.FCNoneAttr.rawValue)           { fatalError("VertexAttribute mismatch") }
}

class Renderer
{
    static /*private*/ let instance = Renderer()
    private init() {}

    // The renderer outlives every screen. It is created with the app, draws from
    // the engine thread, and only borrows a layer while an AR screen is up - so
    // there is deliberately no view here, and nothing that needs one to exist.
    //
    // Metal makes this easy: buffers, textures and pipeline states belong to the
    // MTLDevice, not to a surface, so nothing is lost when the layer goes away
    // and there is no context to keep current on any particular thread.
    private let layerLock = NSLock()
    private var metalLayer: CAMetalLayer?
    private var lastDrawable: CAMetalDrawable?
    private var lastCommandBuffer: MTLCommandBuffer?
    private var firstPresentHandler: (() -> Void)?

    // Matches CAMetalLayer's default maximumDrawableCount: three frames may be
    // in flight, and the fourth waits for the first to finish on the GPU.
    private static let maxFramesInFlight = 3
    private let inFlightSemaphore = DispatchSemaphore(value: Renderer.maxFramesInFlight)

    // Attachment formats. These used to be read off the MTKView, which was
    // always a little wrong: pipeline states are cached for the renderer's
    // lifetime, so the formats they are compiled against have to be fixed rather
    // than whatever the current surface happens to say.
    let colorPixelFormat: MTLPixelFormat = .rgba8Unorm
    let depthStencilPixelFormat: MTLPixelFormat = .depth32Float_stencil8

    var device: MTLDevice!
    var commandQueue: MTLCommandQueue!
    var depthStencilState: MTLDepthStencilState!
    
    var depthStencilTexture: MTLTexture?
    
    var textures: [Texture?] = []
    var materials: [Material?] = []
    var meshes: [Mesh?] = []

    // Every material builds a pipeline state per pass, but the state depends only on
    // the shader specialization (function constants), the vertex layout and the pass -
    // never on which material asked for it. 500 instances of one model would otherwise
    // compile the same handful of specializations 500 times over. Keyed and shared here
    // for the renderer's lifetime, mirroring GlRenderer's mPrograms.
    var pipelineStates: [Material.PipelineKey: MTLRenderPipelineState] = [:]
    var renderables: [Renderable?] = []
    var scenes: [Scene?] = []

    var backgroundPass: BackgroundPass!
    var occlusionPass: OcclusionPass!
    var defaultPass: DefaultPass!
    var imguiPass: ImGuiPass!
    var debugPass: DebugPass!
    var shadowMapPass: ShadowMapPass!
    var shadowsPass: ShadowsPass!
    
    var frameContext = FrameContext()

    // The frame capture (Renderer: frame capture): a copy of the drawable after
    // the 3D passes with the capture overlays drawn in, taken only in frames
    // something wants it - the video recorder, a photo request - and released
    // when nothing does.
    private var captureTexture: MTLTexture?
    private var photoBuffer: MTLBuffer?

    // Occlusion by the real world (the user's Depth Occlusion setting; DeviceAR
    // puts the depth into the frames): this frame's depth - metres along the
    // camera's axis, laid out as the camera image - and its matte, with the
    // transform from the screen to that layout. A texel of no depth and a full
    // matte stand in when there is none: the standard shader binds both whether
    // or not it reads them. Engine thread, like the rest of the frame.
    struct DepthOcclusion {
        var active = false
        var map: MTLTexture
        var matte: MTLTexture
        var uvTransform = matrix_identity_float3x3
        var aspectRatio: Float = 1
    }
    private(set) var depthOcclusion: DepthOcclusion!
    private var noDepthTexture: MTLTexture!
    private var fullMatteTexture: MTLTexture!
    private var depthTextureCache: CVMetalTextureCache?
    private var matteGenerator: ARMatteGenerator?
    private var depthSourceLogged = ""

    // Cached rather than read from the layer: this is read from the engine
    // thread every frame and from the main thread on every touch, and CALayer
    // properties are not for either of those. Seeded from the screen at startup
    // and updated by the AR view when it lays out.
    private let sizeLock = NSLock()
    private var mViewportSize = CGSize(width: 1, height: 1)

    var viewportSize: CGSize {
        sizeLock.lock()
        defer { sizeLock.unlock() }
        return mViewportSize
    }

    static func initCallbacks() {
        g_swiftRenderer().pointee.initialize = { (configPtr: Optional<UnsafeRawPointer>) -> () in Renderer.instance.initialize(configPtr!) }
        g_swiftRenderer().pointee.postInit = { (configPtr: Optional<UnsafeRawPointer>) -> () in Renderer.instance.postInit(configPtr!) }
        g_swiftRenderer().pointee.beginFrame = { (contextPtr: Optional<UnsafeRawPointer>) -> () in Renderer.instance.beginFrame(contextPtr!) }
        g_swiftRenderer().pointee.endFrame = { () -> Bool in return Renderer.instance.endFrame() }
        g_swiftRenderer().pointee.getFrameImageData = { (width: Int, height: Int, outPtr: Optional<UnsafeMutableRawPointer>) -> () in Renderer.instance.getFrameImageData(width, height, outPtr!) }
        
        g_swiftRenderer().pointee.createScene = { (ptr: Optional<UnsafeRawPointer>) -> (Int) in return Renderer.instance.createScene(ptr!) }
        g_swiftRenderer().pointee.deleteScene = { (id: Int) -> () in return Renderer.instance.deleteScene(id) }
/*
        testCallback({
            (meshPtr: Optional<UnsafeRawPointer>) -> (Int) in
            return Renderer.instance.createMesh(meshPtr: meshPtr!)
        })
*/
    }
    
    static func initSingleton(_ device: MTLDevice, _ screenSize: CGSize) {
        if instance.device != nil {
            fatalError("Renderer already initialized")
        }
        instance.device = device
        instance.setViewportSize(screenSize)

        validateVertexAttributeEnum()
    }

    // MARK: - Surface

    // Called from the main thread when the AR view appears / disappears. The
    // engine thread only ever takes a strong reference to whatever is here at
    // the top of a frame, so a detach that lands mid-frame just means one more
    // frame is drawn into a layer nobody is looking at - which costs nothing and
    // is a great deal cheaper than making the main thread wait out a frame.
    // onFirstPresent fires on the main thread once a frame drawn since this
    // attach is actually on screen - not merely committed. A CAMetalLayer keeps
    // displaying its last presented drawable, so on re-entry the previous
    // session's final frame is what the layer composites until this fires; the
    // AR screen keeps it covered until then.
    func attachLayer(_ layer: CAMetalLayer, onFirstPresent: (() -> Void)? = nil) {
        layer.device = device
        layer.pixelFormat = colorPixelFormat
        layer.framebufferOnly = false // getFrameImageData reads the drawable back

        layerLock.lock()
        metalLayer = layer
        firstPresentHandler = onFirstPresent
        layerLock.unlock()
    }

    func detachLayer() {
        layerLock.lock()
        metalLayer = nil
        lastDrawable = nil
        // Nothing will present into this layer again; a handler left here would
        // never fire, and the next attach installs its own.
        firstPresentHandler = nil
        layerLock.unlock()
    }

    func setViewportSize(_ size: CGSize) {
        let clamped = CGSize(width: max(size.width, 1), height: max(size.height, 1))
        sizeLock.lock()
        mViewportSize = clamped
        sizeLock.unlock()
    }

    // Blocks until everything committed so far has finished on the GPU. Called
    // from the engine thread on its way into a background park: iOS kills an app
    // that still has GPU work outstanding once it is backgrounded.
    func waitForGpuIdle() {
        layerLock.lock()
        let commandBuffer = lastCommandBuffer
        layerLock.unlock()

        commandBuffer?.waitUntilCompleted()
    }

    func initialize(_ configPtr: UnsafeRawPointer) {
        Logger.info("renderer initalize")
        commandQueue = device.makeCommandQueue()

        let depthStencilDescriptor = MTLDepthStencilDescriptor()
        depthStencilDescriptor.depthCompareFunction = .lessEqual
        depthStencilDescriptor.isDepthWriteEnabled = true
        depthStencilState = device.makeDepthStencilState(descriptor: depthStencilDescriptor)

        updateDepthStencilTexture(viewportSize)

        noDepthTexture = makeTexel(.r32Float, Float(0))
        fullMatteTexture = makeTexel(.r8Unorm, UInt8(255))
        depthOcclusion = DepthOcclusion(map: noDepthTexture, matte: fullMatteTexture)
        var cache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(nil, nil, device, nil, &cache)
        depthTextureCache = cache

        backgroundPass = BackgroundPass(self)
        occlusionPass = OcclusionPass(self)
        defaultPass = DefaultPass(self)
        debugPass = DebugPass(self)
        shadowMapPass = ShadowMapPass(self)
        shadowsPass = ShadowsPass(self)
        
    }
    
    func postInit(_ configPtr: UnsafeRawPointer) {
        /*
        backgroundPass = BackgroundPass(renderer: self)
        occlusionPass = OcclusionPass(renderer: self)
        defaultPass = DefaultPass(renderer: self)
        debugPass = DebugPass(renderer: self)
        shadowMapPass = ShadowMapPass(renderer: self)
        shadowsPass = ShadowsPass(renderer: self)
        */
    }

    func beginFrame(_ frameContextPtr: UnsafeRawPointer) {
        if imguiPass == nil {
            imguiPass = ImGuiPass(self)
        }

        frameContext.populateFromCore(ptr: frameContextPtr)
    }
    
    private func updateDepthStencilTexture(_ size: CGSize) {
        let width = Int(size.width)
        let height = Int(size.height)
        if let texture = depthStencilTexture, texture.width == width, texture.height == height {
            return
        }

        let stencilTexDescr = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: depthStencilPixelFormat, width: width, height: height, mipmapped: false)
        stencilTexDescr.usage = [.renderTarget]
        stencilTexDescr.storageMode = .private
        depthStencilTexture = device.makeTexture(descriptor: stencilTexDescr)!
    }

    // Returns whether the frame reached the screen. The engine loop paces itself
    // on that, so a dropped frame has to be reported as one.
    func endFrame() -> Bool {
        for scene in scenes {
            if (scene != nil) {
                scene!.onFrameUpdate()
            }
        }

        // Only ever called from the live path, so there is normally a layer
        // here. A nil one still has to be survivable: the AR screen can be taken
        // away between the engine deciding it is live and this frame reaching
        // the renderer.
        layerLock.lock()
        let layer = metalLayer
        layerLock.unlock()

        guard let layer = layer else { return false }

        // Cap how far the CPU may run ahead of the GPU. nextDrawable() gives
        // some backpressure on its own, but only on drawable availability - it
        // says nothing about whether the GPU has finished reading the buffers
        // this frame is about to overwrite. That mattered less when a display
        // link called us; the loop free-runs now.
        inFlightSemaphore.wait()

        guard let drawable = layer.nextDrawable() else {
            inFlightSemaphore.signal()
            Logger.warn("Renderer: no drawable available, frame dropped")
            return false
        }

        updateDepthStencilTexture(CGSize(width: drawable.texture.width, height: drawable.texture.height))

        let commandBuffer = commandQueue.makeCommandBuffer()!

        // Captures the semaphore rather than self, and is attached before any
        // encoding: from here to commit() there is no path out that would strand
        // the permit.
        let semaphore = inFlightSemaphore
        commandBuffer.addCompletedHandler { _ in semaphore.signal() }

        // Claimed here, before commit, because handlers cannot be attached after
        // it. addPresentedHandler is the moment this drawable replaces whatever
        // the layer was showing - which is exactly when the stale frame stops
        // being visible and the cover can come off.
        layerLock.lock()
        let firstPresent = firstPresentHandler
        firstPresentHandler = nil
        layerLock.unlock()

        if let firstPresent = firstPresent {
            drawable.addPresentedHandler { _ in
                DispatchQueue.main.async(execute: firstPresent)
            }
        }

        // Before any pass: the people matte is generated into this command buffer.
        updateDepthOcclusion(commandBuffer)

        imguiPass.renderFrame(commandBuffer, nil, frameContext, self)

        shadowMapPass.renderFrame(commandBuffer, frameContext, self)

        let passDescriptor = MTLRenderPassDescriptor()
        passDescriptor.colorAttachments[0].texture = drawable.texture
        passDescriptor.colorAttachments[0].storeAction = .store
        passDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)
        passDescriptor.colorAttachments[0].loadAction = .clear

        // A capture splits this encoder after the 3D passes (captureFrame) and
        // the debug pass goes on in another, which loads the depth: kept then.
        let capturing = Renderer_capturing()
        passDescriptor.depthAttachment.texture = depthStencilTexture
        passDescriptor.depthAttachment.loadAction = .clear
        passDescriptor.depthAttachment.storeAction = capturing ? .store : .dontCare
        passDescriptor.depthAttachment.clearDepth = 1.0
        
        passDescriptor.stencilAttachment.texture = depthStencilTexture
        passDescriptor.stencilAttachment.loadAction = .clear
        passDescriptor.stencilAttachment.storeAction = capturing ? .store : .dontCare
        passDescriptor.stencilAttachment.clearStencil = 0
        
        var commandEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor)!
        commandEncoder.setFrontFacing(.counterClockwise)

        backgroundPass.renderFrame(commandEncoder, frameContext, self)

        commandEncoder.setCullMode(.back)
        commandEncoder.setDepthStencilState(depthStencilState)
        
        occlusionPass.renderFrame(commandEncoder, frameContext, self)
        defaultPass.renderFrame(commandEncoder, frameContext, self)
        shadowsPass.renderFrame(commandEncoder, frameContext, self)

        // The frame as a photo or a video takes it: the content, before the
        // debug lines and the HUD go on.
        if capturing {
            commandEncoder.endEncoding()
            commandEncoder = captureFrame(commandBuffer, drawable.texture)
        } else if captureTexture != nil {
            captureTexture = nil
            photoBuffer = nil
        }

        debugPass.renderFrame(commandEncoder, frameContext, self)
        imguiPass.renderFrame(nil, commandEncoder, frameContext, self)

        commandEncoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()

        // Presenting is what paces the engine loop: once the layer's drawable
        // pool is empty, nextDrawable() above blocks until the display has
        // finished with one. Also what waitForGpuIdle() waits on.
        layerLock.lock()
        lastDrawable = drawable
        lastCommandBuffer = commandBuffer
        layerLock.unlock()

        return true
    }

    // The capture point. The render encoder has ended; the drawable is copied
    // into the capture texture, the capture overlays are drawn into the copy,
    // the recorder takes it and a photo request is answered from it once the
    // GPU is done. Returns the encoder the on-screen passes go on with, on the
    // drawable with its contents kept.
    private func captureFrame(_ commandBuffer: MTLCommandBuffer, _ drawableTexture: MTLTexture) -> MTLRenderCommandEncoder {
        let width = drawableTexture.width
        let height = drawableTexture.height
        if captureTexture == nil || captureTexture!.width != width || captureTexture!.height != height {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: drawableTexture.pixelFormat, width: width, height: height, mipmapped: false)
            descriptor.usage = [.shaderRead, .renderTarget]
            descriptor.storageMode = .private
            captureTexture = device.makeTexture(descriptor: descriptor)
            photoBuffer = nil
            Logger.info("Renderer: capture target \(width)x\(height)")
        }
        guard let capture = captureTexture else {
            // No capture target: the on-screen passes carry on and a photo gets nothing.
            if Renderer_photoRequested() {
                Renderer_photoCaptured(nil, 0, 0)
            }
            return makeOverlayEncoder(commandBuffer, drawableTexture)
        }

        let blit = commandBuffer.makeBlitCommandEncoder()!
        blit.copy(from: drawableTexture, to: capture)
        blit.endEncoding()

        // The capture overlays, into the capture alone.
        let overlayEncoder = makeOverlayEncoder(commandBuffer, capture)
        imguiPass.renderFrame(nil, overlayEncoder, frameContext, self, capture: true)
        overlayEncoder.endEncoding()

        if VideoRecorder.shared.isRecording {
            VideoRecorder.shared.encode(capture, commandBuffer: commandBuffer)
        }

        if Renderer_photoRequested() {
            let bytesPerRow = width * 4
            let length = bytesPerRow * height
            if photoBuffer == nil || photoBuffer!.length != length {
                photoBuffer = device.makeBuffer(length: length, options: .storageModeShared)
            }
            if let buffer = photoBuffer {
                let copy = commandBuffer.makeBlitCommandEncoder()!
                copy.copy(from: capture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                          sourceSize: MTLSize(width: width, height: height, depth: 1),
                          to: buffer, destinationOffset: 0, destinationBytesPerRow: bytesPerRow, destinationBytesPerImage: length)
                copy.endEncoding()
                commandBuffer.addCompletedHandler { _ in
                    // RGBA, the top row first, as Metal keeps it; copied by the engine at once.
                    Renderer_photoCaptured(buffer.contents(), width, height)
                }
            } else {
                Renderer_photoCaptured(nil, 0, 0)
            }
        }

        return makeOverlayEncoder(commandBuffer, drawableTexture)
    }

    // MARK: - Depth occlusion

    // What this frame's draws are occluded by: LiDAR's scene depth when the
    // frames carry it, else the people matte and its depth, else nothing.
    private func updateDepthOcclusion(_ commandBuffer: MTLCommandBuffer) {
        depthOcclusion.active = false
        depthOcclusion.map = noDepthTexture
        depthOcclusion.matte = fullMatteTexture

        // Off at once when the setting goes off, before ARKit's frames stop carrying depth.
        guard DeviceAR_depthWanted(), let frame = DeviceAR.instance.currentFrame() else {
            logDepthSource("none")
            return
        }

        let source: String
        if let depthMap = (frame.smoothedSceneDepth ?? frame.sceneDepth)?.depthMap,
           let texture = makeTexture(depthMap, .r32Float, commandBuffer) {
            depthOcclusion.map = texture
            source = "scene depth \(texture.width)x\(texture.height)"
        } else if frame.segmentationBuffer != nil && frame.estimatedDepthData != nil {
            if matteGenerator == nil {
                matteGenerator = ARMatteGenerator(device: device, matteResolution: .half)
            }
            depthOcclusion.matte = matteGenerator!.generateMatte(from: frame, commandBuffer: commandBuffer)
            depthOcclusion.map = matteGenerator!.generateDilatedDepth(from: frame, commandBuffer: commandBuffer)
            source = "people \(depthOcclusion.map.width)x\(depthOcclusion.map.height)"
        } else {
            // Wanted, and the session has not taken the depth semantics yet.
            logDepthSource("none yet")
            return
        }

        depthOcclusion.active = true
        depthOcclusion.aspectRatio = Float(depthOcclusion.map.width) / Float(max(depthOcclusion.map.height, 1))
        depthOcclusion.uvTransform = depthUVTransform(frame)
        logDepthSource(source)
    }

    // Screen NDC -> the view's normalized coordinates, origin top left as the
    // background pass's quad has them -> the camera image's, which ARKit lays its
    // depth and matte out in: the inverse of the frame's display transform, as
    // the background pass maps the camera image.
    private func depthUVTransform(_ frame: ARFrame) -> matrix_float3x3 {
        let t = frame.displayTransform(for: Context.inst().getInterfaceOrientation(), viewportSize: viewportSize).inverted()
        let viewToImage = matrix_float3x3(columns: (SIMD3<Float>(Float(t.a), Float(t.b), 0),
                                                   SIMD3<Float>(Float(t.c), Float(t.d), 0),
                                                   SIMD3<Float>(Float(t.tx), Float(t.ty), 1)))
        let ndcToView = matrix_float3x3(columns: (SIMD3<Float>(0.5, 0, 0),
                                                 SIMD3<Float>(0, -0.5, 0),
                                                 SIMD3<Float>(0.5, 0.5, 1)))
        return viewToImage * ndcToView
    }

    // A texture over the pixel buffer's own memory. The CVMetalTexture is what
    // holds that memory, so it is kept until the GPU is done with this frame.
    private func makeTexture(_ pixelBuffer: CVPixelBuffer, _ format: MTLPixelFormat, _ commandBuffer: MTLCommandBuffer) -> MTLTexture? {
        guard let cache = depthTextureCache else { return nil }
        var cvTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(nil, cache, pixelBuffer, nil, format,
                                                               CVPixelBufferGetWidth(pixelBuffer),
                                                               CVPixelBufferGetHeight(pixelBuffer),
                                                               0, &cvTexture)
        guard status == kCVReturnSuccess, let cvTexture = cvTexture,
              let texture = CVMetalTextureGetTexture(cvTexture) else {
            return nil
        }
        commandBuffer.addCompletedHandler { _ in withExtendedLifetime(cvTexture) {} }
        return texture
    }

    private func makeTexel<T>(_ format: MTLPixelFormat, _ value: T) -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: 1, height: 1, mipmapped: false)
        descriptor.usage = [.shaderRead]
        let texture = device.makeTexture(descriptor: descriptor)!
        var texel = value
        texture.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: &texel,
                        bytesPerRow: MemoryLayout<T>.size)
        return texture
    }

    private func logDepthSource(_ source: String) {
        if source != depthSourceLogged {
            depthSourceLogged = source
            Logger.info("Renderer: depth occlusion - \(source)")
        }
    }

    // A render encoder on `texture` keeping what it holds, with the depth
    // attachment the UI pipeline states were made against.
    private func makeOverlayEncoder(_ commandBuffer: MTLCommandBuffer, _ texture: MTLTexture) -> MTLRenderCommandEncoder {
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = texture
        descriptor.colorAttachments[0].loadAction = .load
        descriptor.colorAttachments[0].storeAction = .store
        descriptor.depthAttachment.texture = depthStencilTexture
        descriptor.depthAttachment.loadAction = .load
        descriptor.depthAttachment.storeAction = .dontCare
        descriptor.stencilAttachment.texture = depthStencilTexture
        descriptor.stencilAttachment.loadAction = .load
        descriptor.stencilAttachment.storeAction = .dontCare
        let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)!
        encoder.setFrontFacing(.counterClockwise)
        return encoder
    }

    func getFrameImageData(_ width: Int, _ height: Int, _ outPtr: UnsafeMutableRawPointer) {
        layerLock.lock()
        let drawable = lastDrawable
        layerLock.unlock()

        guard let drawable = drawable else {
            return
        }

        let texture = drawable.texture
        if texture.width != width || texture.height != height {
            Logger.error("getFrameImageData: invalid texture size \(texture.width)x\(texture.height), expected \(width)x\(height)")
        }
        
        let width = texture.width
        let height = texture.height
        
        let bytesPerPixel = 4 // RGBA
        let bytesPerRow = width * bytesPerPixel
        
        let region = MTLRegionMake2D(0, 0, width, height)
        texture.getBytes(outPtr, bytesPerRow: bytesPerRow, from: region, mipmapLevel: 0)
    }
    
    func render(_ renderable: Renderable) {
        occlusionPass.enqueue(renderable)
        defaultPass.enqueue(renderable)
        if Settings_displayShadows() {
            shadowMapPass.enqueue(renderable)
            shadowsPass.enqueue(renderable)
        }
    }
    
    func createScene(_ ptr: UnsafeRawPointer) -> Int {
        // ShadowMapPass iterates through all scenes.
        // So we reuse free slots of deleted scenes.
        
        var availableIdx = -1
        for i in 0 ..< scenes.count {
            if (scenes[i] == nil && availableIdx == -1) {
                availableIdx = i
            }
            if(scenes[i] != nil && scenes[i]!.coreId() == Scene_id(ptr)) {
                return i
            }
        }

        if (availableIdx == -1) {
            availableIdx = scenes.count
        }
        
        let scene = Scene(availableIdx, self, ptr)
        
        if (availableIdx < scenes.count) {
            scenes[availableIdx] = scene
        } else {
            scenes.append(scene)
            if (availableIdx != scenes.count - 1) {
                fatalError("Bad available scene index")
            }
        }
        
        shadowMapPass.resizeScenesQueue(scenes.count)
        
        return availableIdx
    }
    
    func deleteScene(_ id: Int) {
        scenes[Int(id)] = nil
    }

    func shadowMapTexture() -> MTLTexture {
        return shadowMapPass.shadowMapTexture
    }

    func getLibrary() -> MTLLibrary {
        do {
            return try device.makeDefaultLibrary(bundle: Bundle.module)
        } catch {
            fatalError("Failed to create default MTLLibrary: \(error)")
        }
    }
}
