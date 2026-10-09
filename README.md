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

## Using the SDK in an app

Add the package to the app (`https://github.com/dimx-world/dimx-ios-sdk.git`,
an exact version) and link the `DimxCore` product. Then, in the app target:

1. **iOS 16.4 or newer** as the deployment target - the SDK's floor.
2. **`-ObjC` in Other Linker Flags.** ARCore, which the SDK depends on, ships
   as static libraries whose Objective-C categories the linker drops unless
   the app links with `-ObjC`. Without it the app compiles, uploads and then
   dies at launch with an unrecognized selector such as
   `+[GARDeviceProfile profileForIdentifier:osVersion:configurationManager:]`.
3. **Purpose strings in Info.plist** for the camera
   (`NSCameraUsageDescription`), location when in use
   (`NSLocationWhenInUseUsageDescription`), the photo library
   (`NSPhotoLibraryUsageDescription`) and Bluetooth
   (`NSBluetoothAlwaysUsageDescription`). App Store Connect refuses a binary
   linking the SDK without them (ITMS-90683), by email.
4. **A real device** - the engine ships device-only binaries.
5. **`WKAppBoundDomains` in Info.plist, optionally**, for a web screen that opens
   with no network: an array of these domains - `dimx.world`, `dimx-world.firebaseapp.com`, `dimx-world.web.app`, `microsoftonline.com`, `live.com`, `microsoft.com`, `google.com`, `apple.com`, `youtube.com` (the
   platform's, the hosts the web screen keeps a link in, and where the page's
   Microsoft sign-in goes; WebKit takes ten at most). With the key present WebKit
   exposes service workers to the page, which keeps a copy of itself and starts
   from it offline; the SDK limits its web view to those domains while the page's
   host is one of them, and opens a link to any other host in the browser. The
   cost is Apple's rule for the key: script injection and message handlers -
   the SDK's bridge included - work on no page outside the list, in any web view
   of the app, so a development build pointed at a desk's address must not carry
   the key (the DimensionX app drops it from such a build in a script phase).
   A Microsoft work account whose sign-in goes through its company's own
   identity provider cannot finish inside the popup. Without the key the web
   screen works as before and starts offline from the web view's own cache when
   it still has the page.

Initialise once the window exists: `Context.initialize(window, AppConfig())`,
then `Context.inst().showARScreen(url, "", "", onDenied:)` and
`showWebScreen(url)`. The sample app in
[dimx-sdk-samples](https://github.com/dimx-world/dimx-sdk-samples) is the
smallest working project.

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

## When a build must update

Every connection the SDK opens begins by telling the platform what this
build is - app, version, build number and the protocol it speaks - and the
platform answers with its verdict on the build, if it has one. Nothing is
sent about the holder, and this happens whether or not telemetry is on.
Nothing waits for it either; the verdict arrives at the one handler the app sets:

```swift
Context.inst().clientUpdateHandler = { update in
    if update.isRequired { /* stop and say so */ }
    else if update.shouldPrompt() { /* a nudge, at your own pace */ update.markPrompted() }
}
```

`required` is a rare case: the platform has moved past this build. The SDK
refuses every request from then on (`E1003`), and `showARScreen` opens
nothing - it runs `onUpdateRequired:` when the app passed one, and shows its
own alert with the store link when it did not:

```swift
Context.inst().showARScreen(url, settings, account, onUpdateRequired: { update in
    // update.displayMessage, update.url - the store page, when the platform named one
})
```

`Context.updateStatus` says where the build stands at any time - `.unknown`
until the platform has answered on this run (offline, or not yet connected),
`.none`, `.advisory(update)`, `.required(update)` - and `Context.clientUpdate`
is the verdict itself, or nil. `DimxError.updateRequired(ClientUpdate)` is
the same verdict as an error, for code that would rather catch than listen.

## Telemetry

The engine can report to the DimensionX platform: a marker when a session
ends in a crash, its errors, session and frame-rate records - and, when the
platform's operators switch one install to verbose for a while, its full log
stream, ending on its own. It is off unless the app turns it on:

```swift
let appConfig = AppConfig()
appConfig.setTelemetryEnabled(true)            // reports as "ios-sdk"
Context.initialize(window, appConfig)
```

What is sent is tied to an install id the SDK mints (never a device
identifier) and the signed-in DimensionX account; the package's
`PrivacyInfo.xcprivacy` declares it. Nothing is sent while it is off.
