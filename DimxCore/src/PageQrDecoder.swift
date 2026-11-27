import Foundation
import ImageIO
import WebKit
import DimxNative

/// The engine reads a QR code for the page's scanner (web-site's CodeScannerOverlay). The page
/// reads its camera's picture with the browser's own reader where there is one; an iPhone's web
/// view has none, so the page sends the middle of the picture here - a JPEG, as base64 - and the
/// engine's reader answers with the code's text (Vision_decodeQRCode: zxing-cpp, the reader
/// Android's Live View reads codes with). The camera stays the page's: this takes a picture the
/// page took and gives back the text in it.
///
/// A handler with a reply, so the page's `window.Native.decodeQrCode` (WebInterface.js) gets a
/// promise of `{text}` - null where the picture shows no code - and a rejection where the picture
/// could not be read. It takes the page's main frame alone, as the rest of the bridge does
/// (WebViewCtrl). The pictures are read one at a time on a queue of their own; the page waits for
/// each answer before it sends the next.
final class PageQrDecoder: NSObject, WKScriptMessageHandlerWithReply {

    /// The handler's name on the page: `window.webkit.messageHandlers.DimxQrDecode`.
    static let handlerName = "DimxQrDecode"

    /// The largest picture read, px a side, and the longest text it may come as - the page sends
    /// 1280 px at most (QrDecoder.ts); anything far beyond is not a scanner's picture.
    private static let maxSide = 4096
    private static let maxImageChars = 8 * 1024 * 1024
    /// Room for the longest text a QR code holds (2,953 bytes) and its terminating zero.
    private static let maxTextBytes = 4096

    private let queue = DispatchQueue(label: "com.dimx.page-qr-decoder", qos: .userInitiated)

    /// Why a picture could not be read, in the words the page's promise rejects with.
    struct ReadError: Error {
        let message: String
    }

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage,
                               replyHandler: @escaping (Any?, String?) -> Void) {
        guard message.frameInfo.isMainFrame, WebViewCtrl.isAppOrigin(message.frameInfo.securityOrigin.host) else {
            Logger.warn("PageQrDecoder: a picture from [\(message.frameInfo.securityOrigin.host)] refused - not the page's main frame")
            replyHandler(nil, "not the page's main frame")
            return
        }
        guard let body = message.body as? [String: Any], let image = body["image"] as? String,
              !image.isEmpty, image.utf8.count <= PageQrDecoder.maxImageChars else {
            replyHandler(nil, "no picture")
            return
        }
        queue.async {
            let answer = PageQrDecoder.read(base64: image)
            DispatchQueue.main.async {
                switch answer {
                case .success(let text):
                    replyHandler(["text": text.map { $0 as Any } ?? NSNull()], nil)
                case .failure(let error):
                    replyHandler(nil, error.message)
                }
            }
        }
    }

    /// The text of the QR code in a picture given as base64 (a JPEG, or anything ImageIO reads);
    /// nil where it shows none. The picture is drawn grey, one byte a pixel, which is what the
    /// engine's reader reads.
    static func read(base64: String) -> Result<String?, ReadError> {
        guard let data = Data(base64Encoded: base64, options: .ignoreUnknownCharacters) else {
            return .failure(ReadError(message: "the picture is not base64"))
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return .failure(ReadError(message: "the picture could not be decoded"))
        }
        let width = image.width
        let height = image.height
        guard width > 0, height > 0, width <= maxSide, height <= maxSide else {
            return .failure(ReadError(message: "the picture is \(width) by \(height) px"))
        }
        var gray = [UInt8](repeating: 0, count: width * height)
        let drawn: Bool = gray.withUnsafeMutableBytes { pixels in
            guard let context = CGContext(data: pixels.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
                return false
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else {
            return .failure(ReadError(message: "the picture could not be drawn grey"))
        }
        var text = [CChar](repeating: 0, count: maxTextBytes)
        let length = gray.withUnsafeBufferPointer { pixels in
            text.withUnsafeMutableBufferPointer { out in
                Int(Vision_decodeQRCode(pixels.baseAddress, Int32(width), Int32(height), Int32(width), out.baseAddress, Int32(out.count)))
            }
        }
        if length < 0 {
            return .failure(ReadError(message: "the code's text could not be taken"))
        }
        if length == 0 {
            return .success(nil)
        }
        return .success(String(decoding: text.prefix(length).map { UInt8(bitPattern: $0) }, as: UTF8.self))
    }
}
