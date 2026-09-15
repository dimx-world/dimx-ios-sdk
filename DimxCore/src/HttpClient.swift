//
//  HttpClient.swift
//  DimxCore
//
//  The platform's HTTP for what the engine has to send or fetch outside its
//  socket - today the telemetry batches (Context.initEngineCallbacks). One
//  URLSession, the platform's own stack underneath (system trust, proxy,
//  backgrounding), so the engine carries no HTTP or TLS of its own.
//
//  A Request is the method, the url, the headers and the body; send answers
//  with the Response or the error on the session's queue, and post is the
//  fire-and-forget form that only logs. Nothing retries and nothing queues:
//  a caller that needs either does it above this.
//

import Foundation

final class HttpClient {
    struct Request {
        var method = "GET"
        let url: URL
        var headers: [String: String] = [:]
        var body: Data?

        static func post(_ url: URL, contentType: String, body: String) -> Request {
            Request(method: "POST", url: url, headers: ["Content-Type": contentType], body: body.data(using: .utf8))
        }
    }

    struct Response {
        let status: Int
        let body: Data

        var ok: Bool { (200..<300).contains(status) }
    }

    static let shared = HttpClient()

    private let session: URLSession

    private init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration)
    }

    /// Sends off the calling thread; the completion runs on the session's queue, once.
    func send(_ request: Request, completion: ((Result<Response, Error>) -> Void)? = nil) {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method
        for (name, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }
        urlRequest.httpBody = request.body
        session.dataTask(with: urlRequest) { data, response, error in
            if let error = error {
                completion?(.failure(error))
            } else {
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                completion?(.success(Response(status: status, body: data ?? Data())))
            }
        }.resume()
    }

    /// Fire and forget: a failure or an answer outside 2xx is one log line.
    func post(_ url: String, contentType: String, body: String) {
        guard let parsed = URL(string: url) else {
            Logger.warn("http: not a url: \(url)")
            return
        }
        send(Request.post(parsed, contentType: contentType, body: body)) { result in
            switch result {
            case .failure(let error):
                Logger.info("http: POST \(url) failed: \(error.localizedDescription)")
            case .success(let response) where !response.ok:
                Logger.info("http: POST \(url) answered \(response.status)")
            default:
                break
            }
        }
    }
}
