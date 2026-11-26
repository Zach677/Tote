import Foundation

public enum DuoduoLinkValidator: Sendable {
    public static let defaultURLString = "pinduoduo://com.xunmeng.pinduoduo/mdkd/package"

    public static func validatedURL(from raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let hasDisallowedScalar = trimmed.unicodeScalars.contains { scalar in
            CharacterSet.whitespacesAndNewlines.contains(scalar)
                || CharacterSet.controlCharacters.contains(scalar)
        }
        guard !hasDisallowedScalar else { return nil }

        guard let separatorRange = trimmed.range(of: "://") else { return nil }
        let scheme = String(trimmed[..<separatorRange.lowerBound])
        guard isValidScheme(scheme) else { return nil }

        guard let url = URL(string: trimmed),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }

        let hasHost = !(components.host ?? "").isEmpty
        let trimmedPath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let hasPath = !trimmedPath.isEmpty
        guard hasHost || hasPath else { return nil }

        return url
    }

    private static func isValidScheme(_ scheme: String) -> Bool {
        guard let first = scheme.unicodeScalars.first, isASCIILetter(first) else {
            return false
        }

        return scheme.unicodeScalars.allSatisfy { scalar in
            isASCIILetter(scalar)
                || isASCIIDigit(scalar)
                || scalar == "+"
                || scalar == "."
                || scalar == "-"
        }
    }

    private static func isASCIILetter(_ scalar: Unicode.Scalar) -> Bool {
        (0x41 ... 0x5A).contains(scalar.value) || (0x61 ... 0x7A).contains(scalar.value)
    }

    private static func isASCIIDigit(_ scalar: Unicode.Scalar) -> Bool {
        (0x30 ... 0x39).contains(scalar.value)
    }
}
