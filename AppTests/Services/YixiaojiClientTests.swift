@testable import App
import Core
import Foundation
import Testing

struct YixiaojiClientTests {
    @Test
    func liveClientAuthenticatesSyncsAndUnlocksTwoStepOverStubbedTransport() async throws {
        let sessionStore = InMemoryYixiaojiSessionStore()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubYixiaojiURLProtocol.self]
        let urlSession = URLSession(configuration: config)

        let capturedPaths = CapturedRequests()
        StubYixiaojiURLProtocol.setHandler { request in
            let url = try #require(request.url)
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let path = url.path
            capturedPaths.record(path: path, token: request.value(forHTTPHeaderField: "token"), query: components?.query ?? "")

            switch path {
            case "/index/wechat/h5_login":
                return (
                    200,
                    Data(#"{"code":1,"data":{"uid":1024,"token":"tok-1","phone":"13800000000","express_uids":"42,","nickname":"Demo"}}"#.utf8)
                )
            case "/api/user/userinfo":
                return (
                    200,
                    Data(#"{"code":1,"data":{"id":1024,"token":"tok-1","express_uids":"42,","express_name":"Sample Locker A1"}}"#.utf8)
                )
            case "/api/wechat/search":
                return (
                    200,
                    Data(#"{"code":1,"data":[{"take_code":"05240000","order_sn":"YT0000000000000","address":"Sample Locker A1","bind_mac":"MAC-A1","express_uids":"42","is_get":0,"is_open":0}]}"#.utf8)
                )
            case "/api/dev/tackLockOrder":
                return (
                    200,
                    Data(#"{"code":1,"msg":"Submitted","data":{"order_sn":"ORD-77"}}"#.utf8)
                )
            case "/api/dev/checkOrder":
                return (
                    200,
                    Data(#"{"code":1,"msg":"Opened","data":{"box_code":12,"dev_code":"A12"}}"#.utf8)
                )
            default:
                return (404, Data())
            }
        }
        defer { StubYixiaojiURLProtocol.setHandler(nil) }

        let client = LiveYixiaojiClient(sessionStore: sessionStore, urlSession: urlSession)
        let session = try await client.login(username: "demo", password: "secret")
        #expect(session.uid == "1024")
        #expect(session.token == "tok-1")
        #expect(session.defaultSiteName == "Sample Locker A1")
        #expect(sessionStore.session == session)

        let pending = try await client.fetchPendingParcels()
        #expect(pending.count == 1)
        #expect(pending[0].pickupCode == "05240000")
        #expect(pending[0].cabinetMAC == "MAC-A1")

        let unlockResult = try await client.unlockParcel(
            code: "05240000",
            cabinetMAC: "MAC-A1",
            siteID: "42"
        )
        #expect(unlockResult == .opened(compartment: "12", message: "Opened", orderSN: "ORD-77"))

        let requests = capturedPaths.snapshot()
        let tackRequest = try #require(requests.first { $0.path == "/api/dev/tackLockOrder" })
        #expect(tackRequest.token == "tok-1")
        #expect(tackRequest.query.contains("keyword=05240000"))
        #expect(tackRequest.query.contains("mac=MAC-A1"))
        #expect(tackRequest.query.contains("express_uids=42"))

        let checkRequest = try #require(requests.first { $0.path == "/api/dev/checkOrder" })
        #expect(checkRequest.query.contains("order_sn=ORD-77"))
    }
}

private final nonisolated class CapturedRequests: @unchecked Sendable {
    struct Entry {
        let path: String
        let token: String?
        let query: String
    }

    private let lock = NSLock()
    private var entries: [Entry] = []

    func record(path: String, token: String?, query: String) {
        lock.lock()
        entries.append(Entry(path: path, token: token, query: query))
        lock.unlock()
    }

    func snapshot() -> [Entry] {
        lock.lock()
        defer { lock.unlock() }
        return entries
    }
}

private final nonisolated class StubYixiaojiURLProtocol: URLProtocol {
    typealias Handler = @Sendable (URLRequest) throws -> (Int, Data)

    private nonisolated(unsafe) static var handler: Handler?
    private static let lock = NSLock()

    static func setHandler(_ newHandler: Handler?) {
        lock.lock()
        handler = newHandler
        lock.unlock()
    }

    private static func currentHandler() -> Handler? {
        lock.lock()
        defer { lock.unlock() }
        return handler
    }

    override class func canInit(with _: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.currentHandler(), let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        do {
            let (statusCode, data) = try handler(request)
            let response = HTTPURLResponse(
                url: url,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
