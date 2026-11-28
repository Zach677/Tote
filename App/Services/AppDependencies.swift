import Core
import Foundation

struct AppDependencies {
    static let yixiaojiWebFallbackURL = URL(string: "https://ai.iepple.com/h5/#/")!

    let parcelStore: ParcelStore
    let clipboard: any ClipboardManaging
    let launcher: any ExternalLaunching
    let settings: any SettingsStoring
    let yixiaoji: any YixiaojiServicing
    let parser: PickupParser
    let deduplicator: ParcelDeduplicator

    init(
        parcelStore: ParcelStore,
        clipboard: any ClipboardManaging,
        launcher: any ExternalLaunching,
        settings: any SettingsStoring,
        yixiaoji: any YixiaojiServicing,
        parser: PickupParser = PickupParser(),
        deduplicator: ParcelDeduplicator = ParcelDeduplicator()
    ) {
        self.parcelStore = parcelStore
        self.clipboard = clipboard
        self.launcher = launcher
        self.settings = settings
        self.yixiaoji = yixiaoji
        self.parser = parser
        self.deduplicator = deduplicator
    }

    static func live() -> AppDependencies {
        let baseDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let toteDirectory = baseDirectory.appendingPathComponent("Tote", isDirectory: true)
        let sessionStore = KeychainYixiaojiSessionStore()

        return AppDependencies(
            parcelStore: ParcelStore(directoryURL: toteDirectory),
            clipboard: SystemClipboardService(),
            launcher: SystemExternalLauncher(),
            settings: UserDefaultsSettingsStore(),
            yixiaoji: LiveYixiaojiClient(sessionStore: sessionStore)
        )
    }
}
