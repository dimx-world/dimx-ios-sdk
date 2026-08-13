//
//  WebViewController.swift
//  dimx-ios-app
//
//  Created by Sergii Romanov on 24/07/2022.
//  Copyright © 2022 Dimensions. All rights reserved.
//

import UIKit
import WebKit
import CoreLocation
import DimxNative

class WebViewCtrl: UIViewController, WKUIDelegate, WKScriptMessageHandler, WKNavigationDelegate, UIAdaptivePresentationControllerDelegate {
    // Hosts that have to stay inside the web view. The Firebase auth handler lives on
    // firebaseapp.com while the app is served from dimx.world, so a rule written around
    // the app's own domain misses it - which is how the popup ended up in Safari, where
    // the credential had no opener to return to.
    static private let inAppHosts: Set<String> = [
        "dimx-world.firebaseapp.com",
        "dimx-world.web.app",
        "accounts.google.com",
        "appleid.apple.com",
        "www.youtube.com",
        "m.youtube.com",
        "localhost",
        "sergei-laptop"
    ]

    //static private var startupAppUrl: String = ""
    var spinnerView: WKWebView!
    var webView: WKWebView!
    var versionReloaded = false
    var firstTimeUrlLoad = true

    // Web views opened by window.open, kept alive while they are on screen.
    private var childWebViewCtrls: [ChildWebViewCtrl] = []


    func loadWebUrl(_ url: String) {
        Logger.info("loadAppUrl: \(url)")
        var webUrl = Context.inst().convertAppUrlToWebUrl(url)
        Logger.info("loadAppUrl converted: \(webUrl)")
        
        if firstTimeUrlLoad {
            firstTimeUrlLoad = false
    
            if (webUrl.isEmpty) {
                webUrl = Context.inst().settings().webAppHost()
            }
            checkWebVersions()
        }

        if (!webUrl.isEmpty) {
            webView.load(URLRequest(url: URL(string: webUrl)!))
        } else {
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
        
        webView = WKWebView(frame: containerView.bounds, configuration: config)
        webView.uiDelegate = self
        webView.navigationDelegate = self
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
        
        containerView.addSubview(webView)
        
        createSpinnerView(containerView)
        
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
        let params = message.body as! [String: AnyObject]
        let cmd = params["command"] as! String
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
            if let loc = Context.inst().locationManager().location() {
                onsGeolocationUpdate(loc)
            }
            return
        } else if (cmd == "START_PROVIDER_SIGN_IN") {
            startProviderSignIn(params["providerId"] as! String)
            return
        }

        fatalError("Unknown web command: [" + cmd + "]")
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

    func onsGeolocationUpdate(_ loc: CLLocation) {
        let geoStr = "\(loc.coordinate.latitude) \(loc.coordinate.longitude) \(loc.altitude) \(loc.horizontalAccuracy) \(loc.verticalAccuracy)"
        let jscode =
            """
            if (window.DimxInterface) {
                if (window.DimxInterface.updateGeolocation) {
                    window.DimxInterface.updateGeolocation('\(geoStr)')
                } else {
                    console.error('FROM JAVA: window.DimxInterface.updateGeolocation not defined')
                }
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

        if WebViewCtrl.shouldStayInWebView(host) {
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
        // Matched with contains("dimx.world") before, which both let through any host
        // merely mentioning the name and - the reason sign-in broke - missed
        // dimx-world.firebaseapp.com, where the hyphen makes it a different string.
        return host == "dimx.world" || host.hasSuffix(".dimx.world")
    }

    func createSpinnerView(_ containerView: UIView) {
        spinnerView = WKWebView(frame: containerView.bounds)
        spinnerView.isOpaque = false
        spinnerView.backgroundColor = .clear
        spinnerView.scrollView.backgroundColor = .clear
        spinnerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(spinnerView)

        NSLayoutConstraint.activate([
            spinnerView.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            spinnerView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
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
    
    func hideSpinner() {
        guard let spinner = self.spinnerView, spinner.superview != nil else { return }
        self.spinnerView = nil
        
        UIView.animate(withDuration: 0.5, delay: 0, options: .curveEaseOut) {
            spinner.alpha = 0
        } completion: { _ in
            spinner.removeFromSuperview()
        }
    }
    
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        Logger.info("WebView started loading: \(String(describing: webView.url))")
    }
    
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        Logger.info("WebView committed loading: \(String(describing: webView.url))")
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Logger.info("WebView finished loading: \(String(describing: webView.url))")
        hideSpinner()
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error)
    {
        Logger.error("WebView failed loading [\(String(describing: webView.url))]: \(error)")
        hideSpinner()
    }
    
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error)
    {
        Logger.error("WebView failed provisional loading [\(String(describing: webView.url))]: \(error)")
        hideSpinner()
    }
    
    func checkWebVersions() {
        for versionUrl in Context.inst().appConfig().webVersions() {
            Logger.info("Checking web version: \(versionUrl)")
            
            guard let url = URL(string: versionUrl) else {
                Logger.info("Invalid version url: \(versionUrl)")
                return
            }
            
            let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData)
            let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
                guard let strongSelf = self else {
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse else {
                    return
                }
                
                if httpResponse.statusCode < 200 || httpResponse.statusCode > 299 {
                    Logger.info("Failed to fetch web version [\(versionUrl)]. Status code [\(httpResponse.statusCode)]")
                    return
                }
                
                if let data = data, let rawVersion = String(data: data, encoding: .utf8) {
                    let version = rawVersion.trimmingCharacters(in: .whitespacesAndNewlines)
                    if version.isEmpty {
                        Logger.info("Ignoring empty web version [\(versionUrl)]")
                        return
                    }

                    let cachedVersion = Context.inst().settings().getWebVersion(versionUrl)
                    let normalizedCachedVersion = cachedVersion?.trimmingCharacters(in: .whitespacesAndNewlines)
                    Logger.info("Web versions [\(versionUrl)] cached [\(String(describing: normalizedCachedVersion))] latest [\(version)]")

                    if version == normalizedCachedVersion {
                        return
                    }
                    Logger.info("Saving new web version [\(versionUrl)]: \(version)")
                    Context.inst().settings().setWebVersion(versionUrl, version)

                    if normalizedCachedVersion == nil {
                        return
                    }

                    Logger.info("Version changed [\(versionUrl)]. Requesting reload.")
                    DispatchQueue.main.async {
                        if !strongSelf.versionReloaded {
                            strongSelf.versionReloaded = true
                            
                            let websiteDataTypes = NSSet(array: [WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache])
                            let date = Date(timeIntervalSince1970: 0)
                            Logger.info("Cleaning web cache..")
                            WKWebsiteDataStore.default().removeData(ofTypes: websiteDataTypes as! Set<String>, modifiedSince: date, completionHandler: {
                                if strongSelf.webView.url != nil {
                                    Logger.info("Reloading url: \(String(describing: strongSelf.webView.url))")
                                    strongSelf.webView.load(URLRequest(url: strongSelf.webView.url!))
                                }
                            })
                        }
                    }
                }
            }
            
            task.resume()
        }
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
        }
    }
}
