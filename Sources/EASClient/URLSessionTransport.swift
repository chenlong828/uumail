import Foundation

/// URLSession-backed transport. Owns its own sessions so sync traffic never shares
/// queues or connection pools with the app shell.
///
/// One session per total-time budget: commands keep the 120 s default, while attachment
/// downloads ask for a longer budget through `EASHTTPRequest.resourceTimeout` because the
/// gateway needs minutes to produce a large base64 payload.
public final class URLSessionTransport: EASHTTPTransport, @unchecked Sendable {
    public static let defaultResourceTimeout: TimeInterval = 120
    private static let requestTimeout: TimeInterval = 60

    private let configuration: EASConfiguration
    private let lock = NSLock()
    private var sessions: [TimeInterval: URLSession] = [:]

    public init(configuration: EASConfiguration) {
        self.configuration = configuration
    }

    public func send(_ request: EASHTTPRequest) async throws -> EASHTTPResponse {
        let session = session(resourceTimeout: request.resourceTimeout ?? Self.defaultResourceTimeout)
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

    /// Creates (and caches) the session for one total-time budget. The idle timeout stays
    /// at 60 s for every budget; only the overall budget changes.
    private func session(resourceTimeout: TimeInterval) -> URLSession {
        lock.withLock {
            if let existing = sessions[resourceTimeout] {
                return existing
            }
            let sessionConfiguration = URLSessionConfiguration.ephemeral
            sessionConfiguration.timeoutIntervalForRequest = Self.requestTimeout
            sessionConfiguration.timeoutIntervalForResource = resourceTimeout
            sessionConfiguration.httpShouldSetCookies = false
            sessionConfiguration.requestCachePolicy = .reloadIgnoringLocalCacheData
            let session: URLSession
            if configuration.allowInsecureTLS {
                session = URLSession(
                    configuration: sessionConfiguration,
                    delegate: InsecureTrustDelegate(),
                    delegateQueue: nil
                )
            } else {
                session = URLSession(configuration: sessionConfiguration)
            }
            sessions[resourceTimeout] = session
            return session
        }
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
