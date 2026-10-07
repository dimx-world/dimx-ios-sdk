//
//  AppConfig.swift
//  DimxCore
//
//  Created by Sergii Romanov on 21/07/2023.
//  Copyright © 2023 Dimensions. All rights reserved.
//

import Foundation
import UIKit

public class AppConfig
{
    private var mDimensions: [String] = []
    private var mShowAppScreenAction: ((String) -> Void)?
    private var mSharePhotoEnabled: Bool = false
    private var mShareVideoEnabled: Bool = false
    private var mAppScreenSplash: String = ""
    private var mGoogleClientId: String = ""
    private var mAppleSignInEnabled: Bool = true
    // Telemetry (the engine's TelemetryManager, posting to the platform's
    // receiver): off unless the host app turns it on - an SDK consumer's data
    // is theirs to send. The app name is what the receiver files it under.
    private var mTelemetryEnabled: Bool = false
    private var mTelemetryApp: String = "ios-sdk"

    public init() {}

    public func addDimension(_ id: String) {
        mDimensions.append(id)
    }

    public func setShowAppScreenAction(_ callback: ((String) -> Void)?) {
        mShowAppScreenAction = callback
    }

    func showAppScreenAction() -> ((String) -> Void)? {
        return mShowAppScreenAction
    }

    // Does nothing since 2026-10-04: the AR screen's QR scan button is gone, the
    // camera reads a code by itself. Kept so an app built against an older SDK
    // keeps compiling.
    @available(*, deprecated, message: "The QR scan button is gone; codes are read from the camera by themselves. This does nothing.")
    public func setQRCodeEnabled(_ value: Bool) {
    }

    public func setSharePhotoEnabled(_ value: Bool) {
        mSharePhotoEnabled = value
    }
    
    public func setShareVideoEnabled(_ value: Bool) {
        mShareVideoEnabled = value
    }
    
    /// The app's launch screen, by its storyboard's name ("LaunchScreen"), for the web
    /// screen to show while its first page loads. The system shows that screen while
    /// the app starts; an app that opens on the web screen names it here, and the
    /// screen holds the same picture over the web view until the page has its content
    /// up - one picture from the tap on the icon to the page, with no blank web view
    /// in between. Unset, and for any page loaded again later, the screen covers a
    /// loading page with a plain surface and its spinner.
    public func setAppScreenSplash(_ storyboardName: String) {
        mAppScreenSplash = storyboardName
    }

    func appScreenSplash() -> String {
        return mAppScreenSplash
    }
    
    // Overrides the OAuth client id used for native Google sign-in. Left unset, it comes
    // from GoogleService-Info.plist (CLIENT_ID) or the GIDClientID Info.plist key; with
    // none of the three, the web page falls back to its own popup for Google - which
    // Google then refuses with disallowed_useragent.
    public func setGoogleClientId(_ value: String) {
        mGoogleClientId = value
    }

    func googleClientId() -> String {
        return mGoogleClientId
    }

    // Native Sign in with Apple needs the com.apple.developer.applesignin entitlement and
    // a provisioning profile that carries it. A build without the capability must turn
    // this off, so the page uses its own popup instead of a sheet that fails immediately.
    public func setAppleSignInEnabled(_ value: Bool) {
        mAppleSignInEnabled = value
    }

    func appleSignInEnabled() -> Bool {
        return mAppleSignInEnabled
    }

    /// Turns the engine's telemetry on: crash markers, errors, session and
    /// frame-rate records to the platform's receiver, verbose on request from
    /// the platform's diagnostics switch. `app` names the build to the receiver
    /// (the DimensionX app is "ios-app"; a consumer leaves the default).
    public func setTelemetryEnabled(_ value: Bool, app: String = "ios-sdk") {
        mTelemetryEnabled = value
        mTelemetryApp = app
    }

    func telemetryEnabled() -> Bool {
        return mTelemetryEnabled
    }

    /// The identity the engine reports under: this app's bundle version, the
    /// OS, the device model - read here on the Swift side, where they are known.
    private func telemetryJson() -> [String: Any] {
        let info = Bundle.main.infoDictionary
        let version = (info?["CFBundleShortVersionString"] as? String) ?? "unknown"
        let build = (info?["CFBundleVersion"] as? String) ?? ""
        var systemInfo = utsname()
        uname(&systemInfo)
        let model = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(validatingUTF8: $0) ?? "" }
        }
        let osVersion = UIDevice.current.systemVersion
        return [
            "enabled": mTelemetryEnabled,
            "app": mTelemetryApp,
            // The version as the store shows it, the receiver's version label; the build beside it, never in it.
            "version": version,
            "build": build,
            "platform": "ios",
            "os": "iOS \(osVersion)",
            "os_major": String(osVersion.split(separator: ".").first ?? ""),
            "device_model": model
        ]
    }

    func toJsonString() -> String {
        var jsonObject: [String: Any] = [
            "back_enabled": mShowAppScreenAction != nil,
            "share_photo_enabled": mSharePhotoEnabled,
            "share_video_enabled": mShareVideoEnabled
        ]
        if mDimensions.count > 0 {
            jsonObject["dimensions"] = mDimensions
        }
        jsonObject["telemetry"] = telemetryJson()
        // The device's language, for a dimension's scene when neither the user's choice for
        // it nor the user's language is known - all an app with no page of ours has (the
        // engine's Settings::deviceLanguage).
        jsonObject["device_language"] = Locale.preferredLanguages.first ?? ""
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: jsonObject)
            let str = String(data: jsonData, encoding: .utf8)
            return str != nil ? str! : ""
        } catch {
            Logger.error("Error creating AppConfig JSON data: \(error)")
        }
        return ""
    }
}
