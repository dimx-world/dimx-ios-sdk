//
//  AppSettings.swift
//  dimx-ios-app
//
//  Created by Sergii Romanov on 10/12/2022.
//  Copyright © 2022 Dimensions. All rights reserved.
//

import Foundation

public class AppSettings {
    static private let WEB_APP_HOST_KEY = "web_app_host"
    static private let WEB_VERSION_KEY = "web_version_"

    // The install id has a file and a class of its own: it is the one setting here
    // that must not be restored onto another device, and the one two threads ask
    // for at once. See AppInstanceId.
    private let mAppInstanceId = AppInstanceId()
    private var mWebAppHost: String!

    func appInstanceId() -> String {
        return mAppInstanceId.id()
    }

    public func webAppHost() -> String {
        if mWebAppHost != nil {
            return mWebAppHost
        }
        mWebAppHost = UserDefaults.standard.string(forKey: AppSettings.WEB_APP_HOST_KEY)
        if mWebAppHost == nil {
            setWebAppHost("https://app.dimx.world")
        } else {
            Logger.info("Loaded existing web app host: \(String(describing: mWebAppHost))")
        }
        return mWebAppHost
    }

    /// Public for the app's own override: a debug build of dimx-ios-app applies the
    /// host Cockpit compiled into its Info.plist here, before the first screen opens.
    public func setWebAppHost(_ value: String) {
        mWebAppHost = value
        UserDefaults.standard.setValue(mWebAppHost, forKey: AppSettings.WEB_APP_HOST_KEY)
        Logger.info("Setting web app host: \(String(describing: mWebAppHost))")
    }
    
    func getWebVersion(_ key: String) -> String? {
        return UserDefaults.standard.string(forKey: AppSettings.WEB_VERSION_KEY + key)
    }
    
    func setWebVersion(_ key: String, _ value: String) {
        UserDefaults.standard.setValue(value, forKey: AppSettings.WEB_VERSION_KEY + key)
    }
}
