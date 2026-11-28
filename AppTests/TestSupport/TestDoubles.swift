@testable import App
import Core
import Foundation

final class FakeClipboardService: ClipboardManaging {
    private(set) var copiedValues: [String] = []

    var lastCopied: String? {
        copiedValues.last
    }

    func copy(_ text: String) {
        copiedValues.append(text)
    }
}

final class FakeExternalLauncher: ExternalLaunching {
    var shouldSucceed = true
    private(set) var openedURLs: [URL] = []

    func open(_ url: URL, completion: @escaping @MainActor (Bool) -> Void) {
        openedURLs.append(url)
        completion(shouldSucceed)
    }
}

final class InMemorySettingsStore: SettingsStoring {
    var duoduoURLString: String

    init(duoduoURLString: String = DuoduoLinkValidator.defaultURLString) {
        self.duoduoURLString = duoduoURLString
    }

    func resetDuoduoURL() {
        duoduoURLString = DuoduoLinkValidator.defaultURLString
    }
}

final class InMemoryYixiaojiSessionStore: YixiaojiSessionStoring {
    var session: YixiaojiSession?
    var lastSelectedCabinet: YixiaojiCabinet?

    init(session: YixiaojiSession? = nil, lastSelectedCabinet: YixiaojiCabinet? = nil) {
        self.session = session
        self.lastSelectedCabinet = lastSelectedCabinet
    }

    func saveSession(_ session: YixiaojiSession) {
        self.session = session
    }

    func clearSession() {
        session = nil
    }
}

final class FakeYixiaojiService: YixiaojiServicing {
    struct UnlockRequest: Equatable {
        let code: String
        let cabinetMAC: String?
        let siteID: String?
    }

    var currentSession: YixiaojiSession?
    var lastSelectedCabinet: YixiaojiCabinet?

    var loginResult: Result<YixiaojiSession, any Error> = .success(
        YixiaojiSession(uid: "1001", token: "demo-token", username: "demo", defaultSiteID: "42", defaultSiteName: "Sample Locker A1")
    )
    var pendingParcelsResult: Result<[YixiaojiRemoteParcel], any Error> = .success([])
    var searchResultsByKeyword: [String: [YixiaojiRemoteParcel]] = [:]
    var cabinetsResult: Result<[YixiaojiCabinet], any Error> = .success([])
    var unlockResult: Result<YixiaojiUnlockResult, any Error> = .success(
        .opened(compartment: "28", message: "Opened", orderSN: "ORD-001")
    )

    private(set) var loginAttempts: [(username: String, password: String)] = []
    private(set) var logoutCount = 0
    private(set) var fetchPendingCount = 0
    private(set) var searchedKeywords: [String] = []
    private(set) var unlockRequests: [UnlockRequest] = []

    init(session: YixiaojiSession? = nil) {
        currentSession = session
    }

    func login(username: String, password: String) async throws -> YixiaojiSession {
        loginAttempts.append((username, password))
        let session = try loginResult.get()
        currentSession = session
        return session
    }

    func logout() {
        logoutCount += 1
        currentSession = nil
    }

    func fetchPendingParcels() async throws -> [YixiaojiRemoteParcel] {
        fetchPendingCount += 1
        guard currentSession != nil else {
            throw YixiaojiAPIError.notSignedIn
        }
        return try pendingParcelsResult.get()
    }

    func searchParcels(keyword: String) async throws -> [YixiaojiRemoteParcel] {
        searchedKeywords.append(keyword)
        guard currentSession != nil else {
            throw YixiaojiAPIError.notSignedIn
        }
        return searchResultsByKeyword[keyword] ?? []
    }

    func fetchCabinets(keyword _: String) async throws -> [YixiaojiCabinet] {
        guard currentSession != nil else {
            throw YixiaojiAPIError.notSignedIn
        }
        return try cabinetsResult.get()
    }

    func unlockParcel(code: String, cabinetMAC: String?, siteID: String?) async throws -> YixiaojiUnlockResult {
        unlockRequests.append(UnlockRequest(code: code, cabinetMAC: cabinetMAC, siteID: siteID))
        guard currentSession != nil else {
            throw YixiaojiAPIError.notSignedIn
        }
        return try unlockResult.get()
    }
}

struct TestEnvironment {
    let dependencies: AppDependencies
    let clipboard: FakeClipboardService
    let launcher: FakeExternalLauncher
    let settings: InMemorySettingsStore
    let yixiaoji: FakeYixiaojiService
    let store: ParcelStore
    let directoryURL: URL

    init(
        duoduoURLString: String = DuoduoLinkValidator.defaultURLString,
        yixiaojiSession: YixiaojiSession? = nil,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ToteAppTests-\(UUID().uuidString)", isDirectory: true)
        let store = ParcelStore(directoryURL: directoryURL, now: now)
        let clipboard = FakeClipboardService()
        let launcher = FakeExternalLauncher()
        let settings = InMemorySettingsStore(duoduoURLString: duoduoURLString)
        let yixiaoji = FakeYixiaojiService(session: yixiaojiSession)

        self.directoryURL = directoryURL
        self.store = store
        self.clipboard = clipboard
        self.launcher = launcher
        self.settings = settings
        self.yixiaoji = yixiaoji
        dependencies = AppDependencies(
            parcelStore: store,
            clipboard: clipboard,
            launcher: launcher,
            settings: settings,
            yixiaoji: yixiaoji
        )
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: directoryURL)
    }
}
