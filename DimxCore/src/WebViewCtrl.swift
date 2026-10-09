//
//  WebViewController.swift
//  dimx-ios-app
//
//  Created by Sergii Romanov on 24/07/2022.
//  Copyright © 2022 Dimensions. All rights reserved.
//

import UIKit
import WebKit
import Network
import DimxNative

class WebViewCtrl: UIViewController, WKUIDelegate, WKScriptMessageHandler, WKNavigationDelegate, UIAdaptivePresentationControllerDelegate {
    // Hosts that have to stay inside the web view. The Firebase auth handler lives on
    // firebaseapp.com while the app is served from dimx.world, so a rule written around
    // the app's own domain misses it - which is how the popup ended up in Safari, where
    // the credential had no opener to return to.
    //
    // The host the app is served from is deliberately absent: it is whatever
    // web_app_host says - app.dimx.world, or a development machine by its LAN address
    // when Cockpit points a debug build there - and shouldStayInWebView reads it from
    // the setting rather than from a list that would have to name one developer's
    // machine (as "sergei-laptop" once did here).
    static private let inAppHosts: Set<String> = [
        "dimx-world.firebaseapp.com",
        "dimx-world.web.app",
        "accounts.google.com",
        "appleid.apple.com",
        "www.youtube.com",
        "m.youtube.com",
        "localhost"
    ]

    //static private var startupAppUrl: String = ""
    var spinnerView: WKWebView!
    var webView: WKWebView!
    var firstTimeUrlLoad = true

    // The cover over the web view, up from the moment a page starts to load until the
    // page has its own content on screen. A web view shows nothing between its creation
    // and the page's first render - the document, the bundle, the bundle's run - and none
    // of what it reports marks that render: didCommit comes with the empty document,
    // didFinish with the load, both ahead of the content. So the page says when
    // (PAGE_READY, WebInterface.js), and announces in its document that it will
    // (window.__dimxPageReady), which is how a page that never says so - an older build
    // of the web app, any other site - is told apart and not waited for.
    //
    // For the first load the cover shows the host app's launch screen when the app names
    // it (AppConfig.setAppScreenSplash): the system shows that screen while the app
    // starts, and an app that opens on this screen goes from it to its page with the same
    // picture in between. A page loaded again later is covered plainly, with the spinner.
    private var coverView: UIView!
    private var launchScreenCtrl: UIViewController?
    private var coverUp = false
    private var coverRaisedAt = Date()
    private var coverGivenUp: DispatchWorkItem?
    private var pageGivenUp: DispatchWorkItem?
    private var spinnerLater: DispatchWorkItem?
    private var spinnerCentred: NSLayoutConstraint!
    private var spinnerLowered: NSLayoutConstraint!
    // A page that announced it would report is given this long after its document loaded...
    private static let coverAfterLoadSeconds = 4.0
    // ...and no page is covered for longer than this from the start of its load.
    private static let coverMaxSeconds = 12.0
    // Over the launch screen the spinner appears only when the load is taking long: a
    // launch that is quick goes from the picture to the page with nothing in between.
    private static let spinnerOverLaunchScreenAfterSeconds = 2.0
    private static let coverFadeSeconds = 0.18

    // Starting without a connection, as Android's WebActivity does it. The page is the web
    // app's, fetched from its host, and a start in a lift or a basement ended on an empty web
    // view. But the web view keeps a copy of the page and its files from the last time they
    // were fetched, and a page started from that copy is the app as it was left: it shows what
    // it read last and says it is reconnecting. So the page starts from the copy, every time
    // (loadPage) - at once, whatever the network is doing - and brings itself up to date: as it
    // starts it asks its host which build is current, and loads that when it is another one
    // (the page's BuildCheck; a reload of the page's own fetches the document from the host).
    // A copy that cannot do that - an older page, or one that did not start - is replaced from
    // the host as soon as it has loaded (documentLoaded). Only a page the web view has no copy
    // of - a first start offline - leaves the cover up with a message and a button under its
    // picture (showOfflinePanel), and that screen loads the page by itself once the network
    // is back.
    private var pageURL: URL?
    // The load under way fetches the document from its host rather than the copy, and has not
    // finished; what it is (the navigation WebKit answers for it) and whether it has arrived.
    private var loadFromHost = false
    private var loadUnderWay = false
    private var currentNavigation: WKNavigation?
    private var loadCommitted = false
    // Counts this screen's loads: what the page answers comes later, and an answer asked for
    // before the load under way began is not about it.
    private var loadGeneration = 0
    private var loadStall: DispatchWorkItem?
    private static let loadStallSeconds = 6.0
    // A load from the host failed, so a copy that cannot bring itself up to date is shown as it
    // is rather than sent to the host again - which would go back and forth between the two for
    // as long as the host does not answer. Cleared by a load from the host that arrives, and by
    // every try of the offline screen's.
    private var hostFailed = false
    // The device has a network (NWPathMonitor); taken as so until the monitor says otherwise.
    private let pathMonitor = NWPathMonitor()
    private var deviceOnline = true
    private var offlinePanel: UIView?
    private var offlineTitle: UILabel?
    private var offlineMessage: UILabel?
    private var offlineButton: UIButton?
    private var retryWork: DispatchWorkItem?
    // While the offline screen is up and the device has a network, the page is tried again
    // after this long, doubling up to the second.
    private static let retryFirstSeconds = 5.0
    private static let retryLastSeconds = 30.0
    private var retryDelay = retryFirstSeconds

    // Web views opened by window.open, kept alive while they are on screen.
    private var childWebViewCtrls: [ChildWebViewCtrl] = []

    // The web app's footer (--dx-light-grey-color), for the strip behind the home indicator.
    private static let footerColor = UIColor(red: 0xF7 / 255.0, green: 0xF7 / 255.0, blue: 0xF8 / 255.0, alpha: 1)

    // The status bar stays over this screen, dark on the white behind it whatever the
    // device's appearance: the default would turn it white in dark mode.
    override var prefersStatusBarHidden: Bool { false }
    override var preferredStatusBarStyle: UIStatusBarStyle { .darkContent }

    /// Shows the app at `url` - the app's own form, `https://go.dimx.world/...`, or empty for
    /// the page as it is (the way back from the AR screen). The first time the page is loaded
    /// at it; after that the page is asked to navigate there itself (DimxInterface.openAppUrl),
    /// keeping its state and its one history, and is loaded only when it cannot take the url -
    /// still loading, or from before it could.
    func loadWebUrl(_ url: String) {
        Logger.info("loadWebUrl: \(url)")

        if firstTimeUrlLoad {
            firstTimeUrlLoad = false
            var webUrl = Context.inst().convertAppUrlToWebUrl(url)
            if webUrl.isEmpty {
                webUrl = Context.inst().settings().webAppHost()
            }
            Logger.info("loadWebUrl: first load [\(webUrl)]")
            loadPage(URL(string: webUrl)!, fromHost: false)
            return
        }

        if url.isEmpty {
            let jscode =
                """
                if (window.DimxInterface && window.DimxInterface.reloadAccount) {
                    window.DimxInterface.reloadAccount();
                }
                """
            webView.evaluateJavaScript(jscode) {
                (_, error) in
                if error != nil {
                    Logger.error("JS CALL ERROR: \(String(describing: error))")
                }
            }
            return
        }

        let jscode = "window.DimxInterface && window.DimxInterface.openAppUrl ? window.DimxInterface.openAppUrl(" + WebViewCtrl.jsStringLiteral(url) + ") : false"
        webView.evaluateJavaScript(jscode) { [weak self] (result, error) in
            guard let self = self else { return }
            // A JavaScript boolean arrives as an NSNumber.
            let taken = (result as? NSNumber)?.boolValue ?? (result as? Bool ?? false)
            if error == nil && taken {
                Logger.info("loadWebUrl: the page took [\(url)]")
                return
            }
            let webUrl = Context.inst().convertAppUrlToWebUrl(url)
            Logger.info("loadWebUrl: the page could not take [\(url)] - loading [\(webUrl)]")
            if let target = URL(string: webUrl) {
                self.loadPage(target, fromHost: false)
            }
        }
    }
    
    override func loadView() {
        let containerView = UIView(frame: UIScreen.main.bounds)
        containerView.backgroundColor = .white
        
        let config = WKWebViewConfiguration()
        config.userContentController.add(self, name: "WebViewCtrl")

        //--- Inject AppInstanceId
        let appInstContent = "window.DIMX_APP_INSTANCE_ID = '\(Context.inst().settings().appInstanceId())'"
        let appInstScript = WKUserScript(source: appInstContent, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        config.userContentController.addUserScript(appInstScript)

        //--- Inject the providers this build signs in with natively.
        // At document start, like everything else here: the page decides whether it is
        // running in the app by reading 'Native' in window as its bundle loads.
        let providers = ProviderSignIn.supportedProviders().map { "'\($0)'" }.joined(separator: ", ")
        Logger.info("Native provider sign-in supports: [\(providers)]")
        let providersContent = "window.DIMX_NATIVE_SIGNIN_PROVIDERS = [\(providers)]"
        let providersScript = WKUserScript(source: providersContent, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        config.userContentController.addUserScript(providersScript)

        //--- Inject WebInterface
        let filepath = Bundle.module.path(forResource: "WebInterface", ofType: "js")!
        var scriptContent = ""
        do {
           scriptContent = try String(contentsOfFile: filepath)
        } catch {
            fatalError("Failed to load web user script from file!")
        }
        let script = WKUserScript(source: scriptContent, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        config.userContentController.addUserScript(script)
        
        //--- enable audio/video autoplay
        config.mediaTypesRequiringUserActionForPlayback = []
        //---

        // App-Bound Domains: with the host app's Info.plist naming the platform's domains
        // (WKAppBoundDomains) and the web view limited to them, WebKit exposes service
        // workers to the page - which is what lets the page open with no network, out of
        // the copy its worker keeps (web-site services/ServiceWorker.ts). Only while the
        // page's host is one of those domains: a development build loads the page from a
        // desk's address, which no domain names, and a limited web view refuses to go there.
        // The limit holds for the child web views too (window.open), which is why the sign-in
        // hosts the popup flow visits are in the list beside the platform's.
        let webAppHost = WebViewCtrl.webAppHostName()
        if WebViewCtrl.appBoundDomainsCover(host: webAppHost) {
            config.limitsNavigationsToAppBoundDomains = true
            Logger.info("WebViewCtrl: the web view is limited to the app-bound domains (service workers on)")
        } else {
            Logger.info("WebViewCtrl: the web view is not limited to app-bound domains - [\(webAppHost)] is not one of them, or the app names none")
        }

        webView = WKWebView(frame: containerView.bounds, configuration: config)
        webView.uiDelegate = self
        webView.navigationDelegate = self
        // The edge swipe is the page's one history - the page's and the dimension app's,
        // since the app's route is in the page's URL - so it steps back the way the
        // page's own arrow does. The page is one document; nothing else is ever loaded
        // over it (loadWebUrl), so the swipe cannot land on an older page.
        webView.allowsBackForwardNavigationGestures = true
        if #available(iOS 16.4, *) {
            webView.isInspectable = true
        } else {
            // Fallback on earlier versions
        }
        /*
         webView.scrollView.bounces = false
         webView.scrollView.alwaysBounceVertical = false
         webView.scrollView.alwaysBounceHorizontal = false
         */

        // The page lies between the status bar and the home indicator, as Android's
        // WebActivity lays it out within the system bars (fitsSystemWindows). Above and below
        // it is this screen's own: the container's white behind the status bar, under the
        // page's white header, and the footer's grey behind the home indicator, under the
        // page's footer. The cover and the spinner keep the whole screen - the cover carries
        // the launch screen, laid out on the whole screen as the system's own is, and a cover
        // the size of the page would move its picture at the hand-over.
        let bottomStrip = UIView()
        bottomStrip.backgroundColor = WebViewCtrl.footerColor
        bottomStrip.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(bottomStrip)
        webView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(webView)
        let safeArea = containerView.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: safeArea.topAnchor),
            webView.bottomAnchor.constraint(equalTo: safeArea.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor),
            bottomStrip.topAnchor.constraint(equalTo: safeArea.bottomAnchor),
            bottomStrip.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            bottomStrip.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            bottomStrip.trailingAnchor.constraint(equalTo: containerView.trailingAnchor)
        ])

        createCoverView(containerView)
        createSpinnerView(containerView)

        // What the device says of its network, as it changes.
        pathMonitor.pathUpdateHandler = { [weak self] path in
            self?.pathChanged(path.status == .satisfied)
        }
        pathMonitor.start(queue: .main)
        // Up before the first frame: the page's load starts once this screen is
        // presented, and the web view must not be seen empty in between.
        raiseCover()

        self.view = containerView
        
        NotificationCenter.default.addObserver(self, selector: #selector(appDidEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appWillEnterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        //loadAppUrl(WebViewCtrl.startupAppUrl)
/*
        webView.scrollView.bounces = false
        webView.scrollView.alwaysBounceVertical = false
        webView.scrollView.alwaysBounceHorizontal = false
        if #available(iOS 17.4, *) {
            webView.scrollView.bouncesVertically = false
            webView.scrollView.bouncesHorizontally = false
        }
        webView.scrollView.bouncesZoom = false
*/
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        // The page's own main frame, and nothing else: the handler is reachable from every frame -
        // a dimension's app is someone else's code in one - and from the windows the page opens.
        guard message.frameInfo.isMainFrame, WebViewCtrl.isAppOrigin(message.frameInfo.securityOrigin.host) else {
            Logger.warn("WebViewCtrl: a bridge message from [\(message.frameInfo.securityOrigin.host)] refused - not the page's main frame")
            return
        }
        guard let params = message.body as? [String: AnyObject], let cmd = params["command"] as? String else {
            Logger.warn("WebViewCtrl: a bridge message that is no command refused")
            return
        }
        if (cmd == "SHOW_AR") {
            Context.inst().showARScreen(params["url"] as! String, params["settings"] as! String, params["account"] as! String)
            return
        } else if (cmd == "SET_WEB_APP_HOST") {
            Context.inst().settings().setWebAppHost(params["value"] as! String)
            return
        } else if (cmd == "REQUEST_TRACKING_STATUS") {
            let stringObj = String_create(UnsafeRawPointer(bitPattern: 0))
            getAnchorsTrackingStatus(params["dimension"] as! String, stringObj)
            let info = String(cString: String_cstr(stringObj))
            String_delete(stringObj)
            let jscode =
                """
                if (window.DimxInterface) {
                    if (window.DimxInterface.updateTrackingStatus) {
                        window.DimxInterface.updateTrackingStatus(JSON.parse('\(info)'))
                    } else {
                        console.error('FROM SWIFT: window.DimxInterface.updateTrackingStatus not defined')
                    }
                } else {
                    console.error('FROM SWIFT: window.DimxInterface not defined')
                }
                """;
            webView.evaluateJavaScript(jscode) {
                (_, error) in
                if error != nil {
                    Logger.error("JS CALL ERROR: \(String(describing: error))")
                }
            }
            return
        } else if (cmd == "REQUEST_GEOLOCATION_UPDATE") {
            requestGeolocationUpdate()
            return
        } else if (cmd == "REFRESH_NEARBY_BEACONS") {
            refreshNearbyBeacons()
            return
        } else if (cmd == "UPDATE_ACCOUNT") {
            guard let accountData = params["accountData"] as? String else { return }
            updateAccount(accountData)
            return
        } else if (cmd == "REQUEST_BEACON_STATUSES") {
            guard let uuid = params["uuid"] as? String else { return }
            requestBeaconStatuses(uuid)
            return
        } else if (cmd == "START_PROVIDER_SIGN_IN") {
            startProviderSignIn(params["providerId"] as! String)
            return
        } else if (cmd == "REQUEST_PERMISSIONS") {
            Context.inst().permissions().request(feature: params["feature"] as? String ?? "")
            return
        } else if (cmd == "SAVE_DIMENSION_OFFLINE") {
            Offline_saveDimension(params["dimension"] as? String ?? "")
            return
        } else if (cmd == "REMOVE_DIMENSION_OFFLINE") {
            Offline_removeDimension(params["dimension"] as? String ?? "", params["env"] as? String ?? "")
            return
        } else if (cmd == "REQUEST_OFFLINE_DIMENSIONS") {
            Offline_requestDimensions()
            return
        } else if (cmd == "SET_DIAGNOSTICS") {
            // The holder's switch from the page's Support block: the engine goes verbose for this many seconds.
            let seconds = (params["seconds"] as? NSNumber)?.doubleValue ?? 0
            Telemetry_setLocalPolicy(seconds)
            return
        } else if (cmd == "PAGE_READY") {
            // The page has its own content on screen.
            liftCover("ready, says")
            return
        }
        // A command this build does not know - a page newer than the app sends one it has
        // learnt since - is not the app's to die on.
        Logger.error("Unknown web command: [" + cmd + "]")
    }

    // MARK: - Telemetry

    /// What the engine says of this install ({app, version, platform, os, ...}); empty JSON before the engine runs.
    static func telemetryAppInfo() -> String {
        return nativeString { Telemetry_appInfoJson($0) }
    }

    /// The engine's diagnostics policy ({mode, until, server_time, set_by, revision}).
    static func telemetryPolicy() -> String {
        return nativeString { Telemetry_policyJson($0) }
    }

    private static func nativeString(_ fill: (UnsafeMutableRawPointer) -> Void) -> String {
        let stringObj = String_create(UnsafeRawPointer(bitPattern: 0))!
        fill(stringObj)
        let value = String(cString: String_cstr(stringObj))
        String_delete(stringObj)
        return value.isEmpty ? "{}" : value
    }

    /// A JSON text as a JavaScript string literal, so the page parses it itself.
    static func jsStringLiteral(_ text: String) -> String {
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
            .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
        return "'\(escaped)'"
    }

    /// The engine's policy changed (a push from the platform, or the holder's switch): the page hears it at once.
    func notifyTelemetryPolicy(_ policyJson: String) {
        tellPage("onTelemetryPolicy", policyJson)
    }

    /// A dimension being saved for offline use (the engine's OFFLINE_PROGRESS): the page shows it.
    func notifyOfflineProgress(_ json: String) {
        tellPage("onOfflineProgress", json)
    }

    /// The dimensions the engine keeps for offline use (OFFLINE_DIMENSIONS): the page keeps the list.
    func notifyOfflineDimensions(_ json: String) {
        tellPage("onOfflineDimensions", json)
    }

    /// Calls a method of the page's bridge with one JSON argument, when the page has one.
    private func tellPage(_ method: String, _ json: String) {
        guard webView != nil else { return }
        let jscode = "if (window.DimxInterface && window.DimxInterface.\(method)) { window.DimxInterface.\(method)(" + WebViewCtrl.jsStringLiteral(json) + ") }"
        webView.evaluateJavaScript(jscode) { (_, error) in
            if error != nil {
                Logger.error("JS CALL ERROR (\(method)): \(String(describing: error))")
            }
        }
    }

    func startProviderSignIn(_ providerId: String) {
        Logger.info("Starting native provider sign-in: \(providerId)")
        ProviderSignIn.shared.start(providerId, presentingIn: self) { [weak self] result in
            switch result {
            case .success(let credential):
                var payload: [String: Any] = [
                    "providerId": credential.providerId,
                    "idToken": credential.idToken
                ]
                if let rawNonce = credential.rawNonce {
                    payload["rawNonce"] = rawNonce
                }
                self?.sendProviderSignInResult(payload)

            case .failure(let error):
                Logger.error("Provider sign-in [\(providerId)] failed: \(error.message)")
                var payload: [String: Any] = [
                    "providerId": providerId,
                    "error": error.message
                ]
                if let code = error.code {
                    payload["code"] = code
                }
                self?.sendProviderSignInResult(payload)
            }
        }
    }

    // The page keeps a promise pending until this arrives, so it has to be sent for every
    // outcome - a silent failure leaves the sign-in button spinning for good.
    func sendProviderSignInResult(_ payload: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else {
            Logger.error("Failed to serialize provider sign-in result")
            return
        }

        let jscode =
            """
            if (window.DimxInterface && window.DimxInterface.onProviderSignInResult) {
                window.DimxInterface.onProviderSignInResult(\(json))
            } else {
                console.error('FROM SWIFT: window.DimxInterface.onProviderSignInResult not defined')
            }
            """;
        webView.evaluateJavaScript(jscode) {
            (_, error) in
            if error != nil {
                Logger.error("JS CALL ERROR: \(String(describing: error))")
            }
        }
    }

    func onsGeolocationUpdate(_ value: String) {
        let jscode =
            """
            if (window.DimxInterface) {
                if (window.DimxInterface.updateGeolocation) {
                    window.DimxInterface.updateGeolocation('\(value)')
                } else {
                    console.error('FROM SWIFT: window.DimxInterface.updateGeolocation not defined')
                }
            } else {
                console.error('FROM SWIFT: window.DimxInterface not defined')
            }
            """;
        webView.evaluateJavaScript(jscode) {
            (_, error) in
            if error != nil {
                Logger.error("JS CALL ERROR: \(String(describing: error))")
            }
        }
    }

    func updateBeaconStatuses(_ value: String) {
        guard let data = value.data(using: .utf8),
              let status = try? JSONSerialization.jsonObject(with: data),
              JSONSerialization.isValidJSONObject(status) else {
            Logger.error("Ignoring malformed beacon status from the engine")
            return
        }
        guard let webView = webView else {
            return
        }

        // WebKit marshals `status` into the page as an argument. No field is interpolated
        // into JavaScript source, so strings from the native boundary cannot alter the call.
        let script =
            """
            if (window.DimxInterface && typeof window.DimxInterface.updateBeaconStatuses === 'function') {
                window.DimxInterface.updateBeaconStatuses(status)
            }
            """
        webView.callAsyncJavaScript(script,
                                    arguments: ["status": status],
                                    in: nil,
                                    in: .page) { result in
            if case .failure(let error) = result {
                Logger.error("Beacon status JS call failed: \(error)")
            }
        }
    }
    
    func webView(_ webView: WKWebView,
                 runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping () -> Void)
    {
        let alertController = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alertController.addAction(UIAlertAction(title: "Ok", style: .default, handler: { (action) in
            completionHandler()
        }))
        presentPanel(alertController)
    }

    // These panels also serve the web views opened by window.open, which sit in a sheet
    // above this controller - presenting from self would fail while one is up.
    private func presentPanel(_ alertController: UIAlertController) {
        let presenter = topMostViewController() ?? self
        presenter.present(alertController, animated: true, completion: nil)
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (Bool) -> Void)
    {
/*
 Note: for preferredStyle: .actionSheet
        alertController.popoverPresentationController?.sourceView = self.view
        alertController.popoverPresentationController?.sourceRect = CGRect(x: 0, y: 0, width: 0, height: 0)
        alertController.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { (action) in
            completionHandler(false)
        }))
 */
        let alertController = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        
        alertController.addAction(UIAlertAction(title: "Ok", style: .default, handler: { (action) in
            completionHandler(true)
        }))
        alertController.addAction(UIAlertAction(title: "Cancel", style: .default, handler: { (action) in
            completionHandler(false)
        }))

        presentPanel(alertController)
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (String?) -> Void)
    {
        let alertController = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
        alertController.addTextField { (textField) in
            textField.text = defaultText
        }
        alertController.addAction(UIAlertAction(title: "Ok", style: .default, handler: { (action) in
            if let text = alertController.textFields?.first?.text {
                completionHandler(text)
            } else {
                completionHandler(defaultText)
            }
        }))
        alertController.addAction(UIAlertAction(title: "Cancel", style: .default, handler: { (action) in
            completionHandler(nil)
        }))
        presentPanel(alertController)
    }

    // WKUIDelegate method - window.open
    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView?
    {
        Logger.info("Opening child web view: \(String(describing: navigationAction.request.url))")

        // Built from the configuration WebKit handed us, which is what preserves the
        // opener relationship. A child made from a fresh configuration would complete
        // OAuth with no window.opener to post the credential back to.
        let childWebView = WKWebView(frame: .zero, configuration: configuration)
        childWebView.uiDelegate = self
        // Deliberately no navigation delegate: this controller's policy handler sends
        // unrecognised hosts to Safari, which would strand the popup mid-flow.
        if #available(iOS 16.4, *) {
            childWebView.isInspectable = true
        }

        let childCtrl = ChildWebViewCtrl(webView: childWebView) { [weak self] ctrl in
            self?.closeChildWebViewCtrl(ctrl)
        }
        childWebViewCtrls.append(childCtrl)
        present(childCtrl, animated: true)
        // After present(), which is when the presentation controller exists.
        childCtrl.presentationController?.delegate = self

        // WebKit loads the request into the returned view itself.
        return childWebView
    }

    // WKUIDelegate method - window.close, and what the Firebase auth handler calls once it
    // has delivered the credential to its opener.
    func webViewDidClose(_ webView: WKWebView) {
        Logger.info("Child web view asked to close")
        guard let childCtrl = childWebViewCtrls.first(where: { $0.childWebView === webView }) else {
            return
        }
        closeChildWebViewCtrl(childCtrl)
    }

    private func closeChildWebViewCtrl(_ childCtrl: ChildWebViewCtrl) {
        childCtrl.detach()
        childWebViewCtrls.removeAll { $0 === childCtrl }
        childCtrl.dismiss(animated: true)
    }

    // UIAdaptivePresentationControllerDelegate method - the child sheet swiped away.
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        guard let childCtrl = presentationController.presentedViewController as? ChildWebViewCtrl else {
            return
        }
        childCtrl.detach()
        childWebViewCtrls.removeAll { $0 === childCtrl }
    }

    // WKNavigationDelegate method
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {

        //Logger.info("navigationAction 0: \(String(describing: navigationAction.request.url?.absoluteString))")

        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }

        if url.absoluteString == "about:blank" {
            Logger.info("Allowing about:blank redirect")
            decisionHandler(.allow)
            return
        }

        guard let host = url.host else {
            // mailto:, tel: and friends have no host and are not ours to render.
            let scheme = url.scheme?.lowercased()
            if scheme == "http" || scheme == "https" {
                decisionHandler(.allow)
            } else {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
                decisionHandler(.cancel)
            }
            return
        }

        // A web view limited to the app-bound domains cannot go anywhere else: a link to another
        // host, even one kept in the web view otherwise, goes to the browser rather than failing.
        if WebViewCtrl.shouldStayInWebView(host) && (!webView.configuration.limitsNavigationsToAppBoundDomains || WebViewCtrl.appBoundDomainsCover(host: host)) {
            decisionHandler(.allow)
            return
        }

        Logger.info("Opening externally: \(url.absoluteString)")
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
        decisionHandler(.cancel)
    }

    static private func shouldStayInWebView(_ host: String) -> Bool {
        if inAppHosts.contains(host) {
            return true
        }
        // This app's own page, wherever it is served from - the one host that must
        // never leave the web view, and the one a list cannot know in advance.
        if host.lowercased() == webAppHostName() {
            return true
        }
        // Matched with contains("dimx.world") before, which both let through any host
        // merely mentioning the name and - the reason sign-in broke - missed
        // dimx-world.firebaseapp.com, where the hyphen makes it a different string.
        return host == "dimx.world" || host.hasSuffix(".dimx.world")
    }

    /// Whether a frame's host is this app's page: the host web_app_host points at, and no other -
    /// not the platform's other hosts either, since a dimension's app on the files host could put
    /// itself in the main frame with a tap.
    static private func isAppOrigin(_ host: String) -> Bool {
        let lowered = host.lowercased()
        return !lowered.isEmpty && lowered == webAppHostName()
    }

    /// The host of whatever web_app_host currently points at - this app's own page by
    /// definition. Repointing that setting is already what makes another host the app,
    /// so it is the setting that is read, the way android's WebActivity reads it.
    /// Empty when the setting is not a URL with a host, and then nothing matches it.
    static private func webAppHostName() -> String {
        return URL(string: Context.inst().settings().webAppHost())?.host?.lowercased() ?? ""
    }

    /// Whether the host app's WKAppBoundDomains (Info.plist) name this host: the domain
    /// itself, or one above it - WebKit reads every entry as a registrable domain, so
    /// `dimx.world` covers `app.dimx.world`. An address that is no domain - a desk's IP,
    /// localhost - is covered by nothing.
    static func appBoundDomainsCover(host: String) -> Bool {
        guard !host.isEmpty, let domains = Bundle.main.object(forInfoDictionaryKey: "WKAppBoundDomains") as? [String] else {
            return false
        }
        let lowered = host.lowercased()
        return domains.contains { entry in
            let domain = entry.lowercased().trimmingCharacters(in: .whitespaces)
            return !domain.isEmpty && (lowered == domain || lowered.hasSuffix("." + domain))
        }
    }

    /// The device's network came or went: the page hears it (DimxInterface.onNetworkChange),
    /// since a web view's own navigator.onLine is not always kept current; and the value is on
    /// the window for a page whose bridge is not up yet, which reads it as it starts.
    private func tellPageNetwork(_ online: Bool) {
        let script = "window.DIMX_NETWORK_ONLINE = \(online); if (window.DimxInterface && window.DimxInterface.onNetworkChange) { window.DimxInterface.onNetworkChange(\(online)); }"
        webView?.evaluateJavaScript(script) { _, _ in }
    }

    /// The spinner, over the cover and everything else, shown and hidden with it. It sits
    /// at the centre of a plain cover, and lower over a launch screen, clear of what that
    /// has at its centre.
    func createSpinnerView(_ containerView: UIView) {
        spinnerView = WKWebView(frame: containerView.bounds)
        spinnerView.isOpaque = false
        spinnerView.backgroundColor = .clear
        spinnerView.scrollView.backgroundColor = .clear
        spinnerView.translatesAutoresizingMaskIntoConstraints = false
        spinnerView.isUserInteractionEnabled = false
        spinnerView.isHidden = true
        containerView.addSubview(spinnerView)

        spinnerCentred = spinnerView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor)
        spinnerLowered = NSLayoutConstraint(item: spinnerView!, attribute: .centerY, relatedBy: .equal,
                                            toItem: containerView, attribute: .centerY, multiplier: 1.7, constant: 0)
        NSLayoutConstraint.activate([
            spinnerView.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            spinnerCentred,
            spinnerView.widthAnchor.constraint(equalToConstant: 100),
            spinnerView.heightAnchor.constraint(equalToConstant: 100)
        ])

        if let url = Bundle.module.url(forResource: "spinner", withExtension: "gif") {
            if let data = try? Data(contentsOf: url) {
                spinnerView.load(
                    data,
                    mimeType: "image/gif",
                    characterEncodingName: "utf-8",
                    baseURL: url.deletingLastPathComponent()
                )
            }
        }
        //Always on top of all subviews
        containerView.bringSubviewToFront(spinnerView)
    }

    private func showSpinner(lowered: Bool) {
        guard let spinner = spinnerView else { return }
        if lowered {
            NSLayoutConstraint.deactivate([spinnerCentred])
            NSLayoutConstraint.activate([spinnerLowered])
        } else {
            NSLayoutConstraint.deactivate([spinnerLowered])
            NSLayoutConstraint.activate([spinnerCentred])
        }
        spinner.isHidden = false
    }

    func hideSpinner() {
        spinnerView?.isHidden = true
    }

    /// The cover: a plain surface over the web view, and on it - for the first load -
    /// the host app's launch screen when it names one.
    func createCoverView(_ containerView: UIView) {
        let cover = UIView(frame: containerView.bounds)
        cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        cover.backgroundColor = .white
        if let launchScreen = WebViewCtrl.makeLaunchScreen() {
            launchScreen.view.frame = cover.bounds
            launchScreen.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            cover.addSubview(launchScreen.view)
            launchScreenCtrl = launchScreen
        }
        containerView.addSubview(cover)
        coverView = cover
    }

    /// The host app's launch screen - the storyboard it named with
    /// AppConfig.setAppScreenSplash, which is the one the system shows while the app
    /// starts - made again here, so that what covers the page is the picture already
    /// on screen. Nil when the app named none, or none by that name is in its bundle.
    private static func makeLaunchScreen() -> UIViewController? {
        let name = Context.inst().appConfig().appScreenSplash()
        if name.isEmpty {
            return nil
        }
        // UIStoryboard(name:) raises for a storyboard that is not in the bundle: ask the bundle first.
        if Bundle.main.path(forResource: name, ofType: "storyboardc") == nil {
            Logger.warn("WebViewCtrl: no storyboard [\(name)] in the app for the web screen's launch cover - a plain cover instead")
            return nil
        }
        return UIStoryboard(name: name, bundle: Bundle.main).instantiateInitialViewController()
    }

    private func later(_ seconds: Double, _ work: @escaping () -> Void) -> DispatchWorkItem {
        let item = DispatchWorkItem(block: work)
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: item)
        return item
    }

    /// Covers the web view: a page is about to load, or is loading again.
    private func raiseCover() {
        coverGivenUp?.cancel()
        pageGivenUp?.cancel()
        spinnerLater?.cancel()
        guard let cover = coverView else { return }
        cover.layer.removeAllAnimations()
        cover.alpha = 1
        cover.isHidden = false
        if !coverUp {
            coverUp = true
            coverRaisedAt = Date()
        }
        if offlinePanel != nil {
            // The offline screen's button says the page is being tried again.
            hideSpinner()
        } else if launchScreenCtrl != nil {
            hideSpinner()
            spinnerLater = later(WebViewCtrl.spinnerOverLaunchScreenAfterSeconds) { [weak self] in
                if self?.coverUp == true {
                    self?.showSpinner(lowered: true)
                }
            }
        } else {
            showSpinner(lowered: false)
        }
        coverGivenUp = later(WebViewCtrl.coverMaxSeconds) { [weak self] in
            self?.liftCover("given up on")
        }
    }

    /// Uncovers the web view, once per raise; `why` completes the log line "the cover came off: ... the page".
    private func liftCover(_ why: String) {
        if !coverUp {
            return
        }
        coverUp = false
        coverGivenUp?.cancel()
        pageGivenUp?.cancel()
        spinnerLater?.cancel()
        loadStall?.cancel()
        hideSpinner()
        hideOfflinePanel()
        let elapsed = Int(Date().timeIntervalSince(coverRaisedAt) * 1000)
        Logger.info("WebViewCtrl: the cover came off \(elapsed) ms after it went up: \(why) the page")
        guard let cover = coverView else { return }
        UIView.animate(withDuration: WebViewCtrl.coverFadeSeconds, delay: 0, options: [.curveEaseOut, .beginFromCurrentState]) {
            cover.alpha = 0
        } completion: { [weak self] _ in
            guard let self = self, !self.coverUp else { return }
            cover.isHidden = true
            // The launch screen was the launch's: a page loaded again later is covered plainly.
            self.launchScreenCtrl?.view.removeFromSuperview()
            self.launchScreenCtrl = nil
        }
    }

    /// The page's document has loaded. A page that announced it will say when it is ready
    /// (window.__dimxPageReady, set by the document itself before anything else runs) is
    /// waited for a little longer; one that has said so already, or never will, is shown.
    ///
    /// A page from the copy that cannot bring itself up to date - one without the page's build
    /// check (window.__dimxBuildCheck, set as its code starts), an older build or one whose code
    /// did not start because a file of it is gone from the copy - is loaded from the host instead
    /// when there is a network and the host has not just failed; otherwise it is shown as it is,
    /// unless it did not start, which is the offline screen.
    private func documentLoaded(_ navigation: WKNavigation!) {
        let ours = navigation === currentNavigation
        let fromCopy = ours && loadUnderWay && !loadFromHost
        if ours {
            loadUnderWay = false
        }
        let generation = loadGeneration
        webView.evaluateJavaScript("({ready: window.__dimxPageReady || null, updates: window.__dimxBuildCheck === true})") { [weak self] (result, _) in
            guard let self = self, generation == self.loadGeneration else { return }
            let page = result as? [String: Any]
            let state = page?["ready"] as? String
            let updates = (page?["updates"] as? NSNumber)?.boolValue ?? false
            if fromCopy && !updates, let url = self.pageURL {
                if self.deviceOnline && !self.hostFailed {
                    Logger.info("WebViewCtrl: the page from the copy cannot bring itself up to date - loading it from its host")
                    self.loadPage(url, fromHost: true)
                    return
                }
                if state == "pending" {
                    Logger.info("WebViewCtrl: the page from the copy did not start, and \(self.deviceOnline ? "its host cannot be reached" : "there is no network") - the offline screen")
                    self.showOfflinePanel()
                    return
                }
            }
            if ours {
                // The page is here: the offline screen's message is no longer so.
                self.hideOfflinePanel()
            }
            guard self.coverUp else { return }
            if state == "pending" {
                self.pageGivenUp?.cancel()
                self.pageGivenUp = self.later(WebViewCtrl.coverAfterLoadSeconds) { [weak self] in
                    self?.liftCover("given up on")
                }
            } else {
                self.liftCover(state == "ready" ? "ready, says" : "loaded, and nothing more will come from")
            }
        }
    }

    /// Loads the page in full. From the web view's copy - .returnCacheDataElseLoad, which WebKit
    /// hands on to every file the document brings while it loads: taken from the copy however
    /// old, fetched only when it holds none - unless fromHost asks for the host. Given
    /// loadStallSeconds to arrive; a failure goes on in pageLoadFailed.
    private func loadPage(_ url: URL, fromHost: Bool) {
        pageURL = url
        loadFromHost = fromHost
        loadUnderWay = true
        loadCommitted = false
        loadGeneration += 1
        Logger.info("WebViewCtrl: loading [\(url)] from \(loadFromHost ? "its host" : "the web view's copy")")
        raiseCover()
        let request = URLRequest(url: url, cachePolicy: loadFromHost ? .useProtocolCachePolicy : .returnCacheDataElseLoad)
        currentNavigation = webView.load(request)
        loadStall?.cancel()
        loadStall = later(WebViewCtrl.loadStallSeconds) { [weak self] in
            guard let self = self, self.loadUnderWay, !self.loadCommitted else { return }
            self.webView.stopLoading()
            self.pageLoadFailed("did not arrive within \(Int(WebViewCtrl.loadStallSeconds)) s")
        }
    }

    /// The page could not be had: the page in place when it was the host's (showPageInPlace),
    /// else the offline screen.
    private func pageLoadFailed(_ why: String) {
        loadStall?.cancel()
        loadUnderWay = false
        guard pageURL != nil else { return }
        if loadFromHost {
            hostFailed = true
            showPageInPlace(why)
            return
        }
        Logger.info("WebViewCtrl: the page \(why) - the offline screen")
        showOfflinePanel()
    }

    /// A load from the host that does not arrive leaves the page the web view showed in place and
    /// running: the page from the copy, which is shown as it is when it has started, and is the
    /// offline screen when it has not. It is not loaded from the copy again: WebKit takes a load of
    /// the address it shows from the network, whatever the request asks (FrameLoader takes it for
    /// the same page, and ignores the cache).
    private func showPageInPlace(_ why: String) {
        let generation = loadGeneration
        webView.evaluateJavaScript("({ready: window.__dimxPageReady || null, updates: window.__dimxBuildCheck === true})") { [weak self] (result, _) in
            guard let self = self, generation == self.loadGeneration else { return }
            let page = result as? [String: Any]
            let state = page?["ready"] as? String
            let updates = (page?["updates"] as? NSNumber)?.boolValue ?? false
            if state == "pending" && !updates {
                Logger.info("WebViewCtrl: the page \(why) from its host, and the page from the copy did not start - the offline screen")
                self.showOfflinePanel()
                return
            }
            Logger.info("WebViewCtrl: the page \(why) from its host - the page from the copy stays")
            self.hideOfflinePanel()
            self.liftCover("the host did not answer; kept")
        }
    }

    /// Says why there is no page, under the cover's picture - the launch screen at a launch,
    /// which stays up - with a button that tries again. The page is tried again by itself too:
    /// when the device comes back online (pathChanged), when the app returns to the foreground,
    /// and every so often while the device says it is online - the host may be what was missing.
    /// The cover stays until a page is up.
    private func showOfflinePanel() {
        coverGivenUp?.cancel()
        pageGivenUp?.cancel()
        spinnerLater?.cancel()
        hideSpinner()
        if let cover = coverView {
            cover.layer.removeAllAnimations()
            cover.alpha = 1
            cover.isHidden = false
            coverUp = true
        }
        if offlinePanel == nil {
            createOfflinePanel()
        }
        if let panel = offlinePanel {
            view.bringSubviewToFront(panel)
        }
        offlineTitle?.text = WebViewCtrl.offlineText(deviceOnline ? "unreachable_title" : "offline_title")
        offlineMessage?.text = WebViewCtrl.offlineText(deviceOnline ? "unreachable_message" : "offline_message")
        offlineButton?.isEnabled = true
        offlineButton?.configuration?.title = WebViewCtrl.offlineText("retry")
        retryWork?.cancel()
        if deviceOnline {
            retryWork = later(retryDelay) { [weak self] in
                self?.retryPage("trying again by itself")
            }
            retryDelay = min(retryDelay * 2, WebViewCtrl.retryLastSeconds)
        }
    }

    /// The offline screen's message and button, below the middle of the screen so the picture
    /// there stays where it was.
    private func createOfflinePanel() {
        let title = UILabel()
        title.font = .systemFont(ofSize: 18, weight: .semibold)
        title.textColor = UIColor(red: 0x1F / 255, green: 0x29 / 255, blue: 0x37 / 255, alpha: 1)
        title.textAlignment = .center
        title.numberOfLines = 0
        let message = UILabel()
        message.font = .systemFont(ofSize: 15)
        message.textColor = UIColor(red: 0x6B / 255, green: 0x72 / 255, blue: 0x80 / 255, alpha: 1)
        message.textAlignment = .center
        message.numberOfLines = 0
        // The web app's blue.
        var style = UIButton.Configuration.filled()
        style.baseBackgroundColor = UIColor(red: 0x23 / 255, green: 0x6A / 255, blue: 0xF6 / 255, alpha: 1)
        style.cornerStyle = .capsule
        style.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 28, bottom: 12, trailing: 28)
        let button = UIButton(configuration: style, primaryAction: UIAction { [weak self] _ in
            self?.retryPage("Try again")
        })
        let panel = UIStackView(arrangedSubviews: [title, message, button])
        panel.axis = .vertical
        panel.alignment = .center
        panel.spacing = 8
        panel.setCustomSpacing(20, after: message)
        panel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(panel)
        NSLayoutConstraint.activate([
            panel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            panel.topAnchor.constraint(equalTo: view.centerYAnchor, constant: 120),
            panel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
            panel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32),
            message.widthAnchor.constraint(lessThanOrEqualToConstant: 320)
        ])
        offlinePanel = panel
        offlineTitle = title
        offlineMessage = message
        offlineButton = button
    }

    private func hideOfflinePanel() {
        retryWork?.cancel()
        retryDelay = WebViewCtrl.retryFirstSeconds
        offlinePanel?.removeFromSuperview()
        offlinePanel = nil
        offlineTitle = nil
        offlineMessage = nil
        offlineButton = nil
    }

    /// Loads the page again; the offline screen stays, saying so, until the outcome.
    private func retryPage(_ why: String) {
        guard let url = pageURL else { return }
        Logger.info("WebViewCtrl: loading the page again (\(why))")
        retryWork?.cancel()
        hostFailed = false
        offlineButton?.isEnabled = false
        offlineButton?.configuration?.title = WebViewCtrl.offlineText("connecting")
        loadPage(url, fromHost: false)
    }

    private func pathChanged(_ online: Bool) {
        guard online != deviceOnline else { return }
        deviceOnline = online
        Logger.info("WebViewCtrl: the device is \(online ? "online" : "offline")")
        tellPageNetwork(online)
        guard offlinePanel != nil else { return }
        if online {
            retryDelay = WebViewCtrl.retryFirstSeconds
            retryPage("back online")
        } else if !loadUnderWay {
            // Says so, and stops trying by itself until the network is back.
            showOfflinePanel()
        }
    }

    /// The offline screen's words, in the web app's languages; English otherwise.
    private static func offlineText(_ key: String) -> String {
        let english = [
            "offline_title": "No internet connection",
            "offline_message": "The app opens by itself as soon as you're back online.",
            "unreachable_title": "Can't connect",
            "unreachable_message": "The server can't be reached right now. The app keeps trying by itself.",
            "retry": "Try again",
            "connecting": "Connecting…",
        ]
        let translations = [
            "ru": [
                "offline_title": "Нет подключения к интернету",
                "offline_message": "Приложение откроется само, как только появится подключение.",
                "unreachable_title": "Не удаётся подключиться",
                "unreachable_message": "Сервер сейчас недоступен. Приложение продолжает попытки само.",
                "retry": "Повторить",
                "connecting": "Подключение…",
            ],
            "he": [
                "offline_title": "אין חיבור לאינטרנט",
                "offline_message": "האפליקציה תיפתח מעצמה ברגע שהחיבור יחזור.",
                "unreachable_title": "לא ניתן להתחבר",
                "unreachable_message": "לא ניתן להגיע לשרת כרגע. האפליקציה ממשיכה לנסות מעצמה.",
                "retry": "נסו שוב",
                "connecting": "מתחבר…",
            ],
        ]
        var language = String(Locale.preferredLanguages.first?.prefix(2) ?? "en")
        if language == "iw" {
            language = "he"
        }
        return translations[language]?[key] ?? english[key] ?? key
    }

    /// A navigation that ended without failing: one this screen or the page replaced, or one the
    /// policy handler sent elsewhere.
    private static func isInterruption(_ error: Error) -> Bool {
        let error = error as NSError
        return (error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled)
            || (error.domain == "WebKitErrorDomain" && (error.code == 102 || error.code == 204))
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        Logger.info("WebView started loading: \(String(describing: webView.url))")
        raiseCover()
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        Logger.info("WebView committed loading: \(String(describing: webView.url))")
        if navigation === currentNavigation {
            loadCommitted = true
            loadStall?.cancel()
            if loadFromHost {
                hostFailed = false
            }
        }
        // The new document, before its bundle runs: what the device says of its network is
        // on the window for the page to read as it starts.
        tellPageNetwork(deviceOnline)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Logger.info("WebView finished loading: \(String(describing: webView.url))")
        documentLoaded(navigation)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error)
    {
        if WebViewCtrl.isInterruption(error) {
            return
        }
        Logger.error("WebView failed loading [\(String(describing: webView.url))]: \(error)")
        // The document came and the rest of it did not: what the web view shows is all there is.
        if navigation === currentNavigation {
            loadUnderWay = false
        }
        liftCover("the load failed for")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error)
    {
        if WebViewCtrl.isInterruption(error) {
            return
        }
        Logger.error("WebView failed provisional loading [\(String(describing: webView.url))]: \(error)")
        // A load of the page's own that fails leaves the page it had in place; one of this
        // screen's is the copy next, or the offline screen.
        guard navigation === currentNavigation else {
            liftCover("the load failed for")
            return
        }
        pageLoadFailed("failed to load (\(error.localizedDescription))")
    }

    func notifyWebViewHide() {
        let jscode =
            """
            if (window.DimxInterface) {
                window.DimxInterface.onWebViewHide()
            } else {
                console.error('FROM JAVA: window.DimxInterface not defined')
            }
            """;
        webView.evaluateJavaScript(jscode) {
            (_, error) in
            if error != nil {
                Logger.error("JS CALL ERROR: \(String(describing: error))")
            }
        }
    }

    func notifyWebViewShow() {
        let jscode =
            """
            if (window.DimxInterface) {
                window.DimxInterface.onWebViewShow()
            } else {
                console.error('FROM JAVA: window.DimxInterface not defined')
            }
            """;
        webView.evaluateJavaScript(jscode) {
            (_, error) in
            if error != nil {
                Logger.error("JS CALL ERROR: \(String(describing: error))")
            }
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        print("WebView will disappear")
        notifyWebViewHide()
        UIApplication.shared.isIdleTimerDisabled = false
    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        print("WebView will appear")
        notifyWebViewShow()
        UIApplication.shared.isIdleTimerDisabled = true
    }
/*
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        webView.frame = view.bounds
    }
*/
    @objc func appDidEnterBackground() {
        if view.window != nil {
            print("WebViewCtrl: app did enter background")
            notifyWebViewHide()
        }
    }
    
    @objc func appWillEnterForeground() {
        if view.window != nil {
            print("WebViewCtrl: app will enter foreground")
            notifyWebViewShow()
            // A return to the foreground is a moment to try again: the device may have moved
            // while it was away, and its network says nothing of a host that came back.
            if offlinePanel != nil {
                retryPage("back on the screen")
            }
        }
    }
}
