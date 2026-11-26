import Core
import Foundation

struct AppDependencies {
    static let defaultYixiaojiURL = URL(string: "https://ai.iepple.com")!

    let parcelStore: ParcelStore
    let clipboard: any ClipboardManaging
    let launcher: any ExternalLaunching
    let settings: any SettingsStoring
    let parser: PickupParser
    let deduplicator: ParcelDeduplicator
    let autoLoadYixiaoji: Bool
    let yixiaojiURL: URL

    init(
        parcelStore: ParcelStore,
        clipboard: any ClipboardManaging,
        launcher: any ExternalLaunching,
        settings: any SettingsStoring,
        parser: PickupParser = PickupParser(),
        deduplicator: ParcelDeduplicator = ParcelDeduplicator(),
        autoLoadYixiaoji: Bool = true,
        yixiaojiURL: URL = AppDependencies.defaultYixiaojiURL
    ) {
        self.parcelStore = parcelStore
        self.clipboard = clipboard
        self.launcher = launcher
        self.settings = settings
        self.parser = parser
        self.deduplicator = deduplicator
        self.autoLoadYixiaoji = autoLoadYixiaoji
        self.yixiaojiURL = yixiaojiURL
    }

    static func live() -> AppDependencies {
        let baseDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let toteDirectory = baseDirectory.appendingPathComponent("Tote", isDirectory: true)

        return AppDependencies(
            parcelStore: ParcelStore(directoryURL: toteDirectory),
            clipboard: SystemClipboardService(),
            launcher: SystemExternalLauncher(),
            settings: UserDefaultsSettingsStore()
        )
    }
}
