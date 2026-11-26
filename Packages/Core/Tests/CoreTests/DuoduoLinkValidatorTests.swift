import Core
import Foundation
import Testing

@Suite("DuoduoLinkValidator")
struct DuoduoLinkValidatorTests {
    @Test(
        "Accepts valid scheme URLs with host or path and trims outer whitespace",
        arguments: [
            DuoduoLinkValidator.defaultURLString,
            "  pinduoduo://com.xunmeng.pinduoduo/mdkd/package \n",
            "pinduoduo://com.xunmeng.pinduoduo/example/route",
            "pinduoduo:///mdkd/package",
            "my-app+1.0://open/barcode",
        ]
    )
    func acceptsValidURLs(raw: String) throws {
        let url = try #require(DuoduoLinkValidator.validatedURL(from: raw))
        #expect(url.absoluteString == raw.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    @Test(
        "Rejects empty strings, missing separators, bare schemes, internal whitespace, and bad schemes",
        arguments: [
            "",
            "   \n\t ",
            "pinduoduo://",
            "pinduoduo:///",
            "pinduoduo://?tab=barcode",
            "pinduoduo://#barcode",
            "pinduoduo//mdkd/package",
            "foo:bar",
            "com.xunmeng.pinduoduo/mdkd/package",
            "pinduoduo://com.xunmeng.pinduoduo/mdkd package",
            "pinduoduo://com.xunmeng.pinduoduo/mdkd\npackage",
            "123app://host/path",
            "pin_duoduo://host/path",
            "://host/path",
        ]
    )
    func rejectsInvalidURLs(raw: String) {
        #expect(DuoduoLinkValidator.validatedURL(from: raw) == nil, "Expected nil for: \(raw)")
    }
}
