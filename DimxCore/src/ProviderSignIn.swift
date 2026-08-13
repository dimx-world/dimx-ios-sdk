//
//  ProviderSignIn.swift
//  DimxCore
//
//  Copyright © 2026 Dimensions. All rights reserved.
//

import Foundation
import UIKit
import AuthenticationServices
import CryptoKit

// A credential obtained natively, shaped the way the web side expects it. The page turns
// it into a Firebase credential and calls signInWithCredential itself, so everything
// downstream - token refresh, backend LOGIN, account provisioning - is the browser path.
struct ProviderCredential {
    let providerId: String
    let idToken: String
    // Apple only. Firebase re-checks the token's nonce binding, so it needs the raw
    // string whose SHA-256 hash was sent in the request. Google uses no nonce.
    let rawNonce: String?
}

struct ProviderSignInError: Error {
    let message: String
    // Firebase-style code, passed through to the page. It reports auth/user-cancelled
    // quietly instead of as a failure.
    let code: String?

    static func cancelled() -> ProviderSignInError {
        return ProviderSignInError(message: "Sign-in was cancelled", code: "auth/user-cancelled")
    }
}

typealias ProviderSignInAnswer = (Result<ProviderCredential, ProviderSignInError>) -> Void

// Runs the identity providers the web view cannot run itself.
//
// Google refuses OAuth in an embedded user agent (disallowed_useragent) and has to go
// through a Safari-backed session; Apple requires native Sign in with Apple in App Store
// apps that offer other social logins. Both answer through a single callback into the
// page - see NATIVE_PROVIDER_SIGNIN.md on the web side for the contract.
final class ProviderSignIn {
    static let googleProviderId = "google.com"
    static let appleProviderId = "apple.com"

    static let shared = ProviderSignIn()

    private var currentFlow: AnyObject?
    private var currentRequest = 0

    // Providers this build runs itself. The page falls back to its own popup for anything
    // left out, so an unconfigured provider must not appear here.
    static func supportedProviders() -> [String] {
        var providers: [String] = []

        if googleClientId() != nil {
            providers.append(googleProviderId)
        } else {
            Logger.info("Native Google sign-in unavailable: no OAuth client id." +
                        " Add GoogleService-Info.plist or call AppConfig.setGoogleClientId()")
        }

        if Context.inst().appConfig().appleSignInEnabled() {
            providers.append(appleProviderId)
        }

        return providers
    }

    // Answers exactly once. The page holds a promise pending until the answer arrives, so
    // every path out of here has to reach the completion.
    func start(_ providerId: String,
               presentingIn controller: UIViewController,
               completion: @escaping ProviderSignInAnswer)
    {
        currentRequest += 1
        let request = currentRequest

        // Guards the two ways a completion can go wrong: called twice by a flow, or
        // called by a run the page has already given up on - it rejects the previous
        // promise itself when a new sign-in starts.
        let answer: ProviderSignInAnswer = { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self, self.currentRequest == request else {
                    return
                }
                self.currentFlow = nil
                completion(result)
            }
        }

        let anchor = controller.view.window ?? UIApplication.shared.keyWindow ?? UIWindow()

        switch providerId {
        case ProviderSignIn.appleProviderId:
            let flow = AppleSignInFlow(anchor: anchor)
            currentFlow = flow
            flow.start(answer)

        case ProviderSignIn.googleProviderId:
            guard let clientId = ProviderSignIn.googleClientId() else {
                answer(.failure(ProviderSignInError(
                    message: "Google sign-in is not configured in this app build", code: nil)))
                return
            }
            let flow = GoogleSignInFlow(clientId: clientId, anchor: anchor)
            currentFlow = flow
            flow.start(answer)

        default:
            answer(.failure(ProviderSignInError(
                message: "The app does not handle sign-in with \(providerId)", code: nil)))
        }
    }

    // The OAuth client the app authenticates as. Firebase accepts a Google ID token minted
    // for any OAuth client belonging to the same project, so the iOS client is what we use
    // - unlike Android, where Credential Manager needs the web client id explicitly. If the
    // page ever rejects the token as an unknown audience, add this client id under
    // "Whitelist client IDs" in the Firebase console's Google provider settings.
    static func googleClientId() -> String? {
        let configured = Context.inst().appConfig().googleClientId()
        if !configured.isEmpty {
            return configured
        }

        if let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
           let plist = NSDictionary(contentsOfFile: path),
           let clientId = plist["CLIENT_ID"] as? String, !clientId.isEmpty {
            return clientId
        }

        if let clientId = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String,
           !clientId.isEmpty {
            return clientId
        }

        return nil
    }

    // Google's redirect for an iOS client is the client id with its dot-separated parts
    // reversed: 123-abc.apps.googleusercontent.com -> com.googleusercontent.apps.123-abc.
    // ASWebAuthenticationSession claims the scheme for the life of the session, so unlike
    // the Google Sign-In SDK it needs no CFBundleURLTypes entry and no openURL plumbing.
    static func reversedClientId(_ clientId: String) -> String {
        return clientId.split(separator: ".").reversed().joined(separator: ".")
    }

    static func randomUrlSafeString(_ byteCount: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        if SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes) != errSecSuccess {
            Logger.error("SecRandomCopyBytes failed, falling back to UUIDs")
            return (UUID().uuidString + UUID().uuidString).replacingOccurrences(of: "-", with: "")
        }
        return base64Url(Data(bytes))
    }

    // Apple wants the nonce hash as hex.
    static func sha256Hex(_ input: String) -> String {
        return SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    // PKCE wants it base64url-encoded over the raw digest bytes.
    static func pkceChallenge(_ verifier: String) -> String {
        return base64Url(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    static func base64Url(_ data: Data) -> String {
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - Apple

private final class AppleSignInFlow: NSObject,
                                     ASAuthorizationControllerDelegate,
                                     ASAuthorizationControllerPresentationContextProviding
{
    private let anchor: ASPresentationAnchor
    // Generated up front: the request carries its SHA-256 hash, the page needs the raw
    // string. Sending the hash as rawNonce, or omitting it, fails Firebase's check with
    // an error that says nothing about nonces.
    private let rawNonce = ProviderSignIn.randomUrlSafeString()
    private var answer: ProviderSignInAnswer?

    init(anchor: ASPresentationAnchor) {
        self.anchor = anchor
    }

    func start(_ answer: @escaping ProviderSignInAnswer) {
        self.answer = answer

        let request = ASAuthorizationAppleIDProvider().createRequest()
        // Apple releases these only on the first authorization, and only if asked.
        request.requestedScopes = [.fullName, .email]
        request.nonce = ProviderSignIn.sha256Hex(rawNonce)

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }

    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithAuthorization authorization: ASAuthorization)
    {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            answer?(.failure(ProviderSignInError(
                message: "Apple sign-in returned an unexpected credential", code: nil)))
            return
        }

        guard let tokenData = credential.identityToken,
              let idToken = String(data: tokenData, encoding: .utf8) else {
            answer?(.failure(ProviderSignInError(
                message: "Apple sign-in returned no identity token", code: nil)))
            return
        }

        Logger.info("Apple sign-in succeeded for user \(credential.user)")
        answer?(.success(ProviderCredential(providerId: ProviderSignIn.appleProviderId,
                                            idToken: idToken,
                                            rawNonce: rawNonce)))
    }

    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithError error: Error)
    {
        if let authError = error as? ASAuthorizationError, authError.code == .canceled {
            Logger.info("Apple sign-in cancelled")
            answer?(.failure(.cancelled()))
            return
        }

        Logger.error("Apple sign-in failed: \(error)")
        answer?(.failure(ProviderSignInError(
            message: "Apple sign-in failed: \(error.localizedDescription)", code: nil)))
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        return anchor
    }
}

// MARK: - Google

// Authorization code flow with PKCE against Google, run in an ASWebAuthenticationSession.
// That session is Safari-backed, which is exactly what Google's policy requires - the same
// flow in the app's own web view is refused with disallowed_useragent.
private final class GoogleSignInFlow: NSObject, ASWebAuthenticationPresentationContextProviding {
    private static let authEndpoint = "https://accounts.google.com/o/oauth2/v2/auth"
    private static let tokenEndpoint = "https://oauth2.googleapis.com/token"

    private let clientId: String
    private let redirectScheme: String
    private let anchor: ASPresentationAnchor
    private let codeVerifier = ProviderSignIn.randomUrlSafeString()
    private let state = ProviderSignIn.randomUrlSafeString(16)
    private var session: ASWebAuthenticationSession?

    init(clientId: String, anchor: ASPresentationAnchor) {
        self.clientId = clientId
        self.redirectScheme = ProviderSignIn.reversedClientId(clientId)
        self.anchor = anchor
    }

    private var redirectUri: String {
        return "\(redirectScheme):/oauth2redirect"
    }

    func start(_ answer: @escaping ProviderSignInAnswer) {
        guard let url = authorizationUrl() else {
            answer(.failure(ProviderSignInError(
                message: "Could not build the Google sign-in url", code: nil)))
            return
        }

        let session = ASWebAuthenticationSession(url: url, callbackURLScheme: redirectScheme) {
            [weak self] callbackUrl, error in
            self?.onCallback(callbackUrl, error, answer)
        }
        session.presentationContextProvider = self
        // Non-ephemeral so an account already signed in to Safari is offered rather than
        // making the user type the password again.
        session.prefersEphemeralWebBrowserSession = false
        self.session = session

        if !session.start() {
            answer(.failure(ProviderSignInError(
                message: "Could not start the Google sign-in session", code: nil)))
        }
    }

    private func authorizationUrl() -> URL? {
        // No nonce: the page builds the Google credential from the ID token alone, and a
        // token carrying a nonce Firebase was never told about is rejected.
        var components = URLComponents(string: GoogleSignInFlow.authEndpoint)
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectUri),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "openid email profile"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: ProviderSignIn.pkceChallenge(codeVerifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        return components?.url
    }

    private func onCallback(_ callbackUrl: URL?, _ error: Error?, _ answer: @escaping ProviderSignInAnswer) {
        session = nil

        if let error = error {
            if let sessionError = error as? ASWebAuthenticationSessionError,
               sessionError.code == .canceledLogin {
                Logger.info("Google sign-in cancelled")
                answer(.failure(.cancelled()))
                return
            }
            Logger.error("Google sign-in failed: \(error)")
            answer(.failure(ProviderSignInError(
                message: "Google sign-in failed: \(error.localizedDescription)", code: nil)))
            return
        }

        guard let callbackUrl = callbackUrl,
              let items = URLComponents(url: callbackUrl, resolvingAgainstBaseURL: false)?.queryItems else {
            answer(.failure(ProviderSignInError(
                message: "Google sign-in returned no result", code: nil)))
            return
        }

        var values: [String: String] = [:]
        for item in items {
            values[item.name] = item.value
        }

        if let returned = values["error"] {
            // Declining on the consent screen comes back this way rather than as a
            // session error.
            if returned == "access_denied" {
                Logger.info("Google sign-in declined")
                answer(.failure(.cancelled()))
            } else {
                Logger.error("Google sign-in returned error: \(returned)")
                answer(.failure(ProviderSignInError(
                    message: "Google sign-in failed: \(returned)", code: nil)))
            }
            return
        }

        guard values["state"] == state else {
            answer(.failure(ProviderSignInError(
                message: "Google sign-in returned a mismatched state", code: nil)))
            return
        }

        guard let code = values["code"] else {
            answer(.failure(ProviderSignInError(
                message: "Google sign-in returned no authorization code", code: nil)))
            return
        }

        exchange(code, answer)
    }

    private func exchange(_ code: String, _ answer: @escaping ProviderSignInAnswer) {
        var request = URLRequest(url: URL(string: GoogleSignInFlow.tokenEndpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        // An iOS OAuth client is public - PKCE stands in for the secret there is none of.
        request.httpBody = GoogleSignInFlow.formEncoded([
            "client_id": clientId,
            "code": code,
            "code_verifier": codeVerifier,
            "grant_type": "authorization_code",
            "redirect_uri": redirectUri
        ]).data(using: .utf8)

        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error = error {
                Logger.error("Google token exchange failed: \(error)")
                answer(.failure(ProviderSignInError(
                    message: "Google token exchange failed: \(error.localizedDescription)", code: nil)))
                return
            }

            guard let data = data,
                  let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                answer(.failure(ProviderSignInError(
                    message: "Google token exchange returned an unreadable response", code: nil)))
                return
            }

            guard let idToken = json["id_token"] as? String else {
                let detail = json["error_description"] as? String
                    ?? json["error"] as? String
                    ?? "no id_token in the response"
                Logger.error("Google token exchange failed: \(detail)")
                answer(.failure(ProviderSignInError(
                    message: "Google token exchange failed: \(detail)", code: nil)))
                return
            }

            Logger.info("Google sign-in succeeded")
            answer(.success(ProviderCredential(providerId: ProviderSignIn.googleProviderId,
                                               idToken: idToken,
                                               rawNonce: nil)))
        }.resume()
    }

    // URLComponents leaves '+' and '/' unescaped in a query, and both change meaning in a
    // form body - authorization codes routinely contain '/'.
    private static func formEncoded(_ params: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return params.map { key, value in
            "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")"
        }.joined(separator: "&")
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return anchor
    }
}
