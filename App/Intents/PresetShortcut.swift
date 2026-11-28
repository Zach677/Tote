import Foundation

nonisolated enum PresetShortcut: String, CaseIterable, Hashable, Sendable {
    case captureScreen
    case importScreenshot
    case importClipboard

    var iCloudURL: URL {
        switch self {
        case .captureScreen:
            URL(string: "https://www.icloud.com/shortcuts/39ca338a7d714caf90618ad38c93c7ba")!
        case .importScreenshot:
            URL(string: "https://www.icloud.com/shortcuts/af9f8059beed4b49926713482308dde2")!
        case .importClipboard:
            URL(string: "https://www.icloud.com/shortcuts/8ffade53384c42c48aa39aa377c6a013")!
        }
    }

    var title: String {
        switch self {
        case .captureScreen:
            String(localized: "Capture Current Screen")
        case .importScreenshot:
            String(localized: "Import from Screenshot")
        case .importClipboard:
            String(localized: "Import from Clipboard")
        }
    }

    var subtitle: String {
        switch self {
        case .captureScreen:
            String(localized: "Bind to Action Button or Back Tap for 1-tap OCR")
        case .importScreenshot:
            String(localized: "Add from Share Sheet or pick a photo")
        case .importClipboard:
            String(localized: "Parse copied pickup codes in one tap")
        }
    }

    var symbolName: String {
        switch self {
        case .captureScreen:
            "camera.viewfinder"
        case .importScreenshot:
            "photo.on.rectangle"
        case .importClipboard:
            "doc.on.clipboard"
        }
    }
}
