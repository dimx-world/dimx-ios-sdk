import Foundation
import Metal
import ARKit
import DimxNative

// The engine's debug lists (RenderLines) over the scene: lines and polygons; the dots a point
// cloud is drawn with - one vertex each, a point of RenderLines::dotSize pixels (the scan
// editor's map over the camera); and the textured quads a picture is - a keyframe's, where its
// camera stood - read against the scene's depth and never written. Each list's buffer is as
// large as the render config's `debug` block says (Renderer_debugCapacity), made at the first
// frame that draws into it, and a list past it is cut there. The buffers come in sets, one per
// frame the renderer lets the GPU have in flight (Renderer.maxFramesInFlight), taken in turn: a
// frame fills the set the frame that many before it used, which the renderer has waited for,
// and never one the GPU may still be reading.
//
// And the geometry the engine holds across frames (RenderLines::setSurface, addCloud - the
// scans' dense surface and cloud, the map's landmarks, the ones the latest fix matched): a
// buffer per piece, kept by the piece's id and uploaded once - a piece changed is another id
// and another buffer - and dropped when no frame names it any more, Metal keeping a buffer
// alive while a command buffer in flight still reads it. Drawn first with the depth written,
// so a surface hides the landmarks behind it, and the lists over what stands.
class DebugPass
{
    static let componentsPerVertex = 7 // xyz + rgba
    static let vertexSize = MemoryLayout<Float>.stride * componentsPerVertex
    static let matrixSize = MemoryLayout<Float>.stride * 16
    static let quadVertexSize = MemoryLayout<Float>.stride * 5 // xyz + uv
    static let maxQuads = 64

    // One list's buffer, made when the list first has something in it.
    final class ListBuffer {
        var buffer: MTLBuffer?
        var capacity = 0
    }

    // A frame's buffers: every list's, and the pictures'.
    final class FrameBuffers {
        var lines = ListBuffer()
        var polys = ListBuffer()
        var dots = ListBuffer()
        var debugLines = ListBuffer()
        var debugPolys = ListBuffer()
        var debugDots = ListBuffer()
        var quads: MTLBuffer?
    }

    var frames: [FrameBuffers] = []
    var frameIndex = 0

    // A held piece's buffer, by its id.
    final class HeldBuffer {
        let buffer: MTLBuffer
        let count: Int
        init(_ buffer: MTLBuffer, _ count: Int) { self.buffer = buffer; self.count = count }
    }
    var held: [Int: HeldBuffer] = [:]

    var pipelineState: MTLRenderPipelineState!
    var pointPipelineState: MTLRenderPipelineState!
    var heldPipelineState: MTLRenderPipelineState!
    var heldPointPipelineState: MTLRenderPipelineState!
    var quadPipelineState: MTLRenderPipelineState!
    var quadDepthState: MTLDepthStencilState!
    var quadSampler: MTLSamplerState!

    init(_ renderer: Renderer) {
        for _ in 0..<Renderer.maxFramesInFlight {
            let set = FrameBuffers()
            set.quads = renderer.device.makeBuffer(length: DebugPass.maxQuads * 4 * DebugPass.quadVertexSize, options: [])
            frames.append(set)
        }

        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float3
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        vertexDescriptor.attributes[1].format = .float4
        vertexDescriptor.attributes[1].offset = 12 // offset after xyz
        vertexDescriptor.attributes[1].bufferIndex = 0
        vertexDescriptor.layouts[0].stride = DebugPass.vertexSize
        vertexDescriptor.layouts[0].stepRate = 1
        vertexDescriptor.layouts[0].stepFunction = .perVertex

        let defaultLibrary = renderer.getLibrary()
        let pipelineStateDescriptor = MTLRenderPipelineDescriptor()
        pipelineStateDescriptor.label = "DebugPipeline"
        //pipelineStateDescriptor.sampleCount = renderer.sampleCount
        pipelineStateDescriptor.vertexFunction = defaultLibrary.makeFunction(name: "debug_vertex")!
        pipelineStateDescriptor.fragmentFunction = defaultLibrary.makeFunction(name: "debug_fragment")!
        pipelineStateDescriptor.vertexDescriptor = vertexDescriptor
        pipelineStateDescriptor.colorAttachments[0].pixelFormat = renderer.colorPixelFormat
        pipelineStateDescriptor.colorAttachments[0].isBlendingEnabled = true
        pipelineStateDescriptor.colorAttachments[0].rgbBlendOperation = MTLBlendOperation.add
        pipelineStateDescriptor.colorAttachments[0].alphaBlendOperation = MTLBlendOperation.add
        pipelineStateDescriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactor.sourceAlpha
        pipelineStateDescriptor.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactor.sourceAlpha
        pipelineStateDescriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactor.oneMinusSourceAlpha
        pipelineStateDescriptor.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactor.oneMinusSourceAlpha
        pipelineStateDescriptor.depthAttachmentPixelFormat = renderer.depthStencilPixelFormat
        pipelineStateDescriptor.stencilAttachmentPixelFormat = renderer.depthStencilPixelFormat
        do { try pipelineState = renderer.device.makeRenderPipelineState(descriptor: pipelineStateDescriptor) }
        catch let error { Logger.error("Failed to create debug lines pipeline state, error \(error)") }

        // The dots: the same vertices, each a point the vertex stage sizes.
        pipelineStateDescriptor.label = "DebugPointsPipeline"
        pipelineStateDescriptor.vertexFunction = defaultLibrary.makeFunction(name: "debug_point_vertex")!
        do { try pointPipelineState = renderer.device.makeRenderPipelineState(descriptor: pipelineStateDescriptor) }
        catch let error { Logger.error("Failed to create debug points pipeline state, error \(error)") }

        // The held geometry: the same vertices in the piece's own frame, at its opacity - a
        // surface's triangles, a cloud's points.
        pipelineStateDescriptor.label = "DebugHeldPipeline"
        pipelineStateDescriptor.vertexFunction = defaultLibrary.makeFunction(name: "debug_held_vertex")!
        do { try heldPipelineState = renderer.device.makeRenderPipelineState(descriptor: pipelineStateDescriptor) }
        catch let error { Logger.error("Failed to create debug held pipeline state, error \(error)") }
        pipelineStateDescriptor.label = "DebugHeldPointsPipeline"
        pipelineStateDescriptor.vertexFunction = defaultLibrary.makeFunction(name: "debug_held_point_vertex")!
        do { try heldPointPipelineState = renderer.device.makeRenderPipelineState(descriptor: pipelineStateDescriptor) }
        catch let error { Logger.error("Failed to create debug held points pipeline state, error \(error)") }

        // The pictures: a position and a texture coordinate a vertex, premultiplied out as every
        // shader is - the blend is ONE / ONE_MINUS_SRC_ALPHA, as the GL pass's.
        let quadDescriptor = MTLVertexDescriptor()
        quadDescriptor.attributes[0].format = .float3
        quadDescriptor.attributes[0].offset = 0
        quadDescriptor.attributes[0].bufferIndex = 0
        quadDescriptor.attributes[1].format = .float2
        quadDescriptor.attributes[1].offset = 12
        quadDescriptor.attributes[1].bufferIndex = 0
        quadDescriptor.layouts[0].stride = DebugPass.quadVertexSize
        quadDescriptor.layouts[0].stepRate = 1
        quadDescriptor.layouts[0].stepFunction = .perVertex
        let quadPipeline = MTLRenderPipelineDescriptor()
        quadPipeline.label = "DebugQuadsPipeline"
        quadPipeline.vertexFunction = defaultLibrary.makeFunction(name: "debug_quad_vertex")!
        quadPipeline.fragmentFunction = defaultLibrary.makeFunction(name: "debug_quad_fragment")!
        quadPipeline.vertexDescriptor = quadDescriptor
        quadPipeline.colorAttachments[0].pixelFormat = renderer.colorPixelFormat
        quadPipeline.colorAttachments[0].isBlendingEnabled = true
        quadPipeline.colorAttachments[0].rgbBlendOperation = .add
        quadPipeline.colorAttachments[0].alphaBlendOperation = .add
        quadPipeline.colorAttachments[0].sourceRGBBlendFactor = .one
        quadPipeline.colorAttachments[0].sourceAlphaBlendFactor = .one
        quadPipeline.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        quadPipeline.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        quadPipeline.depthAttachmentPixelFormat = renderer.depthStencilPixelFormat
        quadPipeline.stencilAttachmentPixelFormat = renderer.depthStencilPixelFormat
        do { try quadPipelineState = renderer.device.makeRenderPipelineState(descriptor: quadPipeline) }
        catch let error { Logger.error("Failed to create debug quads pipeline state, error \(error)") }

        let depth = MTLDepthStencilDescriptor()
        depth.depthCompareFunction = .lessEqual
        depth.isDepthWriteEnabled = false
        quadDepthState = renderer.device.makeDepthStencilState(descriptor: depth)

        let sampler = MTLSamplerDescriptor()
        sampler.minFilter = .linear
        sampler.magFilter = .linear
        sampler.mipFilter = .linear
        sampler.sAddressMode = .clampToEdge
        sampler.tAddressMode = .clampToEdge
        quadSampler = renderer.device.makeSamplerState(descriptor: sampler)
    }

    // The list's vertices copied into its buffer - made, or made larger, to the list's
    // capacity first - and how many there are to draw.
    private func fill(_ list: ListBuffer, _ data: UnsafeRawPointer?, _ count: Int, _ capacity: Int, _ renderer: Renderer) -> Int {
        guard count > 0, let data = data else {
            return 0
        }
        if list.buffer == nil || list.capacity < capacity {
            list.capacity = max(capacity, 1)
            list.buffer = renderer.device.makeBuffer(length: list.capacity * DebugPass.vertexSize, options: [])
        }
        let n = min(count, list.capacity)
        list.buffer!.contents().copyMemory(from: data, byteCount: DebugPass.vertexSize * n)
        return n
    }

    // A held piece's buffer: the one kept under its id, else made from its vertices now.
    private func heldBuffer(_ id: Int, _ data: UnsafeRawPointer, _ count: Int, _ renderer: Renderer, _ seen: inout Set<Int>) -> HeldBuffer? {
        seen.insert(id)
        if let have = held[id] {
            return have
        }
        guard count > 0, let buffer = renderer.device.makeBuffer(bytes: data, length: count * DebugPass.vertexSize, options: []) else {
            return nil
        }
        let piece = HeldBuffer(buffer, count)
        held[id] = piece
        return piece
    }

    // The frame's view-projection times where a piece stands.
    private func pieceMvp(_ frameContext: FrameContext, _ transform: [Float]) -> matrix_float4x4 {
        let model = matrix_float4x4(columns: (SIMD4<Float>(transform[0], transform[1], transform[2], transform[3]),
                                              SIMD4<Float>(transform[4], transform[5], transform[6], transform[7]),
                                              SIMD4<Float>(transform[8], transform[9], transform[10], transform[11]),
                                              SIMD4<Float>(transform[12], transform[13], transform[14], transform[15])))
        return frameContext.viewProjectionMat * model
    }

    // The held geometry: the surface, then the clouds, each drawn from the buffer kept under its
    // id; what no frame names any more goes.
    private func renderHeld(_ encoder: MTLRenderCommandEncoder, _ frameContext: FrameContext, _ renderer: Renderer) -> Bool {
        var seen = Set<Int>()
        var data: UnsafeRawPointer? = nil
        var count = 0
        var id = 0
        var transform = [Float](repeating: 0, count: 16)
        var opacity: Float = 1
        var pointPixels: Float = 1
        var drew = false
        if Renderer_heldSurface(&data, &count, &id, &transform, &opacity), let bytes = data,
           let piece = heldBuffer(id, bytes, count, renderer, &seen) {
            encoder.setRenderPipelineState(heldPipelineState)
            var mvp = pieceMvp(frameContext, transform)
            encoder.setVertexBytes(&mvp, length: DebugPass.matrixSize, index: 1)
            encoder.setVertexBytes(&opacity, length: MemoryLayout<Float>.stride, index: 2)
            encoder.setVertexBuffer(piece.buffer, offset: 0, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: piece.count)
            drew = true
        }
        let clouds = Renderer_heldCloudsCount()
        if clouds > 0 {
            encoder.setRenderPipelineState(heldPointPipelineState)
            for i in 0..<clouds {
                data = nil
                guard Renderer_heldCloud(i, &data, &count, &id, &transform, &pointPixels, &opacity), let bytes = data,
                      let piece = heldBuffer(id, bytes, count, renderer, &seen) else {
                    continue
                }
                var mvp = pieceMvp(frameContext, transform)
                encoder.setVertexBytes(&mvp, length: DebugPass.matrixSize, index: 1)
                encoder.setVertexBytes(&opacity, length: MemoryLayout<Float>.stride, index: 2)
                encoder.setVertexBytes(&pointPixels, length: MemoryLayout<Float>.stride, index: 3)
                encoder.setVertexBuffer(piece.buffer, offset: 0, index: 0)
                encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: piece.count)
                drew = true
            }
        }
        if held.count != seen.count {
            held = held.filter { seen.contains($0.key) }
        }
        return drew
    }

    func renderFrame(_ encoder: MTLRenderCommandEncoder, _ frameContext: FrameContext, _ renderer: Renderer) {
        // This frame's set of buffers - the GPU may still be reading the others.
        let set = frames[frameIndex]
        frameIndex = (frameIndex + 1) % frames.count
        let lines = set.lines, polys = set.polys, dots = set.dots
        let debugLines = set.debugLines, debugPolys = set.debugPolys, debugDots = set.debugDots
        let lineCapacity = Int(Renderer_debugCapacity(0))
        let polyCapacity = Int(Renderer_debugCapacity(1))
        let dotCapacity = Int(Renderer_debugCapacity(2))
        let linesCount = fill(lines, Renderer_linesVertsData(false), Renderer_linesVertsCount(false), lineCapacity, renderer)
        let polysCount = fill(polys, Renderer_linesPolyVertsData(false), Renderer_linesPolyVertsCount(false), polyCapacity, renderer)
        let dotsCount = fill(dots, Renderer_dotsData(false), Renderer_dotsCount(false), dotCapacity, renderer)
        let debugLinesCount = fill(debugLines, Renderer_linesVertsData(true), Renderer_linesVertsCount(true), lineCapacity, renderer)
        let debugPolysCount = fill(debugPolys, Renderer_linesPolyVertsData(true), Renderer_linesPolyVertsCount(true), polyCapacity, renderer)
        let debugDotsCount = fill(debugDots, Renderer_dotsData(true), Renderer_dotsCount(true), dotCapacity, renderer)
        let quadsCount = Renderer_quadsCount(false)

        // The held pieces first, the depth written (the renderer's own state): a surface hides
        // what is behind it, the lists are drawn over what stands.
        encoder.setCullMode(.none)
        let heldDrawn = renderHeld(encoder, frameContext, renderer)

        if linesCount == 0 && polysCount == 0 && dotsCount == 0 && debugLinesCount == 0 && debugPolysCount == 0
            && debugDotsCount == 0 && quadsCount == 0 {
            if heldDrawn {
                encoder.setRenderPipelineState(pipelineState)
            }
            return
        }

        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBytes(&frameContext.viewProjectionMat, length: DebugPass.matrixSize, index: 1)

        if linesCount > 0 {
            encoder.setVertexBuffer(lines.buffer, offset: 0, index: 0)
            encoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: linesCount)
        }
        if polysCount > 0 {
            encoder.setVertexBuffer(polys.buffer, offset: 0, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: polysCount)
        }
        if debugLinesCount > 0 {
            encoder.setVertexBuffer(debugLines.buffer, offset: 0, index: 0)
            encoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: debugLinesCount)
        }
        if debugPolysCount > 0 {
            encoder.setVertexBuffer(debugPolys.buffer, offset: 0, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: debugPolysCount)
        }

        if dotsCount > 0 || debugDotsCount > 0 {
            encoder.setRenderPipelineState(pointPipelineState)
            encoder.setVertexBytes(&frameContext.viewProjectionMat, length: DebugPass.matrixSize, index: 1)
            if dotsCount > 0 {
                var size = Renderer_dotSize(false)
                encoder.setVertexBytes(&size, length: MemoryLayout<Float>.stride, index: 2)
                encoder.setVertexBuffer(dots.buffer, offset: 0, index: 0)
                encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: dotsCount)
            }
            if debugDotsCount > 0 {
                var size = Renderer_dotSize(true)
                encoder.setVertexBytes(&size, length: MemoryLayout<Float>.stride, index: 2)
                encoder.setVertexBuffer(debugDots.buffer, offset: 0, index: 0)
                encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: debugDotsCount)
            }
        }

        if quadsCount > 0, let quadBuffer = set.quads {
            renderQuads(encoder, frameContext, renderer, quadBuffer, Int(quadsCount))
        }
    }

    // The pictures, each two triangles from its four corners - top left, top right, bottom
    // right, bottom left - its texture's rows bottom-up as the engine keeps them, so the
    // picture's top is at the texture coordinates' larger v.
    private func renderQuads(_ encoder: MTLRenderCommandEncoder, _ frameContext: FrameContext, _ renderer: Renderer,
                             _ quadBuffer: MTLBuffer, _ count: Int) {
        encoder.setRenderPipelineState(quadPipelineState)
        encoder.setDepthStencilState(quadDepthState)
        encoder.setVertexBytes(&frameContext.viewProjectionMat, length: DebugPass.matrixSize, index: 1)
        encoder.setFragmentSamplerState(quadSampler, index: 0)
        var corners = [Float](repeating: 0, count: 12)
        var uv = [Float](repeating: 0, count: 4)
        var alpha: Float = 1
        var premultiplied = false
        var textureId: Int = 0
        let floatsPerQuad = 4 * 5
        let base = quadBuffer.contents().bindMemory(to: Float.self, capacity: DebugPass.maxQuads * floatsPerQuad)
        var slot = 0
        for i in 0..<min(count, DebugPass.maxQuads) {
            if !Renderer_quad(false, i, &corners, &uv, &alpha, &premultiplied, &textureId) {
                continue
            }
            guard textureId >= 0, textureId < renderer.textures.count,
                  let texture = renderer.textures[textureId], let mtlTexture = texture.mTexture else {
                continue
            }
            // The corners in strip order: top left, bottom left, top right, bottom right.
            let order = [0, 3, 1, 2]
            let uvs: [(Float, Float)] = [(uv[0], uv[3]), (uv[0], uv[1]), (uv[2], uv[3]), (uv[2], uv[1])]
            let out = base + slot * floatsPerQuad
            for v in 0..<4 {
                let c = order[v]
                out[v * 5 + 0] = corners[c * 3 + 0]
                out[v * 5 + 1] = corners[c * 3 + 1]
                out[v * 5 + 2] = corners[c * 3 + 2]
                out[v * 5 + 3] = uvs[v].0
                out[v * 5 + 4] = uvs[v].1
            }
            encoder.setVertexBuffer(quadBuffer, offset: slot * floatsPerQuad * MemoryLayout<Float>.stride, index: 0)
            encoder.setFragmentTexture(mtlTexture, index: 0)
            var params = SIMD2<Float>(alpha, premultiplied ? 1 : 0)
            encoder.setFragmentBytes(&params, length: MemoryLayout<SIMD2<Float>>.stride, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            slot += 1
        }
        encoder.setDepthStencilState(renderer.depthStencilState)
    }

    func drawLine(_ p1: simd_float3, _ p2: simd_float3, _ color: simd_float4)
    {
        var tmpP1 = p1;
        var tmpP2 = p2;
        var tmpCol = color;
        Renderer_drawLine(true, &tmpP1, &tmpCol, &tmpP2, &tmpCol)
    }

    func drawTriangle(_ v1: simd_float3, _ v2: simd_float3, _ v3: simd_float3, _ color: simd_float4) {
        var tmpV1 = v1;
        var tmpV2 = v2;
        var tmpV3 = v3;
        var tmpCol = color;
        Renderer_drawTriangle(true, &tmpV1, &tmpV2, &tmpV3, &tmpCol)
    }

    func drawRect(_ width: Float, _ height: Float, _ transform: simd_float4x4, _ color: simd_float4) {
        var tmpTrans = transform;
        var tmpCol = color;
        Renderer_drawLineRect(true, width, height, &tmpTrans, &tmpCol)
    }

    func drawPlane(_ plane: ARPlaneGeometry, _ transform: simd_float4x4, _ color: simd_float4) {
        var verts = plane.vertices
        for i in 0..<verts.count {
            let v = transform * simd_float4(verts[i].x, verts[i].y, verts[i].z, 1)
            verts[i] = simd_float3(v.x, v.y, v.z)
        }
        let inds = plane.triangleIndices
        for i in 0 ..< plane.triangleCount {
            drawTriangle(verts[Int(inds[i * 3])], verts[Int(inds[i * 3 + 1])], verts[Int(inds[i * 3 + 2])], color)
        }
    }

    func drawPoint(_ pos: simd_float3, _ size: Float,_ color: simd_float4) {
        guard let camMat = DeviceAR.instance.frameInUse()?.camera.transform else {
            return
        }
        let s2 = size * 0.5

        let vert = {(x: Float, y: Float) -> simd_float3 in
            let t = camMat * simd_float4(x, y, 0, 0)
            return simd_float3(t.x, t.y, t.z) + pos
        }

        drawTriangle(vert(-s2,  s2), vert(-s2, -s2), vert(s2, s2), color)
        drawTriangle(vert(-s2, -s2), vert( s2, -s2), vert(s2, s2), color)
    }
}
