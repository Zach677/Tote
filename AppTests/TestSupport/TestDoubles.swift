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

struct TestEnvironment {
    let dependencies: AppDependencies
    let clipboard: FakeClipboardService
    let launcher: FakeExternalLauncher
    let settings: InMemorySettingsStore
    let store: ParcelStore
    let directoryURL: URL

    init(
        duoduoURLString: String = DuoduoLinkValidator.defaultURLString,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ToteAppTests-\(UUID().uuidString)", isDirectory: true)
        let store = ParcelStore(directoryURL: directoryURL, now: now)
        let clipboard = FakeClipboardService()
        let launcher = FakeExternalLauncher()
        let settings = InMemorySettingsStore(duoduoURLString: duoduoURLString)

        self.directoryURL = directoryURL
        self.store = store
        self.clipboard = clipboard
        self.launcher = launcher
        self.settings = settings
        dependencies = AppDependencies(
            parcelStore: store,
            clipboard: clipboard,
            launcher: launcher,
            settings: settings,
            autoLoadYixiaoji: false
        )
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: directoryURL)
    }
}
