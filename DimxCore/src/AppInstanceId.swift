//
//  AppInstanceId.swift
//  DimxCore
//
//  The id that names this install of the app.
//

import Foundation
import UIKit

/**
 The id that names this install of the app. It is minted once, kept for as long
 as the app is installed, and reported on every telemetry record and in every
 DXTP header - which is what lets one device's lines be found together, and what
 the diagnostics policy rows are keyed by. Getting it wrong is not a missing
 answer but a wrong one, so the whole of the care is here rather than in
 AppSettings beside the ordinary settings.

 It is a file rather than a UserDefaults key for one reason: UserDefaults lives
 in the app container, which an iCloud or Finder backup captures whole and a
 restore replays onto the new device, and there is no way to keep one key out of
 it. A file can say isExcludedFromBackup, and a restored phone then arrives
 without one and mints its own - where before it would have carried the id of
 the phone it was restored from, two devices reporting as one install, one
 device's diagnostics policy turning both verbose, and two streams of lines
 merged in Loki under one id.

 The device it was minted on is kept beside it as a second guard, since whether
 the backup flag was honoured is not something this code can see:
 identifierForVendor is this vendor's id for this device, it is not carried by a
 backup, and a stored id whose companion disagrees with this device's was
 restored from another one.

 Nothing is minted over an id that might be there. A file that exists and cannot
 be read - which is what a launch before the device's first unlock after a
 reboot looks like, since the file is protected until then - gives this run a
 temporary id and leaves the file exactly as it is.

 The id deliberately ends with the install: the keychain, which would outlive an
 uninstall, is the usual suggestion here and the wrong one.
 */
final class AppInstanceId {

    private static let DIRECTORY_NAME = "world.dimx"
    private static let FILE_NAME = "app_instance_id.json"
    private static let ID_FIELD = "id"
    private static let DEVICE_FIELD = "minted_on_device"

    private var mId: String?
    private let mLock = NSLock()

    /// The install id. Resolved once per process; every caller after the first gets
    /// what the first one settled on, whichever thread asks.
    func id() -> String {
        mLock.lock()
        defer { mLock.unlock() }
        if let id = mId {
            return id
        }
        let id = resolve()
        mId = id
        return id
    }

    private func resolve() -> String {
        guard let file = fileUrl() else {
            let ephemeral = UUID().uuidString
            Logger.error("app_instance_id: no readable store, using a temporary id for this run: \(ephemeral)")
            return ephemeral
        }

        let device = deviceId()

        switch read(file) {
        case .unreadable:
            let ephemeral = UUID().uuidString
            Logger.error("app_instance_id: \(file.lastPathComponent) cannot be read - using a temporary id for this run: \(ephemeral)")
            return ephemeral

        case .stored(let id, let mintedOn):
            if device.isEmpty || mintedOn.isEmpty || mintedOn == device {
                if !device.isEmpty && mintedOn.isEmpty {
                    // Minted before the companion was recorded, or on a run where the
                    // device could not be read: this device owns it from here.
                    write(file, id: id, device: device)
                }
                Logger.info("Loaded existing app_instance_id: \(id)")
                return id
            }
            Logger.info("app_instance_id \(id) was minted on another device - minting a new one")

        case .absent:
            break
        }

        let minted = UUID().uuidString
        Logger.info("Generated new app_instance_id: \(minted)")
        write(file, id: minted, device: device)
        return minted
    }

    private enum Stored {
        case absent
        case unreadable
        case stored(id: String, mintedOn: String)
    }

    private func read(_ file: URL) -> Stored {
        if !FileManager.default.fileExists(atPath: file.path) {
            return .absent
        }
        do {
            let data = try Data(contentsOf: file)
            let fields = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let id = fields?[AppInstanceId.ID_FIELD] as? String ?? ""
            if id.isEmpty {
                // There, and says nothing: a write that was cut short. Mint into it.
                return .absent
            }
            return .stored(id: id, mintedOn: fields?[AppInstanceId.DEVICE_FIELD] as? String ?? "")
        } catch {
            // Protected until the first unlock, or damaged: either way not ours to
            // overwrite on the strength of a failed read.
            Logger.error("app_instance_id: reading \(file.lastPathComponent): \(error)")
            return .unreadable
        }
    }

    private func write(_ file: URL, id: String, device: String) {
        var fields: [String: Any] = [AppInstanceId.ID_FIELD: id]
        if !device.isEmpty {
            fields[AppInstanceId.DEVICE_FIELD] = device
        }
        do {
            let data = try JSONSerialization.data(withJSONObject: fields)
            try data.write(to: file, options: .atomic)
            try excludeFromBackup(file)
        } catch {
            Logger.error("app_instance_id: writing \(file.lastPathComponent): \(error)")
        }
    }

    /// The file's place in Application Support, created on the way; nil when it
    /// cannot be made, which leaves this run without a store rather than with a
    /// file somewhere else.
    private func fileUrl() -> URL? {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            Logger.error("app_instance_id: no application support directory")
            return nil
        }
        let directory = support.appendingPathComponent(AppInstanceId.DIRECTORY_NAME, isDirectory: true)
        do {
            // Application Support is not created for an app on iOS; this is the step
            // that makes it, and it is a no-op once it is there.
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            // The directory too, so anything that lands beside the id inherits it.
            try excludeFromBackup(directory)
        } catch {
            Logger.error("app_instance_id: preparing \(directory.path): \(error)")
            return nil
        }
        return directory.appendingPathComponent(AppInstanceId.FILE_NAME, isDirectory: false)
    }

    private func excludeFromBackup(_ url: URL) throws {
        var target = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try target.setResourceValues(values)
    }

    /// This device, as far as this app may know it; empty when there is none to
    /// read - which is what it is before the device's first unlock.
    private func deviceId() -> String {
        return UIDevice.current.identifierForVendor?.uuidString ?? ""
    }
}
