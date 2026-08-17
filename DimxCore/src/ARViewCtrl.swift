import MetalKit
import AVFoundation
import DimxNative

class CustomPanGestureRecognizer: UIPanGestureRecognizer {
  private var initialTouchLocation: CGPoint!

  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
    super.touchesBegan(touches, with: event)
    initialTouchLocation = touches.first!.location(in: view)
  }
}

// The AR screen. The engine is neither created nor destroyed here and does not
// stop when this controller goes away - all this screen does is lend the
// renderer its layer and tell the engine when it is on top. See Context, which
// owns the engine, and IOSEngine, which owns the update loop.
class ARViewCtrl: UIViewController, UITextInputTraits {
    // The session this screen was opened with, replayed on the way in the way
    // AndEngine::onActivityResume replays its intent.
    var pendingUrl = ""
    var pendingSettingsData = ""
    var pendingAccountData = ""
    var isCurrentlyVisible = false
    var mExtMediaStore = ExtMediaStore()

    // Hides the layer's retained contents - the last frame of the previous
    // session - from the moment this screen is put back up until a frame drawn
    // by the new one is on screen. Without it, re-entering AR shows wherever you
    // were last time until the first new frame lands.
    private var staleFrameCover: UIView?
    private var staleFrameCoverShownAt: CFTimeInterval = 0

    var arView: ARView {
        return view as! ARView
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.view = ARView()

        //Adding notifies on keyboard appearing
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWasShown(_:)), name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillBeHidden(_:)), name: UIResponder.keyboardWillHideNotification, object: nil)

        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        NotificationCenter.default.addObserver(self, selector: #selector(orientationDidChange), name: UIDevice.orientationDidChangeNotification, object: nil)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        Context.inst().refreshInterfaceOrientation()

        // Up before the layer is handed over, so there is no window in which the
        // old contents can be composited.
        showStaleFrameCover()

        // Hand the renderer the layer before the engine is told it has one.
        arView.setNeedsLayout()
        arView.layoutIfNeeded()
        Renderer.instance.attachLayer(arView.metalLayer) { [weak self] in
            self?.hideStaleFrameCover()
        }
        engineSetSurfaceAttached(true)
    }

    private func showStaleFrameCover() {
        guard staleFrameCover == nil else { return }

        let cover = UIView(frame: view.bounds)
        cover.backgroundColor = .black
        cover.isOpaque = true
        cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        // Purely visual: it must never eat a touch, however briefly it is up.
        cover.isUserInteractionEnabled = false
        view.addSubview(cover)
        staleFrameCover = cover
        staleFrameCoverShownAt = CACurrentMediaTime()
    }

    private func hideStaleFrameCover() {
        guard let cover = staleFrameCover else { return }

        // DIAGNOSTIC: how long the black cover was up, i.e. how long the stale
        // frame would have been visible without it. Remove with the others.
        let heldMs = (CACurrentMediaTime() - staleFrameCoverShownAt) * 1000
        Logger.info(String(format: "ARViewCtrl: stale-frame cover lifted after %.1f ms", heldMs))

        cover.removeFromSuperview()
        staleFrameCover = nil
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        isCurrentlyVisible = true
        UIApplication.shared.isIdleTimerDisabled = true

        engineSetScreenVisible(true)
        onScreenResume()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        isCurrentlyVisible = false

        // Off the screen first, then the layer: the loop leaves live mode on its
        // next iteration and stops drawing on its own.
        engineSetScreenVisible(false)
        engineSetSurfaceAttached(false)
        Renderer.instance.detachLayer()

        // detachLayer dropped the callback that would have taken this down, so
        // leaving before the first frame landed would otherwise strand it.
        hideStaleFrameCover()

        DeviceAR.instance.pauseSession()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        UIApplication.shared.isIdleTimerDisabled = false
    }

    // The AR screen coming up, whether that is a fresh presentation or the app
    // returning to the foreground with it still on top. Mirrors what Android
    // does from onActivityResume.
    func onScreenResume() {
        let url = pendingUrl
        let settingsData = pendingSettingsData
        let accountData = pendingAccountData

        // Consumed once. A later resume reloads the session without replaying
        // the url that opened it.
        pendingUrl = ""
        pendingSettingsData = ""
        pendingAccountData = ""

        Logger.info("ARViewCtrl: screen resume, session url [\(url)]")
        Context.inst().reloadARSession(url, settingsData, accountData)
    }
/*
    static func showAR(_ url: String, _ settingsData: String, _ accountData: String) {
        if (ARViewCtrl.instance == nil) {
            let storyBoard = UIStoryboard(name: "Main", bundle: nil)
            ARViewCtrl.instance = (storyBoard.instantiateViewController(withIdentifier: "ARView") as! ARViewCtrl)
            ARViewCtrl.instance!.processUrl = url
            ARViewCtrl.instance!.settingsData = settingsData
            ARViewCtrl.instance!.accountData = accountData
        } else {
            reloadEngineSession(url, settingsData, accountData)
        }
       
        WebViewCtrl.instance!.navigationController!.show(ARViewCtrl.instance!, sender: nil)
    }

    static func hideAR() {
        ARViewCtrl.instance!.navigationController!.popViewController(animated: true)
    }
*/
    func showKeyboard() {
        if (!view.isFirstResponder) {
            view.becomeFirstResponder()
        }
    }
    func hideKeyboard() {
        if (view.isFirstResponder) {
            view.resignFirstResponder()
        }
    }
    
    @objc func keyboardWasShown(_ notification: Notification) {
        let userInfo = notification.userInfo!
        let keyboardSize = (userInfo[UIResponder.keyboardFrameEndUserInfoKey] as AnyObject).cgRectValue.size
        let keyboardTop = view.frame.size.height - keyboardSize.height
        
        let viewport = Renderer.instance.viewportSize
        let bounds = view.bounds
        let pixelsTop = Float(keyboardTop / bounds.height * viewport.height)
        
        setKeyboardTop(pixelsTop);
    }
    
    @objc func keyboardWillBeHidden(_ notification: Notification) {
        setKeyboardTop(0.0); // 0.0 is a special value
    }
    
    @objc func orientationDidChange(notification: NSNotification) {
        // The engine thread reads the interface orientation every frame and must
        // not ask UIKit for it, so refresh the cached value here even though the
        // resize itself is still ignored.
        Context.inst().refreshInterfaceOrientation()
        Logger.info("ARViewCtrl: orientation change ignored.")
/*
        guard let deviceOrientation = UIDevice.current.orientation as UIDeviceOrientation? else {
            return
        }

        // Force layout update
        view.setNeedsLayout() // not working
        view.layoutIfNeeded() // not working
        
        let width = Renderer.instance.viewportSize.width
        let height = Renderer.instance.viewportSize.height
        // Display_setSize(Int(width), Int(height))
        Display_setSize(Int(height), Int(width)) // swap the value because they haven't updated yet
        
        Renderer.instance.backgroundPass.setViewportChanged()
*/
    }
    
    func moveToExtMediaFile(_ src: String, _ dst: String) {
        mExtMediaStore.moveToExtMediaFile(src, dst)
    }
    
    func shareExtMediaFile(_ args: String) {
        mExtMediaStore.shareExtMediaFile(self, args)
    }

}
