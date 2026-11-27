import PiSwiftAI
import XCTest
@testable import Poki

/// The AI/ML API account: its key goes only to https://api.aimlapi.com, its list keeps the chat
/// completions models that call tools.
@MainActor
final class AIMLAPIProviderTests: XCTestCase {
    /// Records what reaches it instead of sending anything, and answers with a redirect when asked.
    private final class Recorder: ProviderHTTPClient, @unchecked Sendable {
        var sent: [URLRequest] = []
        func send(_ request: URLRequest) async throws -> ProviderHTTPResponse {
            try await send(request, timeoutPolicy: .request)
        }
        func send(_ request: URLRequest, timeoutPolicy: ProviderHTTPTimeoutPolicy) async throws -> ProviderHTTPResponse {
            sent.append(request)
            return ProviderHTTPResponse(statusCode: 200, headers: [:], body: Data())
        }
    }

    private func request(_ address: String) -> URLRequest {
        var request = URLRequest(url: URL(string: address)!)
        request.setValue("Bearer placeholder-test-key", forHTTPHeaderField: "Authorization")
        return request
    }

    func testTheAccountIsListedUnderItsName() {
        XCTAssertTrue(ModelProvider.allCases.contains(.aimlapi))
        XCTAssertEqual(ModelProvider.aimlapi.rawValue, "aimlapi")
        XCTAssertEqual(ModelProvider.aimlapi.name, "AI/ML API")
        XCTAssertFalse(ModelProvider.aimlapi.signsIn)
    }

    func testModelsRunOnChatCompletionsAtTheFixedAddress() throws {
        let model = try XCTUnwrap(ModelProvider.aimlapi.piModel("google/gemini-3.8-flash"))
        XCTAssertEqual(model.baseUrl, "https://api.aimlapi.com/v1")
        XCTAssertEqual(model.api, .openAICompletions)
        XCTAssertEqual(model.provider, "aimlapi")
        XCTAssertTrue(model.input.contains(.image))
        let unknown = try XCTUnwrap(ModelProvider.aimlapi.piModel("vendor/new-chat"))
        XCTAssertEqual(unknown.baseUrl, "https://api.aimlapi.com/v1")
    }

    func testTheKeyGoesOnlyToTheExactHost() async throws {
        let recorder = Recorder()
        let client = AIMLAPIClient(inner: recorder)
        _ = try await client.send(request("https://api.aimlapi.com/v1/chat/completions"))
        for address in ["https://api.aimlapi.com.evil.test/v1/chat/completions",
                        "https://evil.test/api.aimlapi.com/v1",
                        "https://aimlapi.com/v1/chat/completions",
                        "https://mcp.aimlapi.com/v1/chat/completions",
                        "http://api.aimlapi.com/v1/chat/completions",
                        "https://api.aimlapi.com:8443/v1/chat/completions",
                        "https://user:pass@api.aimlapi.com/v1/chat/completions"] {
            do {
                _ = try await client.send(request(address))
                XCTFail("sent to \(address)")
            } catch {}
        }
        XCTAssertEqual(recorder.sent.map { $0.url?.absoluteString }, ["https://api.aimlapi.com/v1/chat/completions"])
    }

    /// The transport refuses redirects, so a 3xx from the API cannot carry the key to another host.
    func testTheTransportDoesNotFollowRedirects() {
        XCTAssertFalse(AIMLAPIClient.transport().followRedirects)
        XCTAssertFalse((AIMLAPIClient().inner as? DefaultProviderHTTPClient)?.followRedirects ?? true)
    }

    func testTheListKeepsChatCompletionsModelsWithTools() {
        let items: [[String: Any]] = [
            ["id": "google/gemini-3.8-flash", "type": "openai/chat-completions", "capabilities": ["streaming", "tools", "vision"]],
            ["id": "vendor/no-tools", "type": "openai/chat-completions", "capabilities": ["streaming"]],
            ["id": "vendor/image-model", "type": "image"],
            ["id": "vendor/embedding", "type": "embedding"],
            ["id": "vendor/plain-chat", "type": "openai/chat-completions"],
        ]
        XCTAssertEqual(ModelCatalog.aimlapiChatItems(items).compactMap { $0["id"] as? String },
                       ["google/gemini-3.8-flash", "vendor/plain-chat"])
    }

    /// A fresh install with nothing set up starts on AI/ML API.
    func testAFreshInstallStartsOnAIMLAPI() throws {
        let isolated = try IsolatedTestStorage()
        defer { try? isolated.tearDown() }
        XCTAssertEqual(ModelKeys.selectedProvider(in: isolated.storage), .aimlapi)
        XCTAssertEqual(ModelKeys.selectedModel(in: isolated.storage), "google/gemini-3.8-flash")
    }

    /// An owner with a key for another account and no saved choice keeps Anthropic, as before.
    func testAnOwnerWithAnotherKeyKeepsTheOldDefault() throws {
        let isolated = try IsolatedTestStorage()
        defer { try? isolated.tearDown() }
        try ModelKeys.save("placeholder-test-key", for: .anthropic, storage: isolated.storage)
        XCTAssertEqual(ModelKeys.selectedProvider(in: isolated.storage), .anthropic)
    }

    /// A saved choice always wins.
    func testASavedChoiceIsKept() throws {
        let isolated = try IsolatedTestStorage()
        defer { try? isolated.tearDown() }
        ModelKeys.setSelectedProvider(.openrouter, in: isolated.storage)
        XCTAssertEqual(ModelKeys.selectedProvider(in: isolated.storage), .openrouter)
    }
}
