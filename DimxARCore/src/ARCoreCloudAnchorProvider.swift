//
//  ARCoreCloudAnchorProvider.swift
//  DimxARCore
//
//  Default CloudAnchorProvider implementation using ARCore SDK.
//  Used by regular (non-Flutter) apps that include DimxWorld via SPM.
//

import Foundation
import ARKit
import ARCoreGARSession
import ARCoreCloudAnchors
import DimxCore

public class ARCoreCloudAnchorProvider: CloudAnchorProvider {
    private var gSession: GARSession?

    public init() {}

    private func validateCloudAnchorStateMapping() {
        let mappings: [(name: String, core: Int, arcore: Int)] = [
            ("taskInProgress", CloudAnchorState.taskInProgress, GARCloudAnchorState.taskInProgress.rawValue),
            ("success", CloudAnchorState.success, GARCloudAnchorState.success.rawValue),
            ("errorInternal", CloudAnchorState.errorInternal, GARCloudAnchorState.errorInternal.rawValue),
            ("errorNotAuthorized", CloudAnchorState.errorNotAuthorized, GARCloudAnchorState.errorNotAuthorized.rawValue),
            ("errorResourceExhausted", CloudAnchorState.errorResourceExhausted, GARCloudAnchorState.errorResourceExhausted.rawValue),
            ("errorHostingDatasetProcessingFailed", CloudAnchorState.errorHostingDatasetProcessingFailed, GARCloudAnchorState.errorHostingDatasetProcessingFailed.rawValue),
            ("errorCloudIdNotFound", CloudAnchorState.errorCloudIdNotFound, GARCloudAnchorState.errorCloudIdNotFound.rawValue),
            ("errorResolvingSdkVersionTooOld", CloudAnchorState.errorResolvingSdkVersionTooOld, GARCloudAnchorState.errorResolvingSdkVersionTooOld.rawValue),
            ("errorResolvingSdkVersionTooNew", CloudAnchorState.errorResolvingSdkVersionTooNew, GARCloudAnchorState.errorResolvingSdkVersionTooNew.rawValue),
            ("errorHostingServiceUnavailable", CloudAnchorState.errorHostingServiceUnavailable, GARCloudAnchorState.errorHostingServiceUnavailable.rawValue),
            ("none", CloudAnchorState.none, GARCloudAnchorState.none.rawValue)
        ]

        var mismatches = [String]()
        for mapping in mappings where mapping.core != mapping.arcore {
            mismatches.append("\(mapping.name): core=\(mapping.core), arcore=\(mapping.arcore)")
        }

        if !mismatches.isEmpty {
            fatalError("[DimxARCore] CloudAnchorState mapping validation failed: \(mismatches.joined(separator: "; "))")
        }
    }

    private func validateFeatureMapQualityMapping() {
        let mappings: [(name: String, core: Int, arcore: Int)] = [
            ("insufficient", FeatureMapQuality.insufficient, GARFeatureMapQuality.insufficient.rawValue),
            ("sufficient", FeatureMapQuality.sufficient, GARFeatureMapQuality.sufficient.rawValue),
            ("good", FeatureMapQuality.good, GARFeatureMapQuality.good.rawValue)
        ]

        var mismatches = [String]()
        for mapping in mappings where mapping.core != mapping.arcore {
            mismatches.append("\(mapping.name): core=\(mapping.core), arcore=\(mapping.arcore)")
        }

        if !mismatches.isEmpty {
            fatalError("[DimxARCore] FeatureMapQuality mapping validation failed: \(mismatches.joined(separator: "; "))")
        }
    }

    public func initialize(apiKey: String, bundleId: String?) -> Bool {
        do {
            validateCloudAnchorStateMapping()
            validateFeatureMapQualityMapping()
            gSession = try GARSession(apiKey: apiKey, bundleIdentifier: bundleId)
            let config = GARSessionConfiguration()
            config.cloudAnchorMode = .enabled
            var error: NSError?
            gSession?.setConfiguration(config, error: &error)
            if let error = error {
                NSLog("[DimxARCore] Error setting GARSession configuration: \(error)")
                return false
            }
            return true
        } catch {
            NSLog("[DimxARCore] Error creating GARSession: \(error.localizedDescription)")
            return false
        }
    }

    public func update(frame: ARFrame) {
        do {
            try gSession?.update(frame)
        } catch {
            NSLog("[DimxARCore] Error updating GARSession: \(error.localizedDescription)")
        }
    }

    public func hostCloudAnchor(_ anchor: ARAnchor, ttlDays: Int,
                                completion: @escaping (_ cloudId: String?, _ state: Int) -> Void) -> AnyObject? {
        do {
            let future = try gSession?.hostCloudAnchor(anchor, ttlDays: ttlDays) { cloudId, state in
                completion(cloudId, state.rawValue)
            }
            return future
        } catch {
            NSLog("[DimxARCore] Failed to host cloud anchor: \(error.localizedDescription)")
            return nil
        }
    }

    public func resolveCloudAnchor(_ cloudId: String,
                                   completion: @escaping (_ anchor: AnyObject?, _ state: Int) -> Void) -> AnyObject? {
        do {
            let future = try gSession?.resolveCloudAnchor(cloudId) { anchor, state in
                completion(anchor, state.rawValue)
            }
            return future
        } catch {
            NSLog("[DimxARCore] Failed to resolve cloud anchor: \(error.localizedDescription)")
            return nil
        }
    }

    public func cancelFuture(_ future: AnyObject) {
        if let hostFuture = future as? GARHostCloudAnchorFuture {
            hostFuture.cancel()
        } else if let resolveFuture = future as? GARResolveCloudAnchorFuture {
            resolveFuture.cancel()
        }
    }

    public func removeAnchor(_ anchor: AnyObject) {
        if let garAnchor = anchor as? GARAnchor {
            gSession?.remove(garAnchor)
        }
    }

    public func getTrackingResult(_ anchor: AnyObject) -> CloudAnchorTrackingResult? {
        guard let garAnchor = anchor as? GARAnchor else { return nil }
        if garAnchor.trackingState == .tracking && garAnchor.hasValidTransform {
            return CloudAnchorTrackingResult(isTracking: true, transform: garAnchor.transform)
        }
        return nil
    }

    public func estimateFeatureMapQuality(transform: simd_float4x4) -> Int {
        do {
            let quality = try gSession?.estimateFeatureMapQualityForHosting(transform)
            return quality?.rawValue ?? FeatureMapQuality.insufficient
        } catch {
            return FeatureMapQuality.insufficient
        }
    }
}
