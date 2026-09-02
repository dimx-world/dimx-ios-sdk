//
//  LocationManager.swift
//  dimx-ios-app
//
//  Created by Sergii Romanov on 03/08/2022.
//  Copyright © 2022 Dimensions. All rights reserved.
//

import Foundation
import CoreLocation
import DimxNative

class LocationManager: NSObject, CLLocationManagerDelegate {
    private let mManager = CLLocationManager()
    private let mBeaconScanner = BeaconScanner()
    private var mLocation: CLLocation?
    // Everyone waiting on the one prompt that can be up at a time; a second
    // request while it shows joins the list instead of replacing the first.
    private var mAuthCallbacks: [(Bool) -> Void] = []
    
    override init() {
        super.init()
        mManager.delegate = self
        mManager.desiredAccuracy = kCLLocationAccuracyBest
        mManager.distanceFilter = 1.0
        mManager.startUpdatingLocation()
    }
    
    func location() -> CLLocation? {
        return mLocation;
    }
    
    func handleAuthorizationStatus(_ status: CLAuthorizationStatus) {
        Logger.info("location manager authorization status changed: \(status.rawValue)")
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            answerAuthCallbacks(true)
        case .denied, .restricted:
            answerAuthCallbacks(false)
        case .notDetermined:
            break
        @unknown default:
            break
        }
    }

    private func answerAuthCallbacks(_ granted: Bool) {
        let callbacks = mAuthCallbacks
        mAuthCallbacks.removeAll()
        for callback in callbacks {
            callback(granted)
        }
    }

    func authorizationStatus() -> CLAuthorizationStatus {
        if #available(iOS 14.0, *) {
            return mManager.authorizationStatus
        } else {
            return CLLocationManager.authorizationStatus()
        }
    }
    
    //For iOS >= 14
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        handleAuthorizationStatus(manager.authorizationStatus)
    }
    
    //For iOS < 14
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        handleAuthorizationStatus(status)
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Logger.error("location manager error: \(error.localizedDescription)")
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let loc = locations.last {
            mLocation = loc
            //Logger.info("SWIFT Geolocation update: \(mLocation!)")
            processGeolocationUpdate(mLocation!.coordinate.latitude,
                                     mLocation!.coordinate.longitude,
                                     mLocation!.altitude,
                                     mLocation!.horizontalAccuracy,
                                     mLocation!.verticalAccuracy)
        }
    }
    
    func onRequestGeolocatinUpdate() {
        //Logger.info("SWIFT onRequestGeolocatinUpdate: \(mLocation!)")
        if mLocation != nil {
            processGeolocationUpdate(mLocation!.coordinate.latitude,
                                     mLocation!.coordinate.longitude,
                                     mLocation!.altitude,
                                     mLocation!.horizontalAccuracy,
                                     mLocation!.verticalAccuracy)
        }
    }

    /// The engine names a beacon UUID it wants observations for. Ranging is not
    /// started until the first one arrives, and covers exactly the UUIDs registered.
    func beaconsRegisterUuid(_ uuid: String) {
        mBeaconScanner.register(uuid)
    }

    /// The engine has no beacons nearby; ranging and its UUIDs are dropped until the next registration.
    func beaconsStopScanning() {
        mBeaconScanner.stop()
    }
    
    /// Answers at once when the user has already decided, and after the prompt
    /// when they have not. Only `.notDetermined` can be prompted for: iOS never
    /// shows the alert twice, so a denial stands until changed in Settings.
    func requestPermission(_ callback: @escaping (Bool) -> Void) {
        switch authorizationStatus() {
        case .notDetermined:
            let prompting = !mAuthCallbacks.isEmpty
            mAuthCallbacks.append(callback)
            if !prompting {
                mManager.requestWhenInUseAuthorization()
            }
            return
        case .authorizedWhenInUse, .authorizedAlways:
            callback(true)
            return
        case .denied, .restricted:
            callback(false)
            return
        @unknown default:
            break
        }
        callback(false)
    }
}
