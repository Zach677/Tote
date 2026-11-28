import Core
import Foundation

protocol YixiaojiServicing: AnyObject {
    var currentSession: YixiaojiSession? { get }
    var lastSelectedCabinet: YixiaojiCabinet? { get set }

    func login(username: String, password: String) async throws -> YixiaojiSession
    func logout()
    func fetchPendingParcels() async throws -> YixiaojiPendingSyncBatch
    func searchParcels(keyword: String) async throws -> [YixiaojiRemoteParcel]
    func fetchCabinets(keyword: String) async throws -> [YixiaojiCabinet]
    func unlockParcel(code: String, cabinetMAC: String?, siteID: String?) async throws -> YixiaojiUnlockResult
}

final class LiveYixiaojiClient: YixiaojiServicing {
    private enum Endpoints {
        static let baseURL = URL(string: "https://ai.iepple.com")!
        static let login = "/index/wechat/h5_login"
        static let userInfo = "/api/user/userinfo"
        static let search = "/api/wechat/search"
        static let localizationList = "/api/express/getLocalizationList"
        static let tackLockOrder = "/api/dev/tackLockOrder"
        static let checkOrder = "/api/dev/checkOrder"
        static let pageSize = 10
        static let maxPendingPages = 5
    }

    private let sessionStore: any YixiaojiSessionStoring
    private let urlSession: URLSession

    init(
        sessionStore: any YixiaojiSessionStoring,
        urlSession: URLSession = .shared
    ) {
        self.sessionStore = sessionStore
        self.urlSession = urlSession
    }

    var currentSession: YixiaojiSession? {
        sessionStore.session
    }

    var lastSelectedCabinet: YixiaojiCabinet? {
        get { sessionStore.lastSelectedCabinet }
        set { sessionStore.lastSelectedCabinet = newValue }
    }

    func login(username: String, password: String) async throws -> YixiaojiSession {
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUsername.isEmpty, !password.isEmpty else {
            throw YixiaojiAPIError.invalidCredentials("")
        }

        let body = ["username": trimmedUsername, "password": password]
        let data = try await sendJSONPost(path: Endpoints.login, body: body, token: nil)
        var session = try YixiaojiResponseParser.parseLoginResponse(data, username: trimmedUsername)

        // Best-effort refresh to populate the bound station display name.
        if let infoData = try? await sendJSONPost(
            path: Endpoints.userInfo,
            body: ["uid": session.uid, "token": session.token],
            token: session.token
        ),
            let enriched = YixiaojiResponseParser.parseUserInfoResponse(infoData, updating: session)
        {
            session = enriched
        }

        try sessionStore.saveSession(session)
        return session
    }

    func logout() {
        sessionStore.clearSession()
    }

    func fetchPendingParcels() async throws -> YixiaojiPendingSyncBatch {
        let session = try requireSession()
        var collected: [YixiaojiRemoteParcel] = []
        var isTruncated = false

        for page in 1 ... Endpoints.maxPendingPages {
            let queryItems: [URLQueryItem] = [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "token", value: session.token),
                URLQueryItem(name: "user_id", value: session.uid),
                URLQueryItem(name: "express_uids", value: session.defaultSiteID),
                URLQueryItem(name: "is_open", value: "0"),
            ]
            let data = try await sendGet(path: Endpoints.search, queryItems: queryItems, token: session.token)
            let pageItems = try YixiaojiResponseParser.parseSearchResponse(data)
            collected.append(contentsOf: pageItems.filter { !$0.isPickedUp })

            if pageItems.count < Endpoints.pageSize {
                isTruncated = false
                break
            }
            if page == Endpoints.maxPendingPages {
                isTruncated = true
            }
        }

        return YixiaojiPendingSyncBatch(parcels: collected, isTruncated: isTruncated)
    }

    func searchParcels(keyword: String) async throws -> [YixiaojiRemoteParcel] {
        let session = try requireSession()
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let queryItems: [URLQueryItem] = [
            URLQueryItem(name: "page", value: "0"),
            URLQueryItem(name: "token", value: session.token),
            URLQueryItem(name: "user_id", value: session.uid),
            URLQueryItem(name: "express_uids", value: session.defaultSiteID),
            URLQueryItem(name: "keyword", value: trimmed),
        ]
        let data = try await sendGet(path: Endpoints.search, queryItems: queryItems, token: session.token)
        return try YixiaojiResponseParser.parseSearchResponse(data)
    }

    func fetchCabinets(keyword: String = "") async throws -> [YixiaojiCabinet] {
        let session = try requireSession()
        let queryItems: [URLQueryItem] = [
            URLQueryItem(name: "keyword", value: keyword.trimmingCharacters(in: .whitespacesAndNewlines)),
            URLQueryItem(name: "uid", value: session.uid),
            URLQueryItem(name: "style", value: "1"),
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "limit", value: "100"),
        ]
        let data = try await sendGet(path: Endpoints.localizationList, queryItems: queryItems, token: session.token)
        let parsed = try YixiaojiResponseParser.parseCabinetsResponse(data)
        return parsed.cabinets
    }

    func unlockParcel(code: String, cabinetMAC: String?, siteID: String?) async throws -> YixiaojiUnlockResult {
        let session = try requireSession()
        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCode.isEmpty else {
            throw YixiaojiAPIError.serverError("")
        }

        let cleanMAC = YixiaojiResponseParser.cleanMAC(cabinetMAC ?? "")
        let cleanSiteID = YixiaojiResponseParser.cleanSiteID(siteID ?? "")
        // Fail closed: never send an unlock request without an explicit locker target.
        guard !cleanMAC.isEmpty || !cleanSiteID.isEmpty else {
            throw YixiaojiAPIError.missingCabinetSelection
        }

        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "keyword", value: trimmedCode),
            URLQueryItem(name: "user_id", value: session.uid),
        ]
        if !cleanMAC.isEmpty {
            queryItems.append(URLQueryItem(name: "mac", value: cleanMAC))
        }
        if !cleanSiteID.isEmpty {
            queryItems.append(URLQueryItem(name: "express_uids", value: cleanSiteID))
        }

        let submitData = try await sendGet(
            path: Endpoints.tackLockOrder,
            queryItems: queryItems,
            token: session.token,
            contentType: "application/x-www-form-urlencoded; charset=UTF-8",
            treatAmbiguousTransportAsUnconfirmed: true
        )
        let submission = try YixiaojiResponseParser.parseUnlockSubmission(submitData)

        switch submission {
        case let .paymentRequired(message, amount, overdueDays):
            return .paymentRequired(message: message, amount: amount, overdueDays: overdueDays)

        case let .submitted(orderSN, message):
            guard !orderSN.isEmpty else {
                throw YixiaojiAPIError.unlockUnconfirmed(message: message, orderSN: "")
            }

            do {
                let checkData = try await sendGet(
                    path: Endpoints.checkOrder,
                    queryItems: [URLQueryItem(name: "order_sn", value: orderSN)],
                    token: session.token,
                    contentType: "application/x-www-form-urlencoded; charset=UTF-8"
                )
                return try YixiaojiResponseParser.parseCheckOrderResponse(
                    checkData,
                    fallbackOrderSN: orderSN,
                    fallbackMessage: message
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch let apiError as YixiaojiAPIError {
                let detail = switch apiError {
                case let .serverError(msg), let .sessionExpired(msg), let .networkError(msg):
                    msg.isEmpty ? message : msg
                default:
                    message
                }
                throw YixiaojiAPIError.unlockUnconfirmed(message: detail, orderSN: orderSN)
            } catch {
                throw YixiaojiAPIError.unlockUnconfirmed(message: message, orderSN: orderSN)
            }
        }
    }
}

private extension LiveYixiaojiClient {
    func requireSession() throws -> YixiaojiSession {
        guard let session = sessionStore.session else {
            throw YixiaojiAPIError.notSignedIn
        }
        return session
    }

    func sendGet(
        path: String,
        queryItems: [URLQueryItem],
        token: String?,
        contentType: String? = nil,
        treatAmbiguousTransportAsUnconfirmed: Bool = false
    ) async throws -> Data {
        guard var components = URLComponents(
            url: Endpoints.baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        ) else {
            throw YixiaojiAPIError.invalidResponse
        }
        components.queryItems = queryItems
        guard let url = components.url else {
            throw YixiaojiAPIError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        if let token, !token.isEmpty {
            request.setValue(token, forHTTPHeaderField: "token")
        }
        if let contentType {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }

        return try await execute(
            request,
            treatAmbiguousTransportAsUnconfirmed: treatAmbiguousTransportAsUnconfirmed
        )
    }

    func sendJSONPost(
        path: String,
        body: [String: String],
        token: String?
    ) async throws -> Data {
        let url = Endpoints.baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        if let token, !token.isEmpty {
            request.setValue(token, forHTTPHeaderField: "token")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        return try await execute(request)
    }

    func execute(
        _ request: URLRequest,
        treatAmbiguousTransportAsUnconfirmed: Bool = false
    ) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let urlError as URLError where urlError.code == .cancelled {
            throw CancellationError()
        } catch let urlError as URLError where treatAmbiguousTransportAsUnconfirmed
            && (urlError.code == .timedOut || urlError.code == .networkConnectionLost)
        {
            throw YixiaojiAPIError.unlockUnconfirmed(message: urlError.localizedDescription, orderSN: "")
        } catch {
            throw YixiaojiAPIError.networkError(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw YixiaojiAPIError.invalidResponse
        }
        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 {
                throw YixiaojiAPIError.sessionExpired("")
            }
            throw YixiaojiAPIError.networkError("HTTP \(httpResponse.statusCode)")
        }

        return data
    }
}
