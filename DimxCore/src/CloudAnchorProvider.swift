import Foundation
import ARKit

/// Tracking result for a cloud anchor
public struct CloudAnchorTrackingResult {
    public let isTracking: Bool
    public let transform: simd_float4x4

    public init(isTracking: Bool, transform: simd_float4x4) {
        self.isTracking = isTracking
        self.transform = transform
    }
}

/// Cloud anchor state raw values (mirrors GARCloudAnchorState)
public struct CloudAnchorState {
    public static let taskInProgress = 1
    public static let success = 2
    public static let errorInternal = -1
    public static let errorNotAuthorized = -2
    public static let errorResourceExhausted = -4
    public static let errorHostingDatasetProcessingFailed = -5
    public static let errorCloudIdNotFound = -6
    public static let errorResolvingSdkVersionTooOld = -8
    public static let errorResolvingSdkVersionTooNew = -9
    public static let errorHostingServiceUnavailable = -10
    public static let none = 0
}

/// Feature map quality raw values (mirrors GARFeatureMapQuality)
public struct FeatureMapQuality {
    public static let insufficient = 0
    public static let sufficient = 1
    public static let good = 2
}

/// Protocol that abstracts ARCore cloud anchor functionality.
/// For regular Swift apps: implement using ARCore directly (import ARCore).
/// For Flutter plugin: implement in the plugin layer where ARCore is available via CocoaPods.
public protocol CloudAnchorProvider: AnyObject {
    /// Initialize the cloud anchor session with the given API key and bundle ID.
    func initialize(apiKey: String, bundleId: String?) -> Bool

    /// Update the session with the current AR frame.
    func update(frame: ARFrame)

    /// Host a cloud anchor from the given local ARAnchor.
    /// Returns a cancellable future object (or nil on failure).
    /// Calls completion with (cloudId, CloudAnchorState raw value).
    func hostCloudAnchor(_ anchor: ARAnchor, ttlDays: Int,
                         completion: @escaping (_ cloudId: String?, _ state: Int) -> Void) -> AnyObject?

    /// Resolve a cloud anchor by its cloud identifier.
    /// Returns a cancellable future object (or nil on failure).
    /// Calls completion with (opaque anchor object, CloudAnchorState raw value).
    func resolveCloudAnchor(_ cloudId: String,
                            completion: @escaping (_ anchor: AnyObject?, _ state: Int) -> Void) -> AnyObject?

    /// Cancel a host/resolve future.
    func cancelFuture(_ future: AnyObject)

    /// Remove a cloud anchor from the session.
    func removeAnchor(_ anchor: AnyObject)

    /// Get tracking info for an opaque cloud anchor object.
    func getTrackingResult(_ anchor: AnyObject) -> CloudAnchorTrackingResult?

    /// Estimate feature map quality for hosting at the given camera transform.
    /// Returns a FeatureMapQuality raw value.
    func estimateFeatureMapQuality(transform: simd_float4x4) -> Int
}
