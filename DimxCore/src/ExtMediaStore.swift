//
//  ExtMediaStore.swift
//  DimxCore
//
//  The share sheet for what the engine captured (MediaCapture, SHARE_MEDIA):
//  the photo or the video out of the app's cache, with a text beside it - the
//  dimension and its link - and the photo library, where every capture the
//  shutter makes is put as it is made (SAVE_TO_GALLERY).
//

import Foundation
import UIKit
import Photos

class ExtMediaStore
{
    func shareMedia(_ viewCtrl: UIViewController, _ path: String, _ text: String) {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else {
            Logger.error("ExtMediaStore: nothing to share at [\(path)]")
            return
        }
        var items: [Any] = []
        if isVideoFile(path) {
            items.append(url)
        } else if let image = UIImage(contentsOfFile: path) {
            items.append(image)
        } else {
            items.append(url)
        }
        if !text.isEmpty {
            items.append(text)
        }
        let activityViewController = UIActivityViewController(activityItems: items, applicationActivities: nil)
        configurePopover(activityViewController, viewCtrl)
        viewCtrl.present(activityViewController, animated: true, completion: nil)
    }

    private func isVideoFile(_ filePath: String) -> Bool {
        return ExtMediaStore.isVideo(filePath)
    }

    private static func isVideo(_ filePath: String) -> Bool {
        return filePath.hasSuffix(".mp4") || filePath.hasSuffix(".mov")
    }

    // A capture into the photo library. The file is linked aside at once - the
    // engine drops its cache copy when the capture's tile goes, and the first
    // save waits for the user to answer the library's question. Adding is all
    // that is asked for (NSPhotoLibraryAddUsageDescription), full access the
    // fallback for a host app that declares only NSPhotoLibraryUsageDescription,
    // and nothing at all without either: asking without the purpose string
    // would end the app.
    static func saveToPhotos(_ path: String) {
        let source = URL(fileURLWithPath: path)
        let fileManager = FileManager.default
        let stagingDir = fileManager.temporaryDirectory.appendingPathComponent("gallery", isDirectory: true)
        try? fileManager.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        let staged = stagingDir.appendingPathComponent(UUID().uuidString + "." + source.pathExtension)
        do {
            try fileManager.linkItem(at: source, to: staged)
        } catch {
            do {
                try fileManager.copyItem(at: source, to: staged)
            } catch {
                Logger.error("ExtMediaStore: cannot set [\(path)] aside for the photo library: \(error.localizedDescription)")
                return
            }
        }

        let info = Bundle.main.infoDictionary ?? [:]
        let level: PHAccessLevel
        if info["NSPhotoLibraryAddUsageDescription"] != nil {
            level = .addOnly
        } else if info["NSPhotoLibraryUsageDescription"] != nil {
            level = .readWrite
        } else {
            Logger.error("ExtMediaStore: the app declares no photo library purpose string; [\(path)] stays out of Photos")
            try? fileManager.removeItem(at: staged)
            return
        }

        PHPhotoLibrary.requestAuthorization(for: level) { status in
            guard status == .authorized || status == .limited else {
                Logger.warn("ExtMediaStore: no access to the photo library (\(status.rawValue)); [\(path)] stays out of Photos")
                try? FileManager.default.removeItem(at: staged)
                return
            }
            PHPhotoLibrary.shared().performChanges({
                if isVideo(staged.path) {
                    _ = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: staged)
                } else {
                    _ = PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: staged)
                }
            }) { success, error in
                if success {
                    Logger.info("ExtMediaStore: saved to Photos [\(path)]")
                } else {
                    Logger.error("ExtMediaStore: Photos refused [\(path)]: \(error?.localizedDescription ?? "unknown error")")
                }
                try? FileManager.default.removeItem(at: staged)
            }
        }
    }

    private func configurePopover(_ activityViewController: UIActivityViewController, _ viewCtrl: UIViewController) {
        guard let popover = activityViewController.popoverPresentationController else {
            return
        }

        // Required for iPad and other popover presentations before presenting the share sheet.
        popover.sourceView = viewCtrl.view
        popover.sourceRect = CGRect(x: viewCtrl.view.bounds.midX,
                                    y: viewCtrl.view.bounds.midY,
                                    width: 0,
                                    height: 0)
        popover.permittedArrowDirections = []
    }
}
