// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import Foundation
import PackageDescription

let coreVersion = "0.0.2"

let package = Package(
    name: "DimxWorld",
    platforms: [
        .iOS("16.4")
    ],
    products: [
        .library(
            name: "DimxCore",
            targets: ["DimxCore"]
        ),
        .library(
            name: "DimxARCore",
            targets: ["DimxARCore"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/google-ar/arcore-ios-sdk", from: "1.54.0")
    ],
    targets: [
        .target(
            name: "DimxCore",
            dependencies: [
                "DimxNative"
                /* ARCore is optional and loaded dynamically at runtime */
            ],
            path: "DimxCore",
            resources: [
                .copy("src/WebInterface.js"),
                .copy("data"),
                .process("res")
            ]
        ),

        .target(
            name: "DimxNative",
            dependencies: [
                "dimx-core",
                "dimx-vision",
                "dimx-net",
                "dxaudio",
                "dxvideo",
                "quickjspp",
                "jsoncpp",
                "zstd",
                "ZXing",
                "ozz_animation",
                "ozz_base",
                "openal-soft",
                "yogacore",
                "avcodec",
                "avformat",
                "avutil",
                "swresample",
                "swscale"
            ],
            path: "DimxNative",
            sources: ["src"],
            publicHeadersPath: ".",
            cxxSettings: [
                .define("DIMX_PLATFORM_IOS")
            ],
            linkerSettings: [
//                .linkedFramework("CoreAudio"),
                .linkedFramework("VideoToolbox"),
                .linkedLibrary("bz2"),
                .linkedLibrary("z"),
                .linkedLibrary("iconv")
            ]
        ),
/*
        .binaryTarget(name: "dimx-core", path: "Libs/dimx-core.xcframework"),
        .binaryTarget(name: "dimx-net", path: "Libs/dimx-net.xcframework"),
        .binaryTarget(name: "dimx-vision", path: "Libs/dimx-vision.xcframework"),
        .binaryTarget(name: "dxaudio", path: "Libs/dxaudio.xcframework"),
        .binaryTarget(name: "dxvideo", path: "Libs/dxvideo.xcframework"),
*/
        .binaryTarget(name: "dimx-core", url: "https://dl.dimx.world/sdk/ios/dxcore/\(coreVersion)/dimx-core.xcframework.zip", checksum: "016cc756ffe8eb07a6d5fca4ef146efc62b39ef18340c5fab42aa9ad917e0ad1"),
        .binaryTarget(name: "dimx-net", url: "https://dl.dimx.world/sdk/ios/dxcore/\(coreVersion)/dimx-net.xcframework.zip", checksum: "62cace9643bdb33932e94b65d8a3bb96a3a00447718550bb1cc532e97299aed2"),
        .binaryTarget(name: "dimx-vision", url: "https://dl.dimx.world/sdk/ios/dxcore/\(coreVersion)/dimx-vision.xcframework.zip", checksum: "5f92f2255e65fe54cd7ae29abf461decfdd703f43511c8523949754e276c0738"),
        .binaryTarget(name: "dxaudio", url: "https://dl.dimx.world/sdk/ios/dxcore/\(coreVersion)/dxaudio.xcframework.zip", checksum: "99bcf0886ec9c90c9f7f249dcf5eff419f21c67df3481d9cc00e0cfa98505bcb"),
        .binaryTarget(name: "dxvideo", url: "https://dl.dimx.world/sdk/ios/dxcore/\(coreVersion)/dxvideo.xcframework.zip", checksum: "9b35d9d030e0307b2841d00d42743dbe5c255f913c0b07230a93828899be381c"),

        .binaryTarget(name: "quickjspp", url: "https://dl.dimx.world/sdk/ios/quickjs/0.15.1/qjs.xcframework.zip", checksum: "8b45145b77941f6ad33696f394a0693db5f284a53bc26e8e2d10a3eeaf0445f0"),
        .binaryTarget(name: "jsoncpp", url: "https://dl.dimx.world/sdk/ios/jsoncpp/1.9.8/jsoncpp.xcframework.zip", checksum: "47df558f01eba46f31993bf1058a0c7d7d6f2b1cecc5b50b3c3ce6d1813685b5"),
        .binaryTarget(name: "zstd", url: "https://dl.dimx.world/sdk/ios/zstd/1.5.7/zstd.xcframework.zip", checksum: "65fbf1051fcc39a529d92bea0e66343bbb9dfe731620308060565b24fa31ae98"),
        .binaryTarget(name: "ZXing", url: "https://dl.dimx.world/sdk/ios/zxing-cpp/3.1.0/ZXing.xcframework.zip", checksum: "c8b548fa5f88b0ade9b42a404c44a97a8fa05375927c80d7f65c4cf1b5b28f96"),
        .binaryTarget(name: "ozz_animation", url: "https://dl.dimx.world/sdk/ios/ozz-animation/0.16.0/ozz_animation.xcframework.zip", checksum: "1fca6f3f71fecba9179c5ee14d3cc88025d6c99b52935f9ac2e443dc0838fe28"),
        .binaryTarget(name: "ozz_base", url: "https://dl.dimx.world/sdk/ios/ozz-animation/0.16.0/ozz_base.xcframework.zip", checksum: "d86aec830b505bb329c807661e63f16bef250420136f230a652c8912a3a0b745"),
        .binaryTarget(name: "openal-soft", url: "https://dl.dimx.world/sdk/ios/openal-soft/1.25.2/openal.xcframework.zip", checksum: "5064beb68823ebd2f16d52226c85e9687cff662ca5cd8b9fda292bc7029c07ba"),
        .binaryTarget(name: "yogacore", url: "https://dl.dimx.world/sdk/ios/yoga/3.2.1/yogacore.xcframework.zip", checksum: "af52dbe41b6e0bfa70c43f1408557728335a5867e212d042df2bc2ff2b287ab4"),
        .binaryTarget(name: "avcodec", url: "https://dl.dimx.world/sdk/ios/ffmpeg/9.0/avcodec.xcframework.zip", checksum: "50bf6a4e23ba44a32e22c7afa148319b1e2eafde601b7fc47735a4bfe569c098"),
        .binaryTarget(name: "avformat", url: "https://dl.dimx.world/sdk/ios/ffmpeg/9.0/avformat.xcframework.zip", checksum: "21130ca12bb15a6710db2fe100fee7383c59b230f21a2dc47f982b79583d4085"),
        .binaryTarget(name: "avutil", url: "https://dl.dimx.world/sdk/ios/ffmpeg/9.0/avutil.xcframework.zip", checksum: "fe319f0236e5ad03a8f1b6a3a8ba8fd5c332c7c8f267a27d497ffb3fc2a78b75"),
        .binaryTarget(name: "swresample", url: "https://dl.dimx.world/sdk/ios/ffmpeg/9.0/swresample.xcframework.zip", checksum: "8a982fa01b9efdcdf5b8a5294402516766376f52855976cde5cf7cbbf5c9edc7"),
        .binaryTarget(name: "swscale", url: "https://dl.dimx.world/sdk/ios/ffmpeg/9.0/swscale.xcframework.zip", checksum: "2f5dd92d026d25fa37c5ec1a62389301f94deaa9a546dc38a992132e177d2c3d"),

        .target(
            name: "DimxARCore",
            dependencies: [
                "DimxCore",
                .product(name: "ARCoreGARSession", package: "arcore-ios-sdk"),
                .product(name: "ARCoreCloudAnchors", package: "arcore-ios-sdk"),
                .product(name: "ARCoreGeospatial", package: "arcore-ios-sdk"),
            ],
            path: "DimxARCore",
            sources: ["src"]
        ),
    ],
    cxxLanguageStandard: .cxx2b
)
