import Foundation
import Metal
import DimxNative

class OcclusionPass
{
    var queue: [Renderable] = []
    
    init(_ renderer: Renderer) {
    }
    
    // At every frame's start (Renderer.beginFrame): a frame that ends without
    // drawing must not leave its renderables queued - see DefaultPass.clearQueue.
    func clearQueue() {
        queue.removeAll()
    }

    func enqueue(_ renderable: Renderable) {
        if renderable.occlusion {
            queue.append(renderable)
        }
    }

    func renderFrame(_ encoder: MTLRenderCommandEncoder, _ frameContext: FrameContext, _ renderer: Renderer) {
        for rend in queue {
            for mesh in rend.meshes {
                mesh.material.setupRender(renderer, encoder, mesh, frameContext, occlusionPass: true)
                mesh.mesh.draw(encoder)
            }
        }
        
        queue.removeAll()
    }
}
