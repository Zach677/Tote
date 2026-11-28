import Foundation

public struct YixiaojiSession: Codable, Hashable, Sendable {
    public var uid: String
    public var token: String
    public var username: String
    public var phone: String
    public var nickname: String
    public var defaultSiteID: String
    public var defaultSiteName: String

    public init(
        uid: String,
        token: String,
        username: String = "",
        phone: String = "",
        nickname: String = "",
        defaultSiteID: String = "",
        defaultSiteName: String = ""
    ) {
        self.uid = uid
        self.token = token
        self.username = username
        self.phone = phone
        self.nickname = nickname
        self.defaultSiteID = defaultSiteID
        self.defaultSiteName = defaultSiteName
    }

    public var displayAccountName: String {
        for candidate in [nickname, phone, username, uid] {
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return ""
    }
}

public struct YixiaojiCabinet: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var address: String
    public var city: String
    public var mac: String

    public init(
        id: String,
        name: String,
        address: String = "",
        city: String = "",
        mac: String = ""
    ) {
        self.id = id
        self.name = name
        self.address = address
        self.city = city
        self.mac = mac
    }

    public var displayDetail: String {
        let parts = [city, address]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.joined(separator: " · ")
    }
}

public struct YixiaojiRemoteParcel: Hashable, Sendable {
    public var pickupCode: String
    public var trackingNumber: String
    public var cabinetName: String
    public var cabinetMAC: String
    public var siteID: String
    public var mobile: String
    public var isPickedUp: Bool

    public init(
        pickupCode: String,
        trackingNumber: String = "",
        cabinetName: String = "",
        cabinetMAC: String = "",
        siteID: String = "",
        mobile: String = "",
        isPickedUp: Bool = false
    ) {
        self.pickupCode = pickupCode
        self.trackingNumber = trackingNumber
        self.cabinetName = cabinetName
        self.cabinetMAC = cabinetMAC
        self.siteID = siteID
        self.mobile = mobile
        self.isPickedUp = isPickedUp
    }

    public func makeDraft() -> ParsedParcelDraft {
        ParsedParcelDraft(
            pickupCode: pickupCode,
            trackingNumber: trackingNumber,
            channel: .locker,
            stationLabel: cabinetName,
            note: "",
            lockerMAC: cabinetMAC,
            lockerSiteID: siteID
        )
    }
}

public struct YixiaojiPendingSyncBatch: Equatable, Sendable {
    public var parcels: [YixiaojiRemoteParcel]
    public var isTruncated: Bool

    public init(parcels: [YixiaojiRemoteParcel], isTruncated: Bool = false) {
        self.parcels = parcels
        self.isTruncated = isTruncated
    }
}

public enum YixiaojiUnlockResult: Equatable, Sendable {
    case opened(compartment: String, message: String, orderSN: String)
    case paymentRequired(message: String, amount: String, overdueDays: String)
}

public enum YixiaojiAPIError: Error, Equatable, Sendable {
    case notSignedIn
    case missingCabinetSelection
    case invalidCredentials(String)
    case sessionExpired(String)
    case unlockUnconfirmed(message: String, orderSN: String)
    case storageError(String)
    case serverError(String)
    case invalidResponse
    case networkError(String)
}

public enum YixiaojiUnlockSubmission: Equatable, Sendable {
    case submitted(orderSN: String, message: String)
    case paymentRequired(message: String, amount: String, overdueDays: String)
}

public enum YixiaojiResponseParser {
    public static func cleanSiteID(_ raw: String) -> String {
        raw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty && $0 != "0" })
            ?? ""
    }

    public static func cleanSiteIDList(_ raw: String) -> String {
        var seen: Set<String> = []
        let items = raw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != "0" && seen.insert($0).inserted }
        return items.joined(separator: ",")
    }

    public static func cleanMAC(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "0" else { return "" }
        return trimmed
    }

    public static func parseLoginResponse(_ data: Data, username: String) throws -> YixiaojiSession {
        let envelope: LoginEnvelope
        do {
            envelope = try JSONDecoder().decode(LoginEnvelope.self, from: data)
        } catch {
            throw YixiaojiAPIError.invalidResponse
        }

        if let errorCode = envelope.errorCode?.intValue, errorCode != 0 {
            throw YixiaojiAPIError.invalidCredentials(envelope.msg ?? "")
        }
        if let code = envelope.code?.intValue, code == 0 {
            throw YixiaojiAPIError.invalidCredentials(envelope.msg ?? "")
        }

        guard let payload = envelope.data else {
            throw YixiaojiAPIError.invalidCredentials(envelope.msg ?? "")
        }

        let uid = payload.uid?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let token = payload.token?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !uid.isEmpty, !token.isEmpty else {
            throw YixiaojiAPIError.invalidCredentials(envelope.msg ?? "")
        }

        return YixiaojiSession(
            uid: uid,
            token: token,
            username: username.trimmingCharacters(in: .whitespacesAndNewlines),
            phone: payload.phone?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            nickname: payload.nickname?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            defaultSiteID: cleanSiteIDList(payload.expressUids?.stringValue ?? ""),
            defaultSiteName: payload.expressName?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        )
    }

    public static func parseUserInfoResponse(
        _ data: Data,
        updating existing: YixiaojiSession
    ) -> YixiaojiSession? {
        guard let envelope = try? JSONDecoder().decode(UserInfoEnvelope.self, from: data),
              envelope.code?.intValue == 1,
              let payload = envelope.data
        else {
            return nil
        }

        var updated = existing
        if let id = payload.id?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty {
            updated.uid = id
        }
        if let token = payload.token?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
            updated.token = token
        }
        if let mobile = payload.mobile?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines), !mobile.isEmpty {
            updated.phone = mobile
        }
        if let nickname = payload.nickname?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines), !nickname.isEmpty {
            updated.nickname = nickname
        }
        let cleanedSiteID = cleanSiteIDList(payload.expressUids?.stringValue ?? "")
        if !cleanedSiteID.isEmpty {
            updated.defaultSiteID = cleanedSiteID
        }
        if let siteName = payload.expressName?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines), !siteName.isEmpty {
            updated.defaultSiteName = siteName
        }
        return updated
    }

    public static func parseSearchResponse(_ data: Data) throws -> [YixiaojiRemoteParcel] {
        let envelope: SearchEnvelope
        do {
            envelope = try JSONDecoder().decode(SearchEnvelope.self, from: data)
        } catch {
            throw YixiaojiAPIError.invalidResponse
        }

        let code = envelope.code?.intValue ?? 0
        if code != 1 {
            let message = envelope.msg?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if isAuthFailureMessage(message) {
                throw YixiaojiAPIError.sessionExpired(message)
            }
            if envelope.data == nil, message.isEmpty {
                return []
            }
            throw YixiaojiAPIError.serverError(message)
        }

        let items = envelope.data ?? []
        return items.compactMap { item -> YixiaojiRemoteParcel? in
            let codeValue = item.takeCode?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let orderSN = item.orderSn?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !codeValue.isEmpty || !orderSN.isEmpty else { return nil }

            return YixiaojiRemoteParcel(
                pickupCode: codeValue,
                trackingNumber: orderSN,
                cabinetName: item.address?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                cabinetMAC: cleanMAC(item.bindMac?.stringValue ?? ""),
                siteID: cleanSiteID(item.expressUids?.stringValue ?? ""),
                mobile: item.mobile?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                isPickedUp: item.isGet?.intValue == 1 || item.isOpen?.intValue == 1
            )
        }
    }

    public static func parseCabinetsResponse(_ data: Data) throws -> (cabinets: [YixiaojiCabinet], defaultSiteID: String) {
        let envelope: LocalizationEnvelope
        do {
            envelope = try JSONDecoder().decode(LocalizationEnvelope.self, from: data)
        } catch {
            throw YixiaojiAPIError.invalidResponse
        }

        guard envelope.code?.intValue == 1, let page = envelope.data else {
            let message = envelope.msg?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if isAuthFailureMessage(message) {
                throw YixiaojiAPIError.sessionExpired(message)
            }
            throw YixiaojiAPIError.serverError(message)
        }

        let defaultSiteID = cleanSiteID(page.expressUids?.stringValue ?? "")
        let cabinets = (page.data ?? []).compactMap { item -> YixiaojiCabinet? in
            let id = item.id?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let name = item.name?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !id.isEmpty, !name.isEmpty else { return nil }
            return YixiaojiCabinet(
                id: id,
                name: name,
                address: item.address?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                city: item.city?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                mac: cleanMAC(item.mac?.stringValue ?? "")
            )
        }
        return (cabinets, defaultSiteID)
    }

    public static func parseUnlockSubmission(_ data: Data) throws -> YixiaojiUnlockSubmission {
        let envelope: UnlockEnvelope
        do {
            envelope = try JSONDecoder().decode(UnlockEnvelope.self, from: data)
        } catch {
            throw YixiaojiAPIError.invalidResponse
        }

        let code = envelope.code?.intValue ?? 0
        let message = envelope.msg?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if code == 0, envelope.data?.isPay?.intValue == 0 {
            return .paymentRequired(
                message: message,
                amount: envelope.data?.money?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                overdueDays: envelope.data?.expireDay?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            )
        }

        if code == 1 {
            let orderSN = envelope.data?.orderSn?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return .submitted(orderSN: orderSN, message: message)
        }

        if isAuthFailureMessage(message) {
            throw YixiaojiAPIError.sessionExpired(message)
        }
        throw YixiaojiAPIError.serverError(message)
    }

    public static func parseCheckOrderResponse(
        _ data: Data,
        fallbackOrderSN: String,
        fallbackMessage: String
    ) throws -> YixiaojiUnlockResult {
        let envelope: CheckOrderEnvelope
        do {
            envelope = try JSONDecoder().decode(CheckOrderEnvelope.self, from: data)
        } catch {
            throw YixiaojiAPIError.invalidResponse
        }

        let code = envelope.code?.intValue ?? 0
        let message = envelope.msg?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard code == 1 else {
            if isAuthFailureMessage(message) {
                throw YixiaojiAPIError.sessionExpired(message)
            }
            throw YixiaojiAPIError.serverError(message.isEmpty ? fallbackMessage : message)
        }

        let boxCode = envelope.data?.boxCode?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let devCode = envelope.data?.devCode?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let compartment = (!boxCode.isEmpty && boxCode != "0") ? boxCode : devCode

        return .opened(
            compartment: compartment,
            message: message.isEmpty ? fallbackMessage : message,
            orderSN: fallbackOrderSN
        )
    }
}

// MARK: - Lossy JSON Helpers

private extension YixiaojiResponseParser {
    static func isAuthFailureMessage(_ message: String) -> Bool {
        let lowered = message.lowercased()
        return message.contains("登录")
            || lowered.contains("token")
            || lowered.contains("unauth")
    }

    struct LossyValue: Decodable {
        let stringValue: String
        let intValue: Int?

        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if container.decodeNil() {
                stringValue = ""
                intValue = nil
            } else if let intVal = try? container.decode(Int.self) {
                stringValue = String(intVal)
                intValue = intVal
            } else if let doubleVal = try? container.decode(Double.self) {
                if doubleVal.rounded() == doubleVal, doubleVal >= Double(Int.min), doubleVal <= Double(Int.max) {
                    let intVal = Int(doubleVal)
                    stringValue = String(intVal)
                    intValue = intVal
                } else {
                    stringValue = String(doubleVal)
                    intValue = nil
                }
            } else if let boolVal = try? container.decode(Bool.self) {
                stringValue = boolVal ? "1" : "0"
                intValue = boolVal ? 1 : 0
            } else if let strVal = try? container.decode(String.self) {
                stringValue = strVal
                intValue = Int(strVal.trimmingCharacters(in: .whitespacesAndNewlines))
            } else {
                stringValue = ""
                intValue = nil
            }
        }
    }

    struct LoginEnvelope: Decodable {
        let code: LossyValue?
        let errorCode: LossyValue?
        let msg: String?
        let data: LoginPayload?
    }

    struct LoginPayload: Decodable {
        let uid: LossyValue?
        let token: LossyValue?
        let phone: LossyValue?
        let expressUids: LossyValue?
        let expressName: LossyValue?
        let nickname: LossyValue?

        enum CodingKeys: String, CodingKey {
            case uid
            case token
            case phone
            case expressUids = "express_uids"
            case expressName = "express_name"
            case nickname
        }
    }

    struct UserInfoEnvelope: Decodable {
        let code: LossyValue?
        let msg: String?
        let data: UserInfoPayload?
    }

    struct UserInfoPayload: Decodable {
        let id: LossyValue?
        let token: LossyValue?
        let mobile: LossyValue?
        let expressUids: LossyValue?
        let expressName: LossyValue?
        let nickname: LossyValue?

        enum CodingKeys: String, CodingKey {
            case id
            case token
            case mobile
            case expressUids = "express_uids"
            case expressName = "express_name"
            case nickname
        }
    }

    struct SearchEnvelope: Decodable {
        let code: LossyValue?
        let msg: String?
        let data: [SearchItemPayload]?
    }

    struct SearchItemPayload: Decodable {
        let takeCode: LossyValue?
        let orderSn: LossyValue?
        let address: LossyValue?
        let bindMac: LossyValue?
        let expressUids: LossyValue?
        let mobile: LossyValue?
        let isGet: LossyValue?
        let isOpen: LossyValue?

        enum CodingKeys: String, CodingKey {
            case takeCode = "take_code"
            case orderSn = "order_sn"
            case address
            case bindMac = "bind_mac"
            case expressUids = "express_uids"
            case mobile
            case isGet = "is_get"
            case isOpen = "is_open"
        }
    }

    struct LocalizationEnvelope: Decodable {
        let code: LossyValue?
        let msg: String?
        let data: LocalizationPagePayload?
    }

    struct LocalizationPagePayload: Decodable {
        let expressUids: LossyValue?
        let data: [LocalizationItemPayload]?

        enum CodingKeys: String, CodingKey {
            case expressUids = "express_uids"
            case data
        }
    }

    struct LocalizationItemPayload: Decodable {
        let id: LossyValue?
        let name: LossyValue?
        let address: LossyValue?
        let city: LossyValue?
        let mac: LossyValue?
    }

    struct UnlockEnvelope: Decodable {
        let code: LossyValue?
        let msg: String?
        let data: UnlockPayload?
    }

    struct UnlockPayload: Decodable {
        let orderSn: LossyValue?
        let isPay: LossyValue?
        let money: LossyValue?
        let expireDay: LossyValue?

        enum CodingKeys: String, CodingKey {
            case orderSn = "order_sn"
            case isPay = "is_pay"
            case money
            case expireDay = "expire_day"
        }
    }

    struct CheckOrderEnvelope: Decodable {
        let code: LossyValue?
        let msg: String?
        let data: CheckOrderPayload?
    }

    struct CheckOrderPayload: Decodable {
        let boxCode: LossyValue?
        let devCode: LossyValue?

        enum CodingKeys: String, CodingKey {
            case boxCode = "box_code"
            case devCode = "dev_code"
        }
    }
}
