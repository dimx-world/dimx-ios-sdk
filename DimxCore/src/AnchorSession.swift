//
//  AnchorSession.swift
//  dimx-ios-app
//
//  Created by Sergii Romanov on 29/07/2022.
//  Copyright © 2022 Dimensions. All rights reserved.
//

import Foundation
import ARKit
import ARCoreGARSession
import ARCoreCloudAnchors
import DimxNative

func cloudAnchorStateToCore(_ state: GARCloudAnchorState) -> Int {
    switch state {
        case .taskInProgress: return Int(CLOUD_ANCHOR_STATE_IN_PROGRESS)
        case .success: return Int(CLOUD_ANCHOR_STATE_SUCCESS)
        case .errorInternal,
             .errorNotAuthorized,
             .errorResourceExhausted,
             .errorHostingDatasetProcessingFailed,
             .errorCloudIdNotFound,
             .errorResolvingSdkVersionTooOld,
             .errorResolvingSdkVersionTooNew,
             .errorHostingServiceUnavailable:
            return Int(CLOUD_ANCHOR_STATE_ERROR)
        case .none: return Int(CLOUD_ANCHOR_STATE_NONE)
        default: return Int(CLOUD_ANCHOR_STATE_NONE)
    }
}

func cloudAnchorStateToStr(_ state: GARCloudAnchorState) -> String {
    switch state {
        case .taskInProgress:                       return "In Progress"
        case .success:                              return "Success"
        case .errorInternal:                        return "Internal Error"
        case .errorNotAuthorized:                   return "Not Authorized"
        case .errorResourceExhausted:               return "Resource Exhausted"
        case .errorHostingDatasetProcessingFailed:  return "Hosting Dataset Processing Failed"
        case .errorCloudIdNotFound:                 return "Cloud Id Not Found"
        case .errorResolvingSdkVersionTooOld:       return "Resolving Sdk Version Too Old"
        case .errorResolvingSdkVersionTooNew:       return "Resolving Sdk Version Too New"
        case .errorHostingServiceUnavailable:       return "Hosting Service Unavailable"
        case .none:                                 return "None"
        default:                                    return "None"
    }
}

func featureMapQualityToCore(_ quality: GARFeatureMapQuality) -> Int {
    switch quality {
        case .good:         return Int(FEATURE_MAP_QUALITY_GOOD)
        case .insufficient: return Int(FEATURE_MAP_QUALITY_INSUFFICIENT)
        case .sufficient:   return Int(FEATURE_MAP_QUALITY_SUFFICIENT)
        default:            return Int(FEATURE_MAP_QUALITY_NONE)
    }
}

func writeStringToPointer(_ string: String, _ pointer: UnsafeMutableRawPointer, _ bufferSize: Int) {
    let data = string.data(using: .utf8)!
    let bytesToWrite = min(bufferSize - 1, data.count)
    data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
        pointer.copyMemory(from: bytes.baseAddress!, byteCount: bytesToWrite)
    }
    pointer.advanced(by: bytesToWrite).storeBytes(of: UInt8(0), as: UInt8.self)
}

class GAnchorInfo {
    var token: UInt = 0
    var cloudAnchor: GARAnchor?
    var localAnchorId: Int = -1
    var hostFuture: GARHostCloudAnchorFuture?
    var resolveFuture: GARResolveCloudAnchorFuture?
}

class AnchorSession {
    let ARCORE_API_KEY = "AIzaSyC9CB2bvJ6iZN1YruOlc09-7nlMMB2NucA"
    static let instance = AnchorSession()

    var gSession: GARSession!
    var anchors = [GAnchorInfo?]()

    static func initCallbacks() {
        g_swiftCloudAnchorSession().pointee.initialize = {
            () -> () in AnchorSession.instance.initialize()
        }
        g_swiftCloudAnchorSession().pointee.createAnchor = {
            (token: UInt, transformPtr: Optional<UnsafeRawPointer>, ttlDays: Int) in
                AnchorSession.instance.createAnchor(token, transformPtr!, ttlDays)
        }
        g_swiftCloudAnchorSession().pointee.resolveAnchor = {
            (token: UInt, nativeId: UnsafePointer<CChar>!) in
                AnchorSession.instance.resolveAnchor(token, String(cString: nativeId))
        }
        g_swiftCloudAnchorSession().pointee.removeAnchor = {
            (token: UInt, anchorId: Int) in AnchorSession.instance.removeAnchor(token, anchorId)
        }
        g_swiftCloudAnchorSession().pointee.getAnchorTracking = {
            (anchorId: Int, outPtr: Optional<UnsafeMutableRawPointer>) in
                AnchorSession.instance.getAnchorTracking(anchorId, outPtr!)
        }
        g_swiftCloudAnchorSession().pointee.featureMapQuality = {
            () -> Int in return AnchorSession.instance.featureMapQuality()
        }
    }

    func initialize() {
        do {
            gSession = try GARSession(apiKey: ARCORE_API_KEY, bundleIdentifier: Bundle.main.bundleIdentifier)
            let config = GARSessionConfiguration()
            config.cloudAnchorMode = .enabled
            var error: NSError?
            gSession.setConfiguration(config, error: &error)
            if let error = error {
                Logger.error("Error setting GARSession configuration: \(error)")
            }
        } catch {
            fatalError("Error creating GARSession: \(error.localizedDescription)")
        }
    }

    func update() {
        guard let frame = DeviceAR.instance.currentFrame() else { return }
        do {
            try gSession?.update(frame)
        } catch {
            Logger.error("Error updating GARSession: \(error.localizedDescription)")
        }
    }

    func createAnchor(_ token: UInt, _ transformPtr: UnsafeRawPointer, _ ttlDays: Int) {
        let localAnchorId = DeviceAR.instance.createAnchor(transformPtr)
        let localAnchor = DeviceAR.instance.getAnchor(localAnchorId)

        let anchorId = anchors.count
        anchors.append(GAnchorInfo())
        anchors[anchorId]!.token = token
        anchors[anchorId]!.localAnchorId = localAnchorId

        do {
            weak var weakSelf = self
            anchors[anchorId]!.hostFuture = try gSession.hostCloudAnchor(localAnchor!.anchor!, ttlDays: ttlDays,
                completionHandler: { cloudId, state in weakSelf?.onHostAnchor(token, cloudId, state, anchorId) })
        } catch {
            Logger.error("Failed to host cloud anchor: \(error.localizedDescription)")
            onHostAnchor(token, nil, .errorInternal, anchorId)
        }
    }

    func resolveAnchor(_ token: UInt, _ nativeId: String) {
        let anchorId = anchors.count
        anchors.append(GAnchorInfo())
        anchors[anchorId]!.token = token

        do {
            weak var weakSelf = self
            anchors[anchorId]!.resolveFuture = try gSession.resolveCloudAnchor(nativeId,
                completionHandler: { anchor, state in weakSelf?.onResolveAnchor(token, anchor, state, anchorId) })
        } catch {
            Logger.error("Failed to resolve cloud anchor: \(error.localizedDescription)")
            onResolveAnchor(token, nil, .errorInternal, anchorId)
        }
    }

    func removeAnchor(_ token: UInt, _ anchorId: Int) {
        if anchorId >= anchors.count {
            fatalError("Invalid local anchor id - out of bounds: \(anchorId)")
        }

        let index = anchorId >= 0 ? anchorId : anchors.firstIndex(where: {info in info?.token == token})
        if index == nil || index! < 0 {
            Logger.error("Failed to remove anchor: token \(token), anchorId \(anchorId), index \(String(describing: index))")
            return
        }

        if let future = anchors[index!]?.resolveFuture {
            future.cancel()
        }
        if let future = anchors[index!]?.hostFuture {
            future.cancel()
        }

        if anchors[index!]!.localAnchorId >= 0 {
            DeviceAR.instance.deleteAnchor(anchors[index!]!.localAnchorId)
        }

        if let cloudAnchor = anchors[index!]?.cloudAnchor {
            gSession.remove(cloudAnchor)
        }

        anchors[index!] = nil
    }

    func onHostAnchor(_ token: UInt, _ cloudId: String?, _ state: GARCloudAnchorState, _ anchorId: Int) {
        if anchorId >= anchors.count {
            fatalError("Invalid anchor id - out of bounds: \(anchorId)")
        }
        if anchors[anchorId] == nil {
            fatalError("onHostAnchor: nil anchor info, idx = \(anchorId)")
        }

        anchors[anchorId]!.hostFuture = nil
        CloudAnchorSession_onCreateAnchor(token, cloudAnchorStateToStr(state), cloudId != nil ? cloudId! : "", cloudId != nil ? anchorId : -1)

        if cloudId == nil {
            removeAnchor(token, anchorId)
        }
    }

    func onResolveAnchor(_ token: UInt, _ anchor: GARAnchor?, _ state: GARCloudAnchorState, _ anchorId: Int) {
        if anchorId >= anchors.count {
            fatalError("Invalid anchor id - out of bounds: \(anchorId)")
        }

        if anchors[anchorId] == nil {
            Logger.warn("Anchor resolved after removal [\(anchorId)]")
            if let anchor = anchor {
                gSession.remove(anchor)
            }
            return
        }

        anchors[anchorId]!.cloudAnchor = anchor
        CloudAnchorSession_onResolveAnchor(token, anchor != nil ? anchorId : -1, cloudAnchorStateToStr(state))

        if anchor == nil {
            removeAnchor(token, anchorId)
        }
    }

    func getAnchorTracking(_ anchorId: Int, _ outPtr: UnsafeMutableRawPointer) {
        if anchorId >= anchors.count {
            fatalError("Invalid anchor id - out of bounds")
        }

        if let cloudAnchor = anchors[anchorId]?.cloudAnchor {
            if cloudAnchor.trackingState == .tracking && cloudAnchor.hasValidTransform {
                var transform = cloudAnchor.transform
                TrackingResult_assign(outPtr, true, &transform)
            }
        } else if anchors[anchorId]!.localAnchorId >= 0 {
            DeviceAR.instance.getAnchorTracking(anchors[anchorId]!.localAnchorId, outPtr)
        }
    }

    func featureMapQuality() -> Int {
        guard let transform = DeviceAR.instance.currentFrame()?.camera.transform else {
            return Int(FEATURE_MAP_QUALITY_NONE)
        }
        do {
            let quality = try gSession.estimateFeatureMapQualityForHosting(transform)
            return featureMapQualityToCore(quality)
        } catch {
            return Int(FEATURE_MAP_QUALITY_NONE)
        }
    }
}
