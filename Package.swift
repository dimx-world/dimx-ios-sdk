// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import Foundation
import PackageDescription

let coreVersion = "0.1.2-rc4"

// The engine: prebuilt xcframeworks - the ones the dimx-dev workspace builds
// into Libs/ (`./dev ios`) when that directory exists, the published dxcore
// archives otherwise. Libs/ is git-ignored and only the dev build creates it,
// so its presence is the declaration of intent: a standalone checkout
// resolves the published set. A Libs/ missing a framework fails in
// resolution, with SwiftPM naming the absent artifact - never a silent
// fallback to the published engine.
//
// The switch is read at resolution time, and an Xcode that has already
// resolved this package holds its answer for the whole session: the build
// that fills Libs/ touches this file (env/ios/build.sh), but a running Xcode
// does not necessarily look again. File > Packages > Reset Package Caches is
// not the cure either - it re-fetches what the graph in memory names, which
// is how a session that resolved the published dxcore downloads it again
// after Libs/ appeared. Quitting Xcode and reopening the project is what
// re-reads this file.

let packageDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
var libsIsDirectory: ObjCBool = false
let useLocalEngine = FileManager.default.fileExists(
    atPath: packageDir.appendingPathComponent("Libs").path,
    isDirectory: &libsIsDirectory) && libsIsDirectory.boolValue

let engineTargets: [Target]
if useLocalEngine {
    print("[DimxWorld] ENGINE: local xcframeworks from Libs/ (remove Libs/ to use the published dxcore \(coreVersion))")
    engineTargets = [
        .binaryTarget(name: "dimx-core", path: "Libs/dimx-core.xcframework"),
        .binaryTarget(name: "dimx-net", path: "Libs/dimx-net.xcframework"),
        .binaryTarget(name: "dimx-vision", path: "Libs/dimx-vision.xcframework"),
        .binaryTarget(name: "dxaudio", path: "Libs/dxaudio.xcframework"),
        .binaryTarget(name: "dxvideo", path: "Libs/dxvideo.xcframework"),
    ]
} else {
    print("[DimxWorld] ENGINE: published dxcore \(coreVersion) from dl.dimx.world (no Libs/ directory)")
    engineTargets = [
        .binaryTarget(name: "dimx-core", url: "https://dl.dimx.world/sdk/ios/dxcore/\(coreVersion)/dimx-core.xcframework.zip", checksum: "bee6f8ffdd82b8b171517cf25aa76acb8134e5d31f37bc943f0da0cb53ac41ed"),
        .binaryTarget(name: "dimx-net", url: "https://dl.dimx.world/sdk/ios/dxcore/\(coreVersion)/dimx-net.xcframework.zip", checksum: "b546ef2140367663dce9fdff9eb43fd03d393fd6f48178af715342157e162084"),
        .binaryTarget(name: "dimx-vision", url: "https://dl.dimx.world/sdk/ios/dxcore/\(coreVersion)/dimx-vision.xcframework.zip", checksum: "2988c7265191a26e87c386469ec53edd249568919cd64dbf66e7d5a5aaa73753"),
        .binaryTarget(name: "dxaudio", url: "https://dl.dimx.world/sdk/ios/dxcore/\(coreVersion)/dxaudio.xcframework.zip", checksum: "8a34acbcc5df7f3d92c41331f35587cd15546e06a9c59d4274a1579da0812058"),
        .binaryTarget(name: "dxvideo", url: "https://dl.dimx.world/sdk/ios/dxcore/\(coreVersion)/dxvideo.xcframework.zip", checksum: "ef5e2263b24254b47a2f0189702328b93bfb47070f46b0258adc579297df5250"),
    ]
}

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
    ],
    dependencies: [
        .package(url: "https://github.com/google-ar/arcore-ios-sdk", from: "1.54.0")
    ],
    targets: [
        .target(
            name: "DimxCore",
            dependencies: [
                "DimxNative",
                .product(name: "ARCoreGARSession", package: "arcore-ios-sdk"),
                .product(name: "ARCoreCloudAnchors", package: "arcore-ios-sdk"),
                .product(name: "ARCoreGeospatial", package: "arcore-ios-sdk"),
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
                "Jolt",
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

        .binaryTarget(name: "quickjspp", url: "https://dl.dimx.world/sdk/ios/quickjs/0.15.1/qjs.xcframework.zip", checksum: "8b45145b77941f6ad33696f394a0693db5f284a53bc26e8e2d10a3eeaf0445f0"),
        .binaryTarget(name: "jsoncpp", url: "https://dl.dimx.world/sdk/ios/jsoncpp/1.9.8/jsoncpp.xcframework.zip", checksum: "47df558f01eba46f31993bf1058a0c7d7d6f2b1cecc5b50b3c3ce6d1813685b5"),
        .binaryTarget(name: "zstd", url: "https://dl.dimx.world/sdk/ios/zstd/1.5.7/zstd.xcframework.zip", checksum: "65fbf1051fcc39a529d92bea0e66343bbb9dfe731620308060565b24fa31ae98"),
        .binaryTarget(name: "ZXing", url: "https://dl.dimx.world/sdk/ios/zxing-cpp/3.1.0/ZXing.xcframework.zip", checksum: "c8b548fa5f88b0ade9b42a404c44a97a8fa05375927c80d7f65c4cf1b5b28f96"),
        .binaryTarget(name: "ozz_animation", url: "https://dl.dimx.world/sdk/ios/ozz-animation/0.16.0/ozz_animation.xcframework.zip", checksum: "1fca6f3f71fecba9179c5ee14d3cc88025d6c99b52935f9ac2e443dc0838fe28"),
        .binaryTarget(name: "ozz_base", url: "https://dl.dimx.world/sdk/ios/ozz-animation/0.16.0/ozz_base.xcframework.zip", checksum: "d86aec830b505bb329c807661e63f16bef250420136f230a652c8912a3a0b745"),
        .binaryTarget(name: "openal-soft", url: "https://dl.dimx.world/sdk/ios/openal-soft/1.25.2/openal.xcframework.zip", checksum: "5064beb68823ebd2f16d52226c85e9687cff662ca5cd8b9fda292bc7029c07ba"),
        .binaryTarget(name: "yogacore", url: "https://dl.dimx.world/sdk/ios/yoga/3.2.1/yogacore.xcframework.zip", checksum: "af52dbe41b6e0bfa70c43f1408557728335a5867e212d042df2bc2ff2b287ab4"),
        .binaryTarget(name: "Jolt", url: "https://dl.dimx.world/sdk/ios/jolt-physics/5.6.0/Jolt.xcframework.zip", checksum: "cfccb80aa0281e0b613cd7a7b9a8a1c276e39fe2e4896b4da2cd901d20a2fbad"),
        .binaryTarget(name: "avcodec", url: "https://dl.dimx.world/sdk/ios/ffmpeg/9.0/avcodec.xcframework.zip", checksum: "50bf6a4e23ba44a32e22c7afa148319b1e2eafde601b7fc47735a4bfe569c098"),
        .binaryTarget(name: "avformat", url: "https://dl.dimx.world/sdk/ios/ffmpeg/9.0/avformat.xcframework.zip", checksum: "21130ca12bb15a6710db2fe100fee7383c59b230f21a2dc47f982b79583d4085"),
        .binaryTarget(name: "avutil", url: "https://dl.dimx.world/sdk/ios/ffmpeg/9.0/avutil.xcframework.zip", checksum: "fe319f0236e5ad03a8f1b6a3a8ba8fd5c332c7c8f267a27d497ffb3fc2a78b75"),
        .binaryTarget(name: "swresample", url: "https://dl.dimx.world/sdk/ios/ffmpeg/9.0/swresample.xcframework.zip", checksum: "8a982fa01b9efdcdf5b8a5294402516766376f52855976cde5cf7cbbf5c9edc7"),
        .binaryTarget(name: "swscale", url: "https://dl.dimx.world/sdk/ios/ffmpeg/9.0/swscale.xcframework.zip", checksum: "2f5dd92d026d25fa37c5ec1a62389301f94deaa9a546dc38a992132e177d2c3d"),
    ] + engineTargets,
    cxxLanguageStandard: .cxx2b
)
