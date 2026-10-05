import Foundation
import Metal
import DimxNative

// One scene's ground shadow targets (GroundShadow): the casters' depth seen from
// below, and two darkness textures the blur goes back and forth between - the
// result in the first. Held by the scene, so a scene that goes takes them with
// it and a new one in its slot starts with none.
final class GroundShadowTarget
{
    let size: Int
    let depth: MTLTexture
    let darkness: [MTLTexture]
    // The shadow's revision the textures hold; none until they are first drawn.
    var drawnRevision: UInt64? = nil

    init?(_ device: MTLDevice, _ size: Int) {
        let depthDescr = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: GroundShadowPass.depthPixelFormat,
                                                                  width: size, height: size, mipmapped: false)
        depthDescr.usage = [.renderTarget, .shaderRead]
        depthDescr.storageMode = .private
        let darknessDescr = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r8Unorm,
                                                                     width: size, height: size, mipmapped: false)
        darknessDescr.usage = [.renderTarget, .shaderRead]
        darknessDescr.storageMode = .private
        guard let depth = device.makeTexture(descriptor: depthDescr),
              let darkness0 = device.makeTexture(descriptor: darknessDescr),
              let darkness1 = device.makeTexture(descriptor: darknessDescr) else {
            return nil
        }
        depth.label = "ground shadow casters"
        darkness0.label = "ground shadow"
        darkness1.label = "ground shadow blur"
        self.size = size
        self.depth = depth
        self.darkness = [darkness0, darkness1]
        Logger.info("GroundShadowPass: target \(size)x\(size)")
    }
}

// The grounding shadows (GroundShadow; the GL renderer's is GlGroundShadowPass).
// Each scene's casters are queued as they render; renderTargets() draws them from
// below into the scene's depth target with their own vertex stage - so skinning
// and morphs come out as they are drawn - and blurs that, for each scene whose
// shadow moved since its targets were last drawn; renderShadows() then lays each
// shadow on its ground in the frame, between the opaque meshes and the blended
// ones.
final class GroundShadowPass
{
    static let depthPixelFormat: MTLPixelFormat = .depth32Float

    // The casters, per scene.
    private var queue: [[Renderable]] = []

    private var blurDepthPipelineState: MTLRenderPipelineState!
    private var blurPipelineState: MTLRenderPipelineState!
    private var shadowPipelineState: MTLRenderPipelineState!
    private var casterDepthState: MTLDepthStencilState!
    private var shadowDepthState: MTLDepthStencilState!

    init(_ renderer: Renderer) {
        let library = renderer.getLibrary()

        let blurDescr = MTLRenderPipelineDescriptor()
        blurDescr.label = "GroundShadowBlurDepth"
        blurDescr.vertexFunction = library.makeFunction(name: "ground_shadow_blur_vertex")!
        blurDescr.fragmentFunction = library.makeFunction(name: "ground_shadow_blur_depth_fragment")!
        blurDescr.colorAttachments[0].pixelFormat = .r8Unorm
        do { blurDepthPipelineState = try renderer.device.makeRenderPipelineState(descriptor: blurDescr) }
        catch let error { Logger.error("Failed to create the ground shadow blur pipeline state, error \(error)") }

        blurDescr.label = "GroundShadowBlur"
        blurDescr.fragmentFunction = library.makeFunction(name: "ground_shadow_blur_fragment")!
        do { blurPipelineState = try renderer.device.makeRenderPipelineState(descriptor: blurDescr) }
        catch let error { Logger.error("Failed to create the ground shadow blur pipeline state, error \(error)") }

        // Premultiplied, as every shader writes: black at alpha a scales what is
        // behind by 1 - a.
        let shadowDescr = MTLRenderPipelineDescriptor()
        shadowDescr.label = "GroundShadow"
        shadowDescr.vertexFunction = library.makeFunction(name: "ground_shadow_vertex")!
        shadowDescr.fragmentFunction = library.makeFunction(name: "ground_shadow_fragment")!
        shadowDescr.colorAttachments[0].pixelFormat = renderer.colorPixelFormat
        shadowDescr.colorAttachments[0].isBlendingEnabled = true
        shadowDescr.colorAttachments[0].rgbBlendOperation = .add
        shadowDescr.colorAttachments[0].alphaBlendOperation = .add
        shadowDescr.colorAttachments[0].sourceRGBBlendFactor = .one
        shadowDescr.colorAttachments[0].sourceAlphaBlendFactor = .one
        shadowDescr.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        shadowDescr.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        shadowDescr.depthAttachmentPixelFormat = renderer.depthStencilPixelFormat
        shadowDescr.stencilAttachmentPixelFormat = renderer.depthStencilPixelFormat
        do { shadowPipelineState = try renderer.device.makeRenderPipelineState(descriptor: shadowDescr) }
        catch let error { Logger.error("Failed to create the ground shadow pipeline state, error \(error)") }

        let casterDescr = MTLDepthStencilDescriptor()
        casterDescr.depthCompareFunction = .less
        casterDescr.isDepthWriteEnabled = true
        casterDepthState = renderer.device.makeDepthStencilState(descriptor: casterDescr)

        // The frame's depth test, nothing written.
        let shadowDepthDescr = MTLDepthStencilDescriptor()
        shadowDepthDescr.depthCompareFunction = .lessEqual
        shadowDepthDescr.isDepthWriteEnabled = false
        shadowDepthState = renderer.device.makeDepthStencilState(descriptor: shadowDepthDescr)
    }

    func clearQueue() {
        for i in queue.indices {
            queue[i].removeAll()
        }
    }

    func enqueue(_ renderable: Renderable) {
        let sceneId = renderable.getScene().id
        if sceneId < queue.count {
            queue[sceneId].append(renderable)
        }
    }

    func resizeScenesQueue(_ count: Int) {
        while count > queue.count {
            queue.append([])
        }
    }

    // Before the frame's own passes, in encoders of their own.
    func renderTargets(_ commandBuffer: MTLCommandBuffer, _ frameContext: FrameContext, _ renderer: Renderer) {
        guard blurDepthPipelineState != nil && blurPipelineState != nil else {
            return
        }
        for i in 0 ..< queue.count {
            let casters = queue[i]
            if casters.isEmpty {
                continue
            }
            guard let scene = renderer.scenes[i] else {
                continue
            }
            let core = scene.coreScene
            if !Scene_groundShadowActive(core) {
                continue
            }

            let size = Scene_groundShadowTextureSize(core)
            if scene.groundShadowTarget?.size != size {
                scene.groundShadowTarget = GroundShadowTarget(renderer.device, size)
            }
            guard let target = scene.groundShadowTarget else {
                continue
            }
            let revision = UInt64(Scene_groundShadowRevision(core))
            if target.drawnRevision == revision {
                continue
            }

            drawCasters(commandBuffer, target, casters, Scene_groundShadowCasterViewProj(core), frameContext, renderer)
            // The kernel's taps stand a quarter of its reach apart.
            let step = Scene_groundShadowBlurTexels(core) * 0.25 / Float(size)
            drawBlur(commandBuffer, target.depth, target.darkness[1], SIMD2<Float>(step, 0), blurDepthPipelineState)
            drawBlur(commandBuffer, target.darkness[1], target.darkness[0], SIMD2<Float>(0, step), blurPipelineState)
            target.drawnRevision = revision
        }
    }

    private func drawCasters(_ commandBuffer: MTLCommandBuffer,
                             _ target: GroundShadowTarget,
                             _ casters: [Renderable],
                             _ viewProj: matrix_float4x4,
                             _ frameContext: FrameContext,
                             _ renderer: Renderer) {
        let passDescr = MTLRenderPassDescriptor()
        passDescr.depthAttachment.texture = target.depth
        passDescr.depthAttachment.loadAction = .clear
        passDescr.depthAttachment.clearDepth = 1.0   // nothing casts
        passDescr.depthAttachment.storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescr) else {
            return
        }
        encoder.label = "ground shadow casters"
        encoder.setDepthStencilState(casterDepthState)
        // Seen from below, a mesh shows the faces it turns away from the sky, and
        // a single-sided one - a leaf, a sign - none at all: both sides.
        encoder.setCullMode(.none)
        encoder.setFrontFacing(.counterClockwise)
        for renderable in casters {
            for mesh in renderable.meshes where mesh.material.castsGroundShadow {
                mesh.material.setupRender(renderer, encoder, mesh, frameContext, casterViewProj: viewProj)
                mesh.mesh.draw(encoder)
            }
        }
        encoder.endEncoding()
    }

    private func drawBlur(_ commandBuffer: MTLCommandBuffer,
                          _ source: MTLTexture,
                          _ destination: MTLTexture,
                          _ step: SIMD2<Float>,
                          _ pipelineState: MTLRenderPipelineState) {
        let passDescr = MTLRenderPassDescriptor()
        passDescr.colorAttachments[0].texture = destination
        passDescr.colorAttachments[0].loadAction = .dontCare   // every texel is written
        passDescr.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescr) else {
            return
        }
        encoder.label = "ground shadow blur"
        encoder.setRenderPipelineState(pipelineState)
        var uniforms = GroundShadowBlurUniforms(step: step)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<GroundShadowBlurUniforms>.stride, index: 0)
        encoder.setFragmentTexture(source, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }

    // In the frame's encoder, after the opaque meshes and before the blended ones.
    func renderShadows(_ encoder: MTLRenderCommandEncoder, _ frameContext: FrameContext, _ renderer: Renderer) {
        guard shadowPipelineState != nil else {
            return
        }
        var setUp = false
        for i in 0 ..< queue.count {
            // A scene whose casters did not render this frame is not on show.
            if queue[i].isEmpty {
                continue
            }
            guard let scene = renderer.scenes[i], let target = scene.groundShadowTarget else {
                continue
            }
            let core = scene.coreScene
            if !Scene_groundShadowActive(core) || target.drawnRevision != UInt64(Scene_groundShadowRevision(core)) {
                continue
            }

            let depth = renderer.depthOcclusion!
            if !setUp {
                encoder.pushDebugGroup("GroundShadows")
                encoder.setRenderPipelineState(shadowPipelineState)
                encoder.setDepthStencilState(shadowDepthState)
                encoder.setCullMode(.back)
                // Bound whether or not the shader reads them, as for the content.
                encoder.setFragmentTexture(depth.map, index: 1)
                encoder.setFragmentTexture(depth.matte, index: 2)
                setUp = true
            }

            var uniforms = GroundShadowUniforms()
            uniforms.viewProjMat = frameContext.viewProjectionMat
            uniforms.quadMat = Scene_groundShadowQuadTransform(core)
            uniforms.depthMapUVTransform = depth.uvTransform
            uniforms.opacity = Scene_groundShadowOpacity(core)
            uniforms.depthMapAspectRatio = depth.aspectRatio
            uniforms.useDepthOcclusion = depth.active
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<GroundShadowUniforms>.stride, index: 0)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<GroundShadowUniforms>.stride, index: 0)
            encoder.setFragmentTexture(target.darkness[0], index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }
        if setUp {
            encoder.popDebugGroup()
        }
    }
}
