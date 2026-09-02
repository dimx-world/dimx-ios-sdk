//
//  Context.swift
//  DimxCore
//
//  Created by Sergii Romanov on 21/07/2023.
//  Copyright © 2023 Dimensions. All rights reserved.
//

import Foundation
import UIKit
import Metal
import AVFoundation
import DimxNative

func topMostViewController() -> UIViewController? {
    var topController: UIViewController? = UIApplication.shared.keyWindow?.rootViewController
    while let presentedViewController = topController?.presentedViewController {
        topController = presentedViewController
    }
    return topController
}

// NSObject so the app-lifecycle notifications below can target it with a
// selector - the engine's foreground/background handshake hangs off them.
public class Context: NSObject
{
    static var sInstance: Context!

    private let mSettings = AppSettings()
    private var mAppConfig: AppConfig!
    private var mLocationManager: LocationManager!
    private var mPermissions: PermissionsManager!
    private var mWindow: UIWindow!

    private var mARViewCtrl: ARViewCtrl!
    private var mWebViewCtrl: WebViewCtrl?

    // The engine thread reads the interface orientation every frame (camera
    // projection, background plane) and must not go near UIKit for it. Cached
    // here and refreshed from the main thread on every event that can change it.
    private let mOrientationLock = NSLock()
    private var mInterfaceOrientation: UIInterfaceOrientation = .portrait

    static public func initialize(_ window: UIWindow, _ appConfig: AppConfig) {
        if sInstance != nil {
            fatalError("Context already initialized")
        }
        sInstance = Context()
        sInstance.initializeInternal(window, appConfig)
    }

    static public func inst() -> Context {
        return sInstance
    }
    
    override init() { super.init() }

    func initializeInternal(_ window: UIWindow, _ appConfig: AppConfig) {
        mAppConfig = appConfig
        mLocationManager = LocationManager()
        mPermissions = PermissionsManager(mLocationManager)
        mWindow = window

        refreshInterfaceOrientation()

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback)
            try session.setActive(true)
        } catch {
            Logger.error("Error setting audio session category or activating audio session: \(error)")
        }

        NotificationCenter.default.addObserver(self, selector: #selector(appDidEnterBackground),
                                               name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appWillEnterForeground),
                                               name: UIApplication.willEnterForegroundNotification, object: nil)

        initEngineInternal()
    }

    // The engine belongs to the app, not to a screen: it is created here, runs on
    // its own thread for the life of the process and keeps updating whether or
    // not anything is on screen. ARViewCtrl only lends it a layer.
    private func initEngineInternal() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported on this device")
        }

        let screenBounds = mWindow.screen.bounds
        let scale = mWindow.screen.scale
        let screenSize = CGSize(width: screenBounds.width * scale, height: screenBounds.height * scale)

        Renderer.initSingleton(device, screenSize)

        initEngineCallbacks()
        initAnalyticsInfo()

        let libPath = try! FileManager.default.url(for: .libraryDirectory, in: .userDomainMask, appropriateFor: nil, create: false).path

        Logger.info("SWIFT: initializing engine, screen \(screenSize)")
        initEngine(mSettings.appInstanceId(),
                   Bundle.module.bundlePath.appending("/data"),
                   libPath + "/LocalStorage",
                   libPath + "/Caches",
                   "ExtMedia",
                   mAppConfig.toJsonString(),
                   Int(screenSize.width),
                   Int(screenSize.height))
    }

    // Every one of these is called from the engine thread. The ones that touch
    // UIKit hop to the main queue here, at the boundary - the C++ side has no
    // business knowing which of them do. The C strings are only valid for the
    // duration of the call, so they are copied before the hop.
    private func initEngineCallbacks() {
        g_swiftEngine().pointee.showKeyboard = {
            DispatchQueue.main.async { Context.inst().arViewCtrl()?.showKeyboard() }
        }
        g_swiftEngine().pointee.hideKeyboard = {
            DispatchQueue.main.async { Context.inst().arViewCtrl()?.hideKeyboard() }
        }
        g_swiftEngine().pointee.showAppScreen = { (url: UnsafePointer<CChar>!) -> Void in
            let url = String(cString: url)
            DispatchQueue.main.async { Context.inst().showAppScreen(url) }
        }
        g_swiftEngine().pointee.openUrlExternal = { (url: UnsafePointer<CChar>!) -> Void in
            let url = String(cString: url)
            DispatchQueue.main.async { Context.inst().openUrlExternal(url) }
        }
        g_swiftEngine().pointee.requestGeolocationUpdate = {
            // CLLocationManager belongs to the thread it was created on.
            DispatchQueue.main.async { Context.inst().locationManager().onRequestGeolocatinUpdate() }
        }
        g_swiftEngine().pointee.beaconsRegisterUuid = { (rawUuid: UnsafePointer<CChar>!) -> Void in
            let uuid = String(cString: rawUuid)
            DispatchQueue.main.async { Context.inst().locationManager().beaconsRegisterUuid(uuid) }
        }
        g_swiftEngine().pointee.beaconsStopScanning = {
            DispatchQueue.main.async { Context.inst().locationManager().beaconsStopScanning() }
        }
        g_swiftEngine().pointee.updateGeolocation = { (rawValue: UnsafePointer<CChar>!) -> Void in
            let value = String(cString: rawValue)
            DispatchQueue.main.async { Context.inst().webViewCtrl()?.updateGeolocation(value) }
        }
        g_swiftEngine().pointee.moveToExtMediaFile = { (src: UnsafePointer<CChar>!, dst: UnsafePointer<CChar>!) -> Void in
            let src = String(cString: src)
            let dst = String(cString: dst)
            DispatchQueue.main.async { Context.inst().arViewCtrl()?.moveToExtMediaFile(src, dst) }
        }
        g_swiftEngine().pointee.shareExtMediaFile = { (args: UnsafePointer<CChar>!) -> Void in
            let args = String(cString: args)
            DispatchQueue.main.async { Context.inst().arViewCtrl()?.shareExtMediaFile(args) }
        }
        // Deliberately synchronous, and deliberately touches nothing but Metal:
        // the engine thread calls this to drain the GPU before it parks.
        g_swiftEngine().pointee.waitForGpuIdle = {
            Renderer.instance.waitForGpuIdle()
        }

        Renderer.initCallbacks()
        DeviceAR.initCallbacks()
        AnchorSession.initCallbacks()
        Texture.initCallbacks()
        Material.initCallbacks()
        Mesh.initCallbacks()
        Renderable.initCallbacks()
    }

    private func initAnalyticsInfo() {
        AnalyticsManager_setOSVersion(UIDevice.current.systemVersion)

        var systemInfo = utsname()
        uname(&systemInfo)
        let deviceModel = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                ptr in String.init(validatingUTF8: ptr)
            }
        }
        AnalyticsManager_setDeviceModel(deviceModel)
    }

    // MARK: - App lifecycle

    // This must not return until the update loop has stopped and the GPU has
    // gone idle. Submitting GPU work after the app is backgrounded is what the
    // iOS watchdog kills apps for, so unlike Android's setAppInForeground(false)
    // the handshake here is synchronous. engineEnterBackground blocks.
    @objc private func appDidEnterBackground() {
        Logger.info("Context: app did enter background")
        engineEnterBackground()
    }

    @objc private func appWillEnterForeground() {
        Logger.info("Context: app will enter foreground")
        refreshInterfaceOrientation()
        engineEnterForeground()

        if mARViewCtrl != nil && mARViewCtrl.isCurrentlyVisible {
            mARViewCtrl.onScreenResume()
        }
    }

    func openUrlExternal(_ urlString: String) {
        guard let url = URL(string: urlString) else {
            Logger.error("Invalid external URL: \(urlString)")
            return
        }
        guard UIApplication.shared.canOpenURL(url) else {
            Logger.error("Unable to open external URL: \(urlString)")
            return
        }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }

    /// Asks for and reports the permissions the AR screen needs. Nothing is
    /// cached: `showARScreen` asks on every call, so a denial is recovered
    /// from by tapping the camera button again once Settings has changed.
    public func permissions() -> PermissionsManager {
        return mPermissions
    }

    public func settings() -> AppSettings {
        return mSettings
    }

    func appConfig() -> AppConfig {
        return mAppConfig
    }

    func locationManager() -> LocationManager {
        return mLocationManager
    }

    // Optional now: the engine starts with the app and can call back before any
    // AR screen has ever been created.
    func arViewCtrl() -> ARViewCtrl? {
        return mARViewCtrl;
    }

    func webViewCtrl() -> WebViewCtrl? {
        return mWebViewCtrl;
    }

    public func showAppScreen(_ args: String) {
        mAppConfig.showAppScreenAction()?(args)
    }

    /// Opens the AR screen once the user has granted what it needs, asking for
    /// whatever is still undecided. Only the camera is required: a refusal
    /// shows an alert with a way to Settings, then runs `onDenied` - a deep
    /// link falls back to the web screen there, the camera button on the web
    /// screen has nothing to fall back to. Location is recommended: without it
    /// the screen still opens, with a toast saying it cannot find nearby
    /// content. Beacon ranging is only logged when Bluetooth is off.
    public func showARScreen(_ url: String, _ settingsData: String, _ accountData: String,
                             onDenied: (() -> Void)? = nil) {
        mPermissions.requestAR { [self] outcome in
            if !outcome.camera {
                Logger.warn("AR screen refused: camera access denied")
                mPermissions.presentCameraDeniedAlert(outcome) { onDenied?() }
                return
            }
            if !outcome.bluetooth {
                Logger.warn("Bluetooth is off: beacon ranging unavailable, positioning falls back to GPS")
            }
            presentARScreen(url, settingsData, accountData)
            if !outcome.location {
                Logger.warn("Location access denied: Live View opens without nearby content")
                Toast.show("Access to your location is off for this app, so Live View cannot find nearby content.\(outcome.settingsHint)")
            }
        }
    }

    private func presentARScreen(_ url: String, _ settingsData: String, _ accountData: String) {
        if (mARViewCtrl == nil) {
            mARViewCtrl = ARViewCtrl()
            mARViewCtrl.modalPresentationStyle = .fullScreen //or .overFullScreen for transparency
        }

        // The session is handed to the screen and applied when it comes
        // up, rather than reloaded from here - the engine is already
        // running and the screen is what decides it is live.
        mARViewCtrl.pendingUrl = url
        mARViewCtrl.pendingSettingsData = settingsData
        mARViewCtrl.pendingAccountData = accountData

        if mARViewCtrl.isCurrentlyVisible {
            mARViewCtrl.onScreenResume()
            return
        }

        mWindow.rootViewController!.dismiss(animated: false)
        mWindow.rootViewController!.present(mARViewCtrl, animated: false, completion: nil)
    }

    public func showWebScreen(_ webUrl: String) {
        if (mWebViewCtrl == nil) {
            mWebViewCtrl = WebViewCtrl()
            mWebViewCtrl!.modalPresentationStyle = .fullScreen
        }

        mWindow.rootViewController!.dismiss(animated: false)
        mWindow.rootViewController!.present(mWebViewCtrl!, animated: false, completion: {[self, webUrl] in
            mWebViewCtrl!.loadWebUrl(webUrl)
        })
    }

    public func convertAppUrlToWebUrl(_ appUrl: String) -> String {
        let stringObj = String_create(UnsafeRawPointer(bitPattern: 0))
        cppConvertAppUrlToWebUrl(mSettings.webAppHost(), appUrl, stringObj)
        let webUrl = String(cString: String_cstr(stringObj))
        String_delete(stringObj)
        return webUrl
    }
    
    public func reloadARSession(_ url: String, _ settingsData: String, _ accountData: String) {
        DeviceAR.instance.restartSession()
        reloadEngineSession(url, settingsData, accountData)
    }

    // Read from the engine thread every frame - the cached value, never UIKit.
    public func getInterfaceOrientation() -> UIInterfaceOrientation {
        mOrientationLock.lock()
        defer { mOrientationLock.unlock() }
        return mInterfaceOrientation
    }

    // Main thread only.
    func refreshInterfaceOrientation() {
        let orientation = mARViewCtrl?.view.window?.windowScene?.interfaceOrientation
            ?? mWindow?.windowScene?.interfaceOrientation
            ?? .portrait

        mOrientationLock.lock()
        let changed = mInterfaceOrientation != orientation
        mInterfaceOrientation = orientation
        mOrientationLock.unlock()

        if changed {
            Logger.info("Context: interface orientation is now \(orientation.rawValue)")
        }
    }
}
