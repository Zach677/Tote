import Core
import Foundation
import Security

protocol YixiaojiSessionStoring: AnyObject {
    var session: YixiaojiSession? { get }
    var lastSelectedCabinet: YixiaojiCabinet? { get set }

    func saveSession(_ session: YixiaojiSession)
    func clearSession()
}

final class KeychainYixiaojiSessionStore: YixiaojiSessionStoring {
    private enum Constants {
        static let service = "org.zaxh.tote.yixiaoji"
        static let account = "session"
        static let lastCabinetKey = "yixiaojiLastSelectedCabinet"
    }

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    var session: YixiaojiSession? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Constants.service,
            kSecAttrAccount as String: Constants.account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            return nil
        }

        return try? JSONDecoder().decode(YixiaojiSession.self, from: data)
    }

    var lastSelectedCabinet: YixiaojiCabinet? {
        get {
            guard let data = userDefaults.data(forKey: Constants.lastCabinetKey) else {
                return nil
            }
            return try? JSONDecoder().decode(YixiaojiCabinet.self, from: data)
        }
        set {
            guard let newValue, let data = try? JSONEncoder().encode(newValue) else {
                userDefaults.removeObject(forKey: Constants.lastCabinetKey)
                return
            }
            userDefaults.set(data, forKey: Constants.lastCabinetKey)
        }
    }

    func saveSession(_ session: YixiaojiSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }

        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Constants.service,
            kSecAttrAccount as String: Constants.account,
        ]

        SecItemDelete(baseQuery as CFDictionary)

        var addQuery = baseQuery
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    func clearSession() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Constants.service,
            kSecAttrAccount as String: Constants.account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
