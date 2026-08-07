//
//  AnchorSession.swift
//  dimx-ios-app
//
//  Created by Sergii Romanov on 29/07/2022.
//  Copyright © 2022 Dimensions. All rights reserved.
//

import Foundation
import ARKit
import DimxNative

public func cloudAnchorStateToCore(_ stateValue: Int) -> Int {
    switch stateValue {
        case CloudAnchorState.taskInProgress: return Int(CLOUD_ANCHOR_STATE_IN_PROGRESS)
        case CloudAnchorState.success: return Int(CLOUD_ANCHOR_STATE_SUCCESS)
        case CloudAnchorState.errorInternal,
             CloudAnchorState.errorNotAuthorized,
             CloudAnchorState.errorResourceExhausted,
             CloudAnchorState.errorHostingDatasetProcessingFailed,
             CloudAnchorState.errorCloudIdNotFound,
             CloudAnchorState.errorResolvingSdkVersionTooOld,
             CloudAnchorState.errorResolvingSdkVersionTooNew,
             CloudAnchorState.errorHostingServiceUnavailable:
            return Int(CLOUD_ANCHOR_STATE_ERROR)
        case CloudAnchorState.none: return Int(CLOUD_ANCHOR_STATE_NONE)
        default: return Int(CLOUD_ANCHOR_STATE_NONE)
    }
}

public func cloudAnchorStateToStr(_ stateValue: Int) -> String {
    switch stateValue {
        case CloudAnchorState.taskInProgress:                       return "In Progress"
        case CloudAnchorState.success:                              return "Success"
        case CloudAnchorState.errorInternal:                        return "Internal Error"
        case CloudAnchorState.errorNotAuthorized:                   return "Not Authorized"
        case CloudAnchorState.errorResourceExhausted:               return "Resource Exhausted"
        case CloudAnchorState.errorHostingDatasetProcessingFailed:  return "Hosting Dataset Processing Failed"
        case CloudAnchorState.errorCloudIdNotFound:                 return "Cloud Id Not Found"
        case CloudAnchorState.errorResolvingSdkVersionTooOld:       return "Resolving Sdk Version Too Old"
        case CloudAnchorState.errorResolvingSdkVersionTooNew:       return "Resolving Sdk Version Too New"
        case CloudAnchorState.errorHostingServiceUnavailable:       return "Hosting Service Unavailable"
        case CloudAnchorState.none:                                 return "None"
        default:                                                    return "None"
    }
}

public func featureMapQualityToCore(_ qualityValue: Int) -> Int {
    switch qualityValue {
        case FeatureMapQuality.good:         return Int(FEATURE_MAP_QUALITY_GOOD)
        case FeatureMapQuality.insufficient: return Int(FEATURE_MAP_QUALITY_INSUFFICIENT)
        case FeatureMapQuality.sufficient:   return Int(FEATURE_MAP_QUALITY_SUFFICIENT)
        default:                             return Int(FEATURE_MAP_QUALITY_NONE)
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
    var cloudAnchor: AnyObject?
    var localAnchorId: Int = -1
    var hostFuture: AnyObject?
    var resolveFuture: AnyObject?
}

public class AnchorSession {
    let ARCORE_API_KEY = "AIzaSyC9CB2bvJ6iZN1YruOlc09-7nlMMB2NucA"
    public static let instance = AnchorSession()
    private var provider: CloudAnchorProvider?

    private var requiredProvider: CloudAnchorProvider {
        guard let provider = provider else {
            fatalError("No CloudAnchorProvider set - cloud anchors will not be available")
        }
        return provider
    }

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

    public func setProvider(_ provider: CloudAnchorProvider?) {
        self.provider = provider
    }

    func initialize() {
        if !requiredProvider.initialize(apiKey: ARCORE_API_KEY, bundleId: Bundle.main.bundleIdentifier) {
            fatalError("CloudAnchorProvider initialization failed")
        }
    }

    public func update() {
        guard let frame = DeviceAR.instance.currentFrame() else { return }
        requiredProvider.update(frame: frame)
    }

    func createAnchor(_ token: UInt, _ transformPtr: UnsafeRawPointer, _ ttlDays: Int) {
        let localAnchorId = DeviceAR.instance.createAnchor(transformPtr)
        let localAnchor = DeviceAR.instance.getAnchor(localAnchorId)

        let anchorId = anchors.count
        anchors.append(GAnchorInfo())
        anchors[anchorId]!.token = token
        anchors[anchorId]!.localAnchorId = localAnchorId

        weak var weakSelf = self
        anchors[anchorId]!.hostFuture = requiredProvider.hostCloudAnchor(localAnchor!.anchor!, ttlDays: ttlDays,
            completion: { cloudId, state in weakSelf?.onHostAnchor(token, cloudId, state, anchorId) })

        if anchors[anchorId]!.hostFuture == nil {
            Logger.error("Failed to host cloud anchor")
            onHostAnchor(token, nil, CloudAnchorState.errorInternal, anchorId)
        }
    }

    func resolveAnchor(_ token: UInt, _ nativeId: String) {
        let anchorId = anchors.count
        anchors.append(GAnchorInfo())
        anchors[anchorId]!.token = token

        weak var weakSelf = self
        anchors[anchorId]!.resolveFuture = requiredProvider.resolveCloudAnchor(nativeId,
            completion: { anchor, state in weakSelf?.onResolveAnchor(token, anchor, state, anchorId) })

        if anchors[anchorId]!.resolveFuture == nil {
            Logger.error("Failed to resolve cloud anchor")
            onResolveAnchor(token, nil, CloudAnchorState.errorInternal, anchorId)
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
            requiredProvider.cancelFuture(future)
        }
        if let future = anchors[index!]?.hostFuture {
            requiredProvider.cancelFuture(future)
        }

        if anchors[index!]!.localAnchorId >= 0 {
            DeviceAR.instance.deleteAnchor(anchors[index!]!.localAnchorId)
        }

        if let cloudAnchor = anchors[index!]?.cloudAnchor {
            requiredProvider.removeAnchor(cloudAnchor)
        }

        anchors[index!] = nil
    }

    func onHostAnchor(_ token: UInt, _ cloudId: String?, _ stateValue: Int, _ anchorId: Int) {
        if anchorId >= anchors.count {
            fatalError("Invalid anchor id - out of bounds: \(anchorId)")
        }
        if anchors[anchorId] == nil {
            fatalError("onHostAnchor: nil anchor info, idx = \(anchorId)")
        }

        anchors[anchorId]!.hostFuture = nil
        CloudAnchorSession_onCreateAnchor(token, cloudAnchorStateToStr(stateValue), cloudId != nil ? cloudId! : "", cloudId != nil ? anchorId : -1)

        if cloudId == nil {
            removeAnchor(token, anchorId)
        }
    }

    func onResolveAnchor(_ token: UInt, _ anchor: AnyObject?, _ stateValue: Int, _ anchorId: Int) {
        if anchorId >= anchors.count {
            fatalError("Invalid anchor id - out of bounds: \(anchorId)")
        }

        if anchors[anchorId] == nil {
            Logger.warn("Anchor resolved after removal [\(anchorId)]")
            if let anchor = anchor {
                requiredProvider.removeAnchor(anchor)
            }
            return
        }

        anchors[anchorId]!.cloudAnchor = anchor
        CloudAnchorSession_onResolveAnchor(token, anchor != nil ? anchorId : -1, cloudAnchorStateToStr(stateValue))

        if anchor == nil {
            removeAnchor(token, anchorId)
        }
    }

    func getAnchorTracking(_ anchorId: Int, _ outPtr: UnsafeMutableRawPointer) {
        if anchorId >= anchors.count {
            fatalError("Invalid anchor id - out of bounds")
        }

        if let cloudAnchor = anchors[anchorId]?.cloudAnchor,
           let result = requiredProvider.getTrackingResult(cloudAnchor),
           result.isTracking {
            var transform = result.transform
            TrackingResult_assign(outPtr, true, &transform)
        } else if anchors[anchorId]!.localAnchorId >= 0 {
            DeviceAR.instance.getAnchorTracking(anchors[anchorId]!.localAnchorId, outPtr)
        }
    }

    func featureMapQuality() -> Int {
        guard let transform = DeviceAR.instance.currentFrame()?.camera.transform else {
            return Int(FEATURE_MAP_QUALITY_NONE)
        }
        let quality = requiredProvider.estimateFeatureMapQuality(transform: transform)
        return featureMapQualityToCore(quality)
    }
}
