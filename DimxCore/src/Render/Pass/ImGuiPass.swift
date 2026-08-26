import Foundation
import Metal
import DimxNative

class ImGuiPass
{
    var pipelineState2D: MTLRenderPipelineState!
    var pipelineState3D: MTLRenderPipelineState!

    // ImGui 1.92 manages its font atlas as dynamic textures (ImDrawData::Textures). We create one
    // MTLTexture per ImTextureData and stash it here, keyed by the id we write back into the
    // ImTextureData (ImTexture_setCreated). Draw calls reference it through ImGuiDrawCall.texData.
    private var imguiTextures: [UInt64: MTLTexture] = [:]
    private var nextImguiTexId: UInt64 = 1

    init(_ renderer: Renderer) {
        let vertDesc = MTLVertexDescriptor()
        vertDesc.attributes[0].offset = 0
        vertDesc.attributes[0].format = MTLVertexFormat.float2
        vertDesc.attributes[0].bufferIndex = 0
        vertDesc.attributes[1].offset = 4 * 2; // two floats for pos
        vertDesc.attributes[1].format = MTLVertexFormat.float2
        vertDesc.attributes[1].bufferIndex = 0
        vertDesc.attributes[2].offset = 4 * 4; // two floats for pos and two for uv
        vertDesc.attributes[2].format = MTLVertexFormat.uchar4
        vertDesc.attributes[2].bufferIndex = 0
        vertDesc.layouts[0].stepRate = 1
        vertDesc.layouts[0].stepFunction = MTLVertexStepFunction.perVertex
        vertDesc.layouts[0].stride = 2 * 4 + 2 * 4 + 4 // pos + uv + color
        //if vertDesc.layouts[0].stride != ImGui_vertexSize() {
        //    fatalError("Invalid vertex layout!")
        //}
        
        let defaultLibrary = renderer.getLibrary()
        let pipelineStateDescriptor = MTLRenderPipelineDescriptor()
        pipelineStateDescriptor.vertexFunction = defaultLibrary.makeFunction(name: "imgui_vertex")
        pipelineStateDescriptor.fragmentFunction = defaultLibrary.makeFunction(name: "imgui_fragment")
        pipelineStateDescriptor.vertexDescriptor = vertDesc
        pipelineStateDescriptor.colorAttachments[0].pixelFormat = renderer.colorPixelFormat
        pipelineStateDescriptor.colorAttachments[0].isBlendingEnabled = true
        pipelineStateDescriptor.colorAttachments[0].rgbBlendOperation = MTLBlendOperation.add
        pipelineStateDescriptor.colorAttachments[0].alphaBlendOperation = MTLBlendOperation.add
        // The shader writes premultiplied colour (ImGui.metal), so a UI render
        // target ends up holding premultiplied colour with a true alpha, which
        // is what the standard shader reads it as.
        pipelineStateDescriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactor.one
        pipelineStateDescriptor.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactor.one
        pipelineStateDescriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactor.oneMinusSourceAlpha
        pipelineStateDescriptor.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactor.oneMinusSourceAlpha
        pipelineStateDescriptor.depthAttachmentPixelFormat = renderer.depthStencilPixelFormat
        pipelineStateDescriptor.stencilAttachmentPixelFormat = renderer.depthStencilPixelFormat
        
        pipelineState2D = try! renderer.device.makeRenderPipelineState(descriptor: pipelineStateDescriptor)

        // for 3D UI
        pipelineStateDescriptor.colorAttachments[0].pixelFormat = .rgba8Unorm
        pipelineStateDescriptor.depthAttachmentPixelFormat = .invalid
        pipelineStateDescriptor.stencilAttachmentPixelFormat = .invalid
        pipelineState3D = try! renderer.device.makeRenderPipelineState(descriptor: pipelineStateDescriptor)
    }
    
    // Service the ImGui 1.92 dynamic font-atlas texture queue for a context before rendering it, so
    // every ImTextureData referenced by the draw calls has a live MTLTexture. Mirrors the GL backend
    // (GlImGuiPass::updateImGuiTexture). The atlas is RGBA32; we re-upload the whole image on updates.
    private func updateTextures(_ context: UnsafeRawPointer) {
        let count = ImGuiContext_numTextures(context)
        for i in 0 ..< count {
            guard let tex = ImGuiContext_texture(context, i) else { continue }

            if ImTexture_wantCreate(tex) != 0 {
                let width = Int(ImTexture_width(tex))
                let height = Int(ImTexture_height(tex))
                let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                    pixelFormat: .rgba8Unorm, width: width, height: height, mipmapped: false)
                descriptor.usage = .shaderRead
                let mtlTexture = Renderer.instance.device.makeTexture(descriptor: descriptor)!
                if let pixels = ImTexture_pixels(tex) {
                    mtlTexture.replace(region: MTLRegionMake2D(0, 0, width, height),
                                       mipmapLevel: 0, withBytes: pixels, bytesPerRow: 4 * width)
                }
                let id = nextImguiTexId
                nextImguiTexId += 1
                imguiTextures[id] = mtlTexture
                ImTexture_setCreated(tex, id)
            } else if ImTexture_wantUpdates(tex) != 0 {
                let id = ImTexture_texId(tex)
                if let mtlTexture = imguiTextures[id], let pixels = ImTexture_pixels(tex) {
                    let width = Int(ImTexture_width(tex))
                    let height = Int(ImTexture_height(tex))
                    mtlTexture.replace(region: MTLRegionMake2D(0, 0, width, height),
                                       mipmapLevel: 0, withBytes: pixels, bytesPerRow: 4 * width)
                }
                ImTexture_setUpdated(tex)
            } else if ImTexture_wantDestroy(tex) != 0 {
                imguiTextures[ImTexture_texId(tex)] = nil
                ImTexture_setDestroyed(tex)
            }
        }
    }

    func renderFrame(_ commandBuffer: MTLCommandBuffer?, _ defaultEncoder: MTLRenderCommandEncoder?, _ frameContext: FrameContext, _ renderer: Renderer) {
        for i in 0 ..< ImGui_numContexts() {
            let context: UnsafeRawPointer = ImGui_context(i)!
            if ImGuiContext_frameCounter(context) != frameContext.frameCounter {
                continue
            }

            var encoder: MTLRenderCommandEncoder! = nil
            let targetTexturePtr = ImGuiContext_renderTarget(context)
            if defaultEncoder != nil {
                if targetTexturePtr != nil {
                    continue
                }
                encoder = defaultEncoder!
                encoder.setRenderPipelineState(pipelineState2D)
            } else {
                if targetTexturePtr == nil {
                    continue
                }
                let targetTexture = Renderer.instance.textures[Texture_nativeId(targetTexturePtr!)]
                encoder = commandBuffer!.makeRenderCommandEncoder(descriptor: targetTexture!.mRenderPassDescriptor)
                encoder.setRenderPipelineState(pipelineState3D)
            }

            // Create/update the ImGui-managed atlas textures referenced by this context's draw calls.
            updateTextures(context)

            let mesh = renderer.meshes[Mesh_nativeId(ImGuiContext_mesh(context))]!
            let vertexSize = ImGuiContext_vertexSize(context)
            let indexSize = ImGuiContext_indexSize(context)
            
            encoder.setCullMode(.none)
            encoder.setVertexBuffer(mesh.vertexBuffer, offset: 0, index: 0)

            encoder.setVertexBytes(ImGuiContext_mvpMat(context), length: 4 * 16, index: 1)
            
            var totalNumVerts = 0
            var totalNumInds = 0
            
            var callVertOffset = 0
            var callIndOffset = 0
            
            var currentBufferId = -1
            for j in 0 ..< ImGuiContext_numDrawCalls(context) {
                let call: UnsafePointer<ImGuiDrawCall> = ImGuiContext_drawCall(context, j)
                
                if call.pointee.bufferId != currentBufferId {
                    let vertBufPtr = mesh.vertexBuffer.contents() + totalNumVerts * vertexSize
                    let indBufPtr = mesh.indexBuffer!.contents() + totalNumInds * indexSize
                    
                    vertBufPtr.copyMemory(from: call.pointee.vertexData,
                                          byteCount: call.pointee.numVertsInBuffer * vertexSize)
                    indBufPtr.copyMemory(from: call.pointee.indexData,
                                         byteCount: call.pointee.numIndsInBuffer * indexSize)
                    
                    callVertOffset = totalNumVerts
                    callIndOffset = totalNumInds
                    
                    totalNumVerts += call.pointee.numVertsInBuffer
                    totalNumInds += call.pointee.numIndsInBuffer
                    
                    currentBufferId = call.pointee.bufferId
                }

                // ImGui 1.92 can emit zero-element draw commands (e.g. texture-update/callback
                // commands carry no geometry). GL's glDrawElements no-ops on count 0, but Metal's
                // drawIndexedPrimitives asserts on indexCount == 0 — so skip them explicitly.
                if call.pointee.numIndsInCall == 0 {
                    continue
                }

                let texture: MTLTexture?
                var redChannel: Float
                var premultiplied: Float = 0.0
                if let texData = call.pointee.texData {
                    // ImGui-managed font atlas (RGBA32), serviced by updateTextures() above.
                    texture = imguiTextures[ImTexture_texId(texData)]
                    redChannel = 0.0
                } else {
                    // User texture (ImGui::Image): texId carries the native texture id directly
                    // (Renderer.textures index) since ImGui 1.92 — no Texture_nativeId indirection.
                    let userTexture = renderer.textures[Int(bitPattern: call.pointee.texId)]
                    texture = userTexture?.mTexture
                    // Single-channel (R8) user textures are sampled via the red channel as alpha.
                    redChannel = texture?.pixelFormat == MTLPixelFormat.r8Unorm ? 1.0 : 0.0
                    // Decoded images and render targets carry premultiplied colour; the
                    // shader multiplies the rest itself.
                    if let userTexture = userTexture, Texture_premultiplied(userTexture.mCoreTex) {
                        premultiplied = 1.0
                    }
                }
                var fragUniforms: [Float] = [redChannel, premultiplied]
                encoder.setFragmentBytes(&fragUniforms, length: 8, index: 1)
                encoder.setFragmentTexture(texture, index: 0)
                encoder.drawIndexedPrimitives(type: mesh.primitiveType,
                                              indexCount: call.pointee.numIndsInCall,
                                              indexType: mesh.indexType,
                                              indexBuffer: mesh.indexBuffer!,
                                              indexBufferOffset: (callIndOffset + call.pointee.indOffsetInCall) * indexSize,
                                              instanceCount: 1,
                                              baseVertex: callVertOffset,
                                              baseInstance: 0)
            }
            if defaultEncoder == nil {
                encoder.endEncoding()
            }
        }
    }
}
