import Core
import Foundation

extension Notification.Name {
    nonisolated static let toteParcelsDidChange = Notification.Name("org.zaxh.tote.parcelsDidChange")
}

struct AppDependencies {
    static let yixiaojiWebFallbackURL = URL(string: "https://ai.iepple.com/h5/#/")!

    let parcelStore: ParcelStore
    let clipboard: any ClipboardManaging
    let launcher: any ExternalLaunching
    let settings: any SettingsStoring
    let yixiaoji: any YixiaojiServicing
    let notificationCenter: NotificationCenter
    let parser: PickupParser
    let deduplicator: ParcelDeduplicator

    init(
        parcelStore: ParcelStore,
        clipboard: any ClipboardManaging,
        launcher: any ExternalLaunching,
        settings: any SettingsStoring,
        yixiaoji: any YixiaojiServicing,
        notificationCenter: NotificationCenter = .default,
        parser: PickupParser = PickupParser(),
        deduplicator: ParcelDeduplicator = ParcelDeduplicator()
    ) {
        self.parcelStore = parcelStore
        self.clipboard = clipboard
        self.launcher = launcher
        self.settings = settings
        self.yixiaoji = yixiaoji
        self.notificationCenter = notificationCenter
        self.parser = parser
        self.deduplicator = deduplicator
    }

    static func liveParcelStore() -> ParcelStore {
        let baseDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let toteDirectory = baseDirectory.appendingPathComponent("Tote", isDirectory: true)
        return ParcelStore(directoryURL: toteDirectory)
    }

    static func live() -> AppDependencies {
        let sessionStore = KeychainYixiaojiSessionStore()

        return AppDependencies(
            parcelStore: liveParcelStore(),
            clipboard: SystemClipboardService(),
            launcher: SystemExternalLauncher(),
            settings: UserDefaultsSettingsStore(),
            yixiaoji: LiveYixiaojiClient(sessionStore: sessionStore)
        )
    }
}
