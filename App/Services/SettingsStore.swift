import Core
import Foundation

protocol SettingsStoring: AnyObject {
    var duoduoURLString: String { get set }
    func resetDuoduoURL()
}

final class UserDefaultsSettingsStore: SettingsStoring {
    private enum Keys {
        static let duoduoURL = "duoduoStationURL"
    }

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    var duoduoURLString: String {
        get {
            userDefaults.string(forKey: Keys.duoduoURL) ?? DuoduoLinkValidator.defaultURLString
        }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                userDefaults.removeObject(forKey: Keys.duoduoURL)
            } else {
                userDefaults.set(trimmed, forKey: Keys.duoduoURL)
            }
        }
    }

    func resetDuoduoURL() {
        userDefaults.removeObject(forKey: Keys.duoduoURL)
    }
}
