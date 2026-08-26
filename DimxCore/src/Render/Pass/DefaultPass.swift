import Foundation
import Metal
import DimxNative

// The pass that draws the scene: the stencil writers, then the opaque meshes,
// then the blended ones back to front. Each mesh's material decides the state
// it is drawn with - depth write, cull mode, and (through its pipeline state)
// the blend - the same rules as the GL renderer's GlDefaultPass.
class DefaultPass
{
    var opaque: [RenderableMesh] = []
    var transparent: [RenderableMesh] = []
    var stencil: [RenderableMesh] = []

    var writeStencilState: MTLDepthStencilState?
    var readStencilState: MTLDepthStencilState?
    var readStencilNoDepthWriteState: MTLDepthStencilState?
    var noDepthWriteState: MTLDepthStencilState?

    // What the encoder was last given, so a run of meshes sharing a state
    // costs no state changes.
    private var currentDepthStencilState: MTLDepthStencilState?
    private var currentCullMode: MTLCullMode = .back

    init(_ renderer: Renderer) {
        let writeStencilDescr = MTLDepthStencilDescriptor()
        writeStencilDescr.frontFaceStencil = MTLStencilDescriptor()
        writeStencilDescr.isDepthWriteEnabled = false
        writeStencilDescr.frontFaceStencil.stencilCompareFunction = .always
        writeStencilDescr.frontFaceStencil.stencilFailureOperation = .keep
        writeStencilDescr.frontFaceStencil.depthFailureOperation = .keep
        writeStencilDescr.frontFaceStencil.depthStencilPassOperation = .replace
        writeStencilDescr.frontFaceStencil.readMask = 0xFF
        writeStencilDescr.frontFaceStencil.writeMask = 0xFF
        writeStencilState = Renderer.instance.device.makeDepthStencilState(descriptor: writeStencilDescr)!

        let readStencilDescr = MTLDepthStencilDescriptor()
        readStencilDescr.frontFaceStencil = MTLStencilDescriptor()
        readStencilDescr.frontFaceStencil.stencilCompareFunction = .equal
        readStencilDescr.frontFaceStencil.stencilFailureOperation = .keep
        readStencilDescr.frontFaceStencil.depthFailureOperation = .keep
        readStencilDescr.frontFaceStencil.depthStencilPassOperation = .keep
        readStencilDescr.frontFaceStencil.readMask = 0xFF
        readStencilDescr.frontFaceStencil.writeMask = 0x00
        readStencilState = Renderer.instance.device.makeDepthStencilState(descriptor: readStencilDescr)!
        readStencilDescr.isDepthWriteEnabled = false
        readStencilNoDepthWriteState = Renderer.instance.device.makeDepthStencilState(descriptor: readStencilDescr)!

        // The renderer's default depth state with the write turned off: what a
        // blended mesh draws with, so that it neither hides what is behind it
        // from the meshes drawn after it nor writes its transparent texels.
        let noDepthWriteDescr = MTLDepthStencilDescriptor()
        noDepthWriteDescr.depthCompareFunction = .lessEqual
        noDepthWriteDescr.isDepthWriteEnabled = false
        noDepthWriteState = Renderer.instance.device.makeDepthStencilState(descriptor: noDepthWriteDescr)!
    }

    func enqueue(_ renderable: Renderable) {
        if (renderable.occlusion || renderable.shadowPass) && !Settings_displayOcclusionObjects() {
            return;
        }

        for mesh in renderable.meshes {
            if mesh.material.transparent {
                transparent.append(mesh)
            } else if mesh.material.stencilMode == .write {
                stencil.append(mesh)
            } else {
                opaque.append(mesh)
            }
        }
    }

    func renderFrame(_ encoder: MTLRenderCommandEncoder, _ frameContext: FrameContext, _ renderer: Renderer) {
        // Back to front, so that every blended fragment lands on all that is
        // behind it. A material's priority comes before its distance: that is
        // how an overlay stays on top of a scene it may well sit inside of.
        // Stable, so meshes at one depth keep the order they were enqueued in.
        let order = transparent.enumerated().sorted { a, b in
            let priorityA = a.element.material.sortPriority
            let priorityB = b.element.material.sortPriority
            if priorityA != priorityB {
                return priorityA < priorityB
            }
            let depthA = a.element.sortDepth()
            let depthB = b.element.sortDepth()
            if depthA != depthB {
                return depthA > depthB
            }
            return a.offset < b.offset
        }

        // The passes before this one leave the state wherever they finished.
        restoreState(encoder, renderer)

        for mesh in stencil {
            drawRenderable(mesh, encoder, frameContext, renderer, depthWrite: false)
        }
        stencil.removeAll()

        for mesh in opaque {
            drawRenderable(mesh, encoder, frameContext, renderer)
        }
        opaque.removeAll()

        for entry in order {
            drawRenderable(entry.element, encoder, frameContext, renderer)
        }
        transparent.removeAll()

        restoreState(encoder, renderer)
    }

    // `depthWrite` overrides the material's own, for the stencil writers.
    func drawRenderable(_ mesh: RenderableMesh, _ encoder: MTLRenderCommandEncoder, _ frameContext: FrameContext, _ renderer: Renderer, depthWrite: Bool? = nil) {
        let material = mesh.material
        let writeDepth = depthWrite ?? material.depthWrite

        let state: MTLDepthStencilState?
        switch material.stencilMode {
        case .write: state = writeStencilState
        case .read:  state = writeDepth ? readStencilState : readStencilNoDepthWriteState
        default:     state = writeDepth ? renderer.depthStencilState : noDepthWriteState
        }
        applyState(encoder, state!, material.cullMode)

        material.setupRender(renderer, encoder, mesh, frameContext, occlusionPass: false, shadowMapPass: false, shadowsPass: false)
        mesh.mesh.draw(encoder)
    }

    private func applyState(_ encoder: MTLRenderCommandEncoder, _ depthStencilState: MTLDepthStencilState, _ cullMode: MTLCullMode) {
        if currentDepthStencilState !== depthStencilState {
            encoder.setDepthStencilState(depthStencilState)
            currentDepthStencilState = depthStencilState
        }
        if currentCullMode != cullMode {
            encoder.setCullMode(cullMode)
            currentCullMode = cullMode
        }
    }

    // The renderer's defaults, set unconditionally: what the encoder holds
    // on entry is another pass's, and what it holds on exit is the next one's.
    private func restoreState(_ encoder: MTLRenderCommandEncoder, _ renderer: Renderer) {
        encoder.setDepthStencilState(renderer.depthStencilState)
        currentDepthStencilState = renderer.depthStencilState
        encoder.setCullMode(.back)
        currentCullMode = .back
    }
}
