
class IOSNativeInterface
{

    showAR(url, settings, account)
    {
        window.webkit.messageHandlers.WebViewCtrl.postMessage({command: "SHOW_AR", url: url, settings: settings, account: account});
    }

    getAppInstanceId() {
        return window.DIMX_APP_INSTANCE_ID;
    }
    
    setWebAppHost(value) {
        window.webkit.messageHandlers.WebViewCtrl.postMessage({command: "SET_WEB_APP_HOST", value: value});
    }
    
    requestTrackingStatus(dimension) {
        window.webkit.messageHandlers.WebViewCtrl.postMessage({command: "REQUEST_TRACKING_STATUS", dimension: dimension});
    }
    
    requestGeolocationUpdate() {
        window.webkit.messageHandlers.WebViewCtrl.postMessage({command: "REQUEST_GEOLOCATION_UPDATE"});
    }

    // Synchronous by contract, so it cannot go through a message handler - those are
    // one-way. The list is injected at document start alongside this script and holds the
    // providers the app is actually configured to run; the page uses its own popup for
    // anything missing from it.
    canSignInWithProvider(providerId) {
        const providers = window.DIMX_NATIVE_SIGNIN_PROVIDERS;
        return Array.isArray(providers) && providers.indexOf(providerId) >= 0;
    }

    // Returns nothing: the result arrives later through
    // window.DimxInterface.onProviderSignInResult, exactly once per call.
    startProviderSignIn(providerId) {
        window.webkit.messageHandlers.WebViewCtrl.postMessage({command: "START_PROVIDER_SIGN_IN", providerId: providerId});
    }
} // class IOSNativeInterface

window.Native = new IOSNativeInterface()
