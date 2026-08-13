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
    private var mQRCodeEnabled: Bool = false
    private var mSharePhotoEnabled: Bool = false
    private var mShareVideoEnabled: Bool = false
    private var mWebVersions: [String] = []
    private var mGoogleClientId: String = ""
    private var mAppleSignInEnabled: Bool = true

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

    public func setQRCodeEnabled(_ value: Bool) {
        mQRCodeEnabled = value
    }

    public func setSharePhotoEnabled(_ value: Bool) {
        mSharePhotoEnabled = value
    }
    
    public func setShareVideoEnabled(_ value: Bool) {
        mShareVideoEnabled = value
    }
    
    public func addWebVersion(_ url: String) {
        mWebVersions.append(url)
    }
    
    public func webVersions() -> [String] {
        return mWebVersions
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

    func toJsonString() -> String {
        var jsonObject: [String: Any] = [
            "back_enabled": mShowAppScreenAction != nil,
            "qrcode_enabled": mQRCodeEnabled,
            "share_photo_enabled": mSharePhotoEnabled,
            "share_video_enabled": mShareVideoEnabled
        ]
        if mDimensions.count > 0 {
            jsonObject["dimensions"] = mDimensions
        }
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
