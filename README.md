# DimxWorld

The DimX iOS SDK: a Swift package wrapping the DimX engine.

Everything native is a prebuilt xcframework downloaded from the DimX release
server, so a plain checkout builds without any extra setup:

```
https://dl.dimx.world/sdk/ios/<lib>/<version>/<Framework>.xcframework.zip
```

* `dxcore` - the DimX engine (`dimx-core`, `dimx-core-headers`, `dimx-net`,
  `dimx-vision`, `dxaudio`, `dxvideo`), published from the `ios-dev` workspace
  with `ios-app/publish_core_frameworks.sh`.
* the third party libraries (ffmpeg, openal, quickjs, yoga, zstd, ZXing, ozz,
  jsoncpp), built and published from the `external-libs-dev` workspace with
  `scripts/publish_frameworks.sh`.

Both publishing scripts print the `.binaryTarget` lines - including the checksum
of the archive they uploaded - that belong in `Package.swift`. The third party
lines are pasted in by hand; for `dxcore`, `publish_core_frameworks.sh` updates
`coreVersion` and the six checksums in place (the urls interpolate `coreVersion`).

## Working on the engine

Inside the `ios-dev` workspace the package can be pointed at the engine built
there instead of the published archives. Both scripts are run by hand:

```
ios-dev/scripts/build_core.sh          # -> install/nativecore/frameworks
ios-dev/scripts/sync_libs_to_sdk.sh    # -> Libs/*.xcframework (git-ignored)
```

The frameworks have to be copied into `Libs/` rather than referenced in place,
because SwiftPM rejects a binaryTarget `path:` outside the package root.

`Package.swift` carries both sets of `dxcore` targets, one of them commented out
- move the `/*` and `//*` to switch:

```swift
//*                                      <- active block
        .binaryTarget(name: "dimx-core", path: "Libs/dimx-core.xcframework"),
        ...
//*/
/*                                       <- commented out block
        .binaryTarget(name: "dimx-core", url: "...\(coreVersion)/dimx-core.xcframework.zip", checksum: "..."),
        ...
*/
```

The package is committed with the published archives active. Editing
`Package.swift` makes SwiftPM re-resolve on its own; if Xcode still shows the
previous frameworks, use *File > Packages > Reset Package Caches*.

## Troubleshooting

Error: `the path does not point to a valid library: .../libdimx-core.a` - delete
the `CONFIGURATION_BUILD_DIR` parameter in the build settings. It should be used
from the project, not from a specific target.

