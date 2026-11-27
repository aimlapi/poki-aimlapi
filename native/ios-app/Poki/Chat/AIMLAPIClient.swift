import Foundation
import PiSwiftAI

/// The HTTP client for the AI/ML API account. The owner's key goes only to `https://api.aimlapi.com`:
/// a request for any other address is refused before it is sent, and a redirect is not followed, so
/// the key never reaches another host.
struct AIMLAPIClient: ProviderHTTPClient {
    static let host = "api.aimlapi.com"
    static let baseURL = "https://api.aimlapi.com/v1"

    let inner: any ProviderHTTPClient

    init(inner: any ProviderHTTPClient = Self.transport()) {
        self.inner = inner
    }

    /// pi's transport with redirects refused.
    static func transport(env: [String: String]? = nil) -> DefaultProviderHTTPClient {
        DefaultProviderHTTPClient(env: env, followRedirects: false)
    }

    /// Only HTTPS to the exact host, on the default port.
    static func allows(_ url: URL?) -> Bool {
        guard let url, url.scheme?.lowercased() == "https", url.host?.lowercased() == host,
              url.user == nil, url.password == nil else { return false }
        return url.port == nil || url.port == 443
    }

    func send(_ request: URLRequest) async throws -> ProviderHTTPResponse {
        try await send(request, timeoutPolicy: .request)
    }

    func send(_ request: URLRequest, timeoutPolicy: ProviderHTTPTimeoutPolicy) async throws -> ProviderHTTPResponse {
        guard Self.allows(request.url) else { throw URLError(.unsupportedURL) }
        return try await inner.send(request, timeoutPolicy: timeoutPolicy)
    }
}
