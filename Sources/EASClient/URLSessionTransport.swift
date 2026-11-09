import Foundation

/// URLSession-backed transport. Owns its own session so sync traffic never shares
/// queues or connection pools with the app shell.
public final class URLSessionTransport: EASHTTPTransport, @unchecked Sendable {
    private let session: URLSession

    public init(configuration: EASConfiguration) {
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.timeoutIntervalForRequest = 60
        sessionConfiguration.timeoutIntervalForResource = 120
        sessionConfiguration.httpShouldSetCookies = false
        sessionConfiguration.requestCachePolicy = .reloadIgnoringLocalCacheData
        if configuration.allowInsecureTLS {
            self.session = URLSession(
                configuration: sessionConfiguration,
                delegate: InsecureTrustDelegate(),
                delegateQueue: nil
            )
        } else {
            self.session = URLSession(configuration: sessionConfiguration)
        }
    }

    public func send(_ request: EASHTTPRequest) async throws -> EASHTTPResponse {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        for (name, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }

        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else {
            throw EASError.transient(reason: "non-HTTP response")
        }
        var headers: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
            headers[String(describing: key).lowercased()] = String(describing: value)
        }
        return EASHTTPResponse(status: http.statusCode, headers: headers, body: data)
    }
}

/// Accepts any server certificate. Only reachable through
/// `EASConfiguration.allowInsecureTLS`, which defaults to false.
private final class InsecureTrustDelegate: NSObject, URLSessionDelegate {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}
