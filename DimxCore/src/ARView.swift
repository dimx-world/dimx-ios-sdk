import Foundation
import MetalKit
import DimxNative

class Vec2 {
    var x: Float = 0
    var y: Float = 0
    init() {
        x = 0
        y = 0
    }
    init(xx: Float, yy: Float) {
        x = xx
        y = yy
    }
}

func screenPos(_ point: CGPoint, _ bounds: CGRect) -> Vec2 {
    // UIScreen.main.scale)
    let scaleX = Renderer.instance.viewportSize.width / bounds.width
    let scaleY = Renderer.instance.viewportSize.height / bounds.height
    return Vec2(xx: Float(point.x * scaleX), yy: Float(point.y * scaleY))
}


class TouchListener {
  
    var count: Int = 0
    var firstFinger: UInt = 0
    var firstFingerPos = Vec2()
    
    func onTouchDown(_ key: UInt, _ pos: Vec2) {
        //Logger.debug("touch down: \(key) [\(pos.x) \(pos.y)]")
        if count == 0 {
            firstFinger = key
            firstFingerPos = pos
            processTouchDown(pos.x, pos.y)
        } else if count == 1 {
            processMultitouchDown(firstFingerPos.x, firstFingerPos.y)
        }
        count += 1
    }
    
    func onTouchMove(_ key: UInt, _ pos: Vec2) {
        if key == firstFinger {
            firstFingerPos = pos
            processTouchMove(pos.x, pos.y)
        }
    }

    func onTouchUp(_ key: UInt, _ pos: Vec2) {
        //Logger.debug("touch up: \(key) [\(pos.x) \(pos.y)]")
        count -= 1
        if count == 1 {
            processMultitouchUp(firstFingerPos.x, firstFingerPos.y)
        } else if count == 0 {
            processTouchUp(firstFingerPos.x, firstFingerPos.y)
        }
        
        // clean up
        if count <= 0 {
            cancelAll()
        }
    }
    
    func cancelAll() {
        //Logger.debug("touch cancel")
        count = 0
        firstFinger = 0
        firstFingerPos = Vec2()
    }
}

// A plain CAMetalLayer-backed view. It used to be an MTKView, whose display link
// was the engine's entire update loop and stopped the moment the view left the
// window. The loop now lives on the engine thread (see IOSEngine); all this view
// does is lend the renderer a layer to draw into.
class ARView: UIView, UIKeyInput
{
    let touchListener = TouchListener()

    override class var layerClass: AnyClass {
        return CAMetalLayer.self
    }

    var metalLayer: CAMetalLayer {
        return layer as! CAMetalLayer
    }

    override init(frame frameRect: CGRect) {
        super.init(frame: frameRect)
        isMultipleTouchEnabled = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        isMultipleTouchEnabled = true
    }

    // The engine thread must never touch the layer to find out how big it is, so
    // the size is pushed to the renderer from here, where it is known.
    override func layoutSubviews() {
        super.layoutSubviews()

        let scale = window?.screen.scale ?? UIScreen.main.scale
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        guard size.width > 0 && size.height > 0 else { return }

        metalLayer.contentsScale = scale
        metalLayer.drawableSize = size
        Renderer.instance.setViewportSize(size)
    }

    var hasText: Bool {
        return true
    }
    
    func insertText(_ text: String) {
        if (text.count > 0) {
            processInsertText(Int(text.unicodeScalars.first!.value))
        }
    }
    
    func deleteBackward() {
        processDeleteBackward()
    }
    
    override var canBecomeFirstResponder: Bool {
        return true
    }

    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        for touch in touches {
            touchListener.onTouchDown(UInt(bitPattern: ObjectIdentifier(touch)),
                                      screenPos(touch.location(in: self), bounds))
        }
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        for touch in touches {
            touchListener.onTouchMove(UInt(bitPattern: ObjectIdentifier(touch)),
                                       screenPos(touch.location(in: self), bounds))
        }
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        //Logger.debug("BDS: \(bounds)")
        //Logger.debug("VPS: \(Renderer.instance.viewportSize)")
        //Logger.debug("SCL: \(UIScreen.main.scale)")
        for touch in touches {
            //let pnt = touch.location(in: self)
            //Logger.debug("PNT: \(pnt)")
            touchListener.onTouchUp(UInt(bitPattern: ObjectIdentifier(touch)),
                                    screenPos(touch.location(in: self), bounds))
        }
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        touchListener.cancelAll()
    }
}
