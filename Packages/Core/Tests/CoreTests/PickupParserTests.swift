import Core
import Foundation
import Testing

@Suite("PickupParser")
struct PickupParserTests {
    private let parser = PickupParser()

    // MARK: - All Six Channels

    @Test("Parses all six channels with station labels and codes")
    func parsesAllSixChannels() throws {
        let cases: [(text: String, channel: PickupChannel, code: String, station: String)] = [
            (
                "【多多驿站】您的包裹已到达Demo Station B，取件码12-3-0000，请及时领取。",
                .duoduo,
                "12-3-0000",
                "Demo Station B"
            ),
            (
                "【宜小集】您的包裹已存入Sample Locker A1，凭开柜码A03-8821开柜。",
                .yixiaoji,
                "A03-8821",
                "Sample Locker A1"
            ),
            (
                "【菜鸟驿站】您的包裹已到North Pickup Point，凭取件码4-2-1048领取。",
                .cainiao,
                "4-2-1048",
                "North Pickup Point"
            ),
            (
                "【顺丰速运】您的快件SF0000000000000已存放至West Gate Locker，取件码3-2-0091。",
                .sfExpress,
                "3-2-0091",
                "West Gate Locker"
            ),
            (
                "【京东快递】您的包裹JD0000000000000已送达South Station，提货码5-1-2207。",
                .jd,
                "5-1-2207",
                "South Station"
            ),
            (
                "【校园快递点】您的包裹已到达East Point，核销码C2-15-08，请尽快取件。",
                .other,
                "C2-15-08",
                "East Point"
            ),
        ]

        for item in cases {
            let drafts = parser.parse(item.text)
            let draft = try #require(drafts.first, "Expected a draft for: \(item.text)")
            #expect(drafts.count == 1)
            #expect(draft.channel == item.channel)
            #expect(draft.pickupCode == item.code)
            #expect(draft.stationLabel == item.station)
        }
    }

    @Test("Parses English station and courier messages")
    func parsesEnglishMessages() throws {
        let cainiao = try #require(
            parser.parse("Cainiao: Your parcel arrived at North Pickup Point. Pickup code: 4-2-1048").first
        )
        #expect(cainiao.channel == .cainiao)
        #expect(cainiao.pickupCode == "4-2-1048")
        #expect(cainiao.stationLabel == "North Pickup Point")

        let yixiaoji = try #require(
            parser.parse("Yixiaoji locker ready at Sample Locker A1, code: B12-0457").first
        )
        #expect(yixiaoji.channel == .yixiaoji)
        #expect(yixiaoji.pickupCode == "B12-0457")
        #expect(yixiaoji.stationLabel == "Sample Locker A1")

        let duoduo = try #require(
            parser.parse("Duoduo Station delivered to Demo Station B, code 1-2345").first
        )
        #expect(duoduo.channel == .duoduo)
        #expect(duoduo.pickupCode == "1-2345")
        #expect(duoduo.stationLabel == "Demo Station B")
    }

    // MARK: - Station Precedence Over Carrier Prefix

    @Test("Explicit station keyword overrides carrier tracking prefix and carrier keyword")
    func stationOverridesCarrier() throws {
        let sfAtDuoduo = """
        【多多驿站】您的顺丰包裹(SF0000000000000)已到达Demo Station B，取件码12-3-0000。
        """
        let duoduoDraft = try #require(parser.parse(sfAtDuoduo).first)
        #expect(duoduoDraft.channel == .duoduo)
        #expect(duoduoDraft.pickupCode == "12-3-0000")
        #expect(duoduoDraft.trackingNumber == "SF0000000000000")
        #expect(duoduoDraft.stationLabel == "Demo Station B")

        let jdAtCainiao = """
        【菜鸟驿站】您的京东快递JD0000000000000已到North Pickup Point，取件码4-2-1048。
        """
        let cainiaoDraft = try #require(parser.parse(jdAtCainiao).first)
        #expect(cainiaoDraft.channel == .cainiao)
        #expect(cainiaoDraft.pickupCode == "4-2-1048")
        #expect(cainiaoDraft.trackingNumber == "JD0000000000000")

        let pddBoughtAtCainiao = """
        拼多多买的包裹到了菜鸟驿站，取件码4-2-1048
        """
        let boughtDraft = try #require(parser.parse(pddBoughtAtCainiao).first)
        #expect(boughtDraft.channel == .cainiao)
        #expect(boughtDraft.pickupCode == "4-2-1048")
    }

    // MARK: - Multi-Parcel Paste

    @Test("Parses multiple SMS blocks separated by blank lines or headers")
    func parsesMultiBlockSMS() {
        let text = """
        【多多驿站】您的包裹已到达Demo Station B，取件码12-3-0000。

        【宜小集】您的包裹已存入Sample Locker A1，取件码A03-8821。
        【菜鸟驿站】您的包裹已到North Pickup Point，取件码4-2-1048。
        """

        let drafts = parser.parse(text)
        #expect(drafts.count == 3)
        #expect(drafts.map(\.channel) == [.duoduo, .yixiaoji, .cainiao])
        #expect(drafts.map(\.pickupCode) == ["12-3-0000", "A03-8821", "4-2-1048"])
        #expect(drafts.map(\.stationLabel) == ["Demo Station B", "Sample Locker A1", "North Pickup Point"])
    }

    @Test("Parses multiple codes inside one SMS and family-forwarded lists")
    func parsesMultiCodeMessageAndFamilyList() {
        let singleSMS = "【多多驿站】您的2个包裹已到达Demo Station B，取件码12-3-0000、4-2-1048，请及时领取。"
        let smsDrafts = parser.parse(singleSMS)
        #expect(smsDrafts.count == 2)
        #expect(smsDrafts.map(\.pickupCode) == ["12-3-0000", "4-2-1048"])
        #expect(smsDrafts.allSatisfy { $0.channel == .duoduo && $0.stationLabel == "Demo Station B" })

        let familyPreamble = """
        今天两个快递到了菜鸟驿站：
        12-3-0000
        4-2-1048
        """
        let familyDrafts = parser.parse(familyPreamble)
        #expect(familyDrafts.count == 2)
        #expect(familyDrafts.map(\.pickupCode) == ["12-3-0000", "4-2-1048"])
        #expect(familyDrafts.allSatisfy { $0.channel == .cainiao })
    }

    @Test("Keeps multi-line single SMS fields together while splitting bare lists")
    func multiLineSMSVsBareList() throws {
        let multiLineSMS = """
        【多多驿站】您的包裹已到达Demo Station B
        取件码：12-3-0000
        运单号：YT0000000000000
        """
        let smsDrafts = parser.parse(multiLineSMS)
        let combined = try #require(smsDrafts.first)
        #expect(smsDrafts.count == 1)
        #expect(combined.channel == .duoduo)
        #expect(combined.pickupCode == "12-3-0000")
        #expect(combined.trackingNumber == "YT0000000000000")
        #expect(combined.stationLabel == "Demo Station B")

        let bareList = """
        12-3-0000
        4-2-1048
        YT0000000000000
        """
        let listDrafts = parser.parse(bareList)
        #expect(listDrafts.count == 3)
        #expect(listDrafts[0].pickupCode == "12-3-0000")
        #expect(listDrafts[1].pickupCode == "4-2-1048")
        #expect(listDrafts[2].isTrackingOnly)
        #expect(listDrafts[2].trackingNumber == "YT0000000000000")
    }

    // MARK: - Standalone Codes & Fullwidth Normalization

    @Test("Parses standalone pickup codes and channel shorthand")
    func parsesStandaloneCodes() throws {
        let hyphenated = try #require(parser.parse("12-3-0000").first)
        #expect(hyphenated.pickupCode == "12-3-0000")
        #expect(hyphenated.channel == .other)

        let alphaHyphenated = try #require(parser.parse("A03-8821").first)
        #expect(alphaHyphenated.pickupCode == "A03-8821")

        let sixDigit = try #require(parser.parse("884210").first)
        #expect(sixDigit.pickupCode == "884210")

        let channelShorthand = try #require(parser.parse("宜小集 884210").first)
        #expect(channelShorthand.channel == .yixiaoji)
        #expect(channelShorthand.pickupCode == "884210")
    }

    @Test("Normalizes fullwidth digits, letters, and dashes")
    func normalizesFullwidthCharacters() throws {
        let text = "【宜小集】开柜码：Ａ０３—８８２１，运单号：ＳＦ０００００００００００００"
        let draft = try #require(parser.parse(text).first)
        #expect(draft.channel == .yixiaoji)
        #expect(draft.pickupCode == "A03-8821")
        #expect(draft.trackingNumber == "SF0000000000000")

        let fullwidthShelf = try #require(parser.parse("１２－３－００００").first)
        #expect(fullwidthShelf.pickupCode == "12-3-0000")
    }

    // MARK: - Tracking-Only Waybills

    @Test("Extracts carrier-prefixed, labeled, and standalone numeric waybills")
    func extractsTrackingNumbers() throws {
        let cases: [(input: String, tracking: String, channel: PickupChannel)] = [
            ("SF0000000000000", "SF0000000000000", .sfExpress),
            ("JD0000000000000", "JD0000000000000", .jd),
            ("JDVA0000000000", "JDVA0000000000", .jd),
            ("YT0000000000000", "YT0000000000000", .other),
            ("JT0000000000000", "JT0000000000000", .other),
            ("DPK000000000000", "DPK000000000000", .other),
            ("EA000000000CN", "EA000000000CN", .other),
            ("75000000000000", "75000000000000", .other),
            ("快递单号：7700000000000", "7700000000000", .other),
        ]

        for item in cases {
            let drafts = parser.parse(item.input)
            let draft = try #require(drafts.first, "Expected tracking draft for: \(item.input)")
            #expect(drafts.count == 1)
            #expect(draft.isTrackingOnly)
            #expect(draft.trackingNumber == item.tracking)
            #expect(draft.channel == item.channel)
        }
    }

    // MARK: - Intra-Input Deduplication

    @Test("Deduplicates repeated codes and merges tracking-only with code message in one paste")
    func deduplicatesIntraInput() throws {
        let repeated = "【多多驿站】取件码12-3-0000，请凭12-3-0000到Demo Station B领取。"
        let repeatedDrafts = parser.parse(repeated)
        #expect(repeatedDrafts.count == 1)
        #expect(repeatedDrafts[0].pickupCode == "12-3-0000")

        let pairedPaste = """
        YT0000000000000

        【多多驿站】您的包裹YT0000000000000已到达Demo Station B，取件码12-3-0000。
        """
        let merged = parser.parse(pairedPaste)
        let draft = try #require(merged.first)
        #expect(merged.count == 1)
        #expect(draft.channel == .duoduo)
        #expect(draft.pickupCode == "12-3-0000")
        #expect(draft.trackingNumber == "YT0000000000000")
        #expect(draft.stationLabel == "Demo Station B")
    }

    // MARK: - False-Positive Rejections

    @Test(
        "Rejects empty text, dates, times, prices, phones, OTPs, and plain conversation",
        arguments: [
            "",
            "   \n\t  ",
            "2026-11-26",
            "11-26",
            "18:20",
            "营业时间 08:30-21:00",
            "¥29.90",
            "一共 29.9元",
            "13800000000",
            "138-0000-0000",
            "取件码：138-000-00000",
            "取件码：11-26",
            "联系电话 138-0000-0000 客服 400-000-0000",
            "您的登录验证码是123456，5分钟内有效。",
            "Verification code: 654321",
            "Your invite code is AB1234",
            "Use referral code: 884210",
            "Can you get the blue box for me later? Thanks!",
            "2026",
            "Pick up in 3-day window for Phase-1.",
        ]
    )
    func rejectsFalsePositives(input: String) {
        #expect(parser.parse(input).isEmpty, "Unexpected parse result for: \(input)")
    }

    @Test("Ignores phone numbers, times, and dates inside a real pickup SMS")
    func ignoresNoiseInsideRealSMS() throws {
        let sms = """
        【菜鸟驿站】2026-11-26 18:20 您的尾号0000包裹已到达North Pickup Point（营业时间08:30-21:00），取件码4-2-1048，详询13800000000，超期2.5元/天。
        """
        let drafts = parser.parse(sms)
        let draft = try #require(drafts.first)
        #expect(drafts.count == 1)
        #expect(draft.channel == .cainiao)
        #expect(draft.pickupCode == "4-2-1048")
        #expect(draft.trackingNumber.isEmpty)
        #expect(draft.stationLabel == "North Pickup Point")
    }

    @Test("Handles concatenated single-line SMS blocks, bracketed codes, and temporal phrases")
    func parsesConcatenatedAndTrickySMSForms() throws {
        let concatenated = "【菜鸟驿站】请在3天内到North Pickup Point取件，取件码【4-2-1048】。【多多驿站】您的包裹已到达Demo Station B，取件码(12-3-0000)。"
        let drafts = parser.parse(concatenated)
        #expect(drafts.count == 2)
        #expect(drafts[0].channel == .cainiao)
        #expect(drafts[0].pickupCode == "4-2-1048")
        #expect(drafts[0].stationLabel == "North Pickup Point")
        #expect(drafts[1].channel == .duoduo)
        #expect(drafts[1].pickupCode == "12-3-0000")
        #expect(drafts[1].stationLabel == "Demo Station B")

        let twoWaybills = parser.parse("SF0000000000000, JD0000000000000")
        #expect(twoWaybills.count == 2)
        #expect(twoWaybills[0].channel == .sfExpress)
        #expect(twoWaybills[0].trackingNumber == "SF0000000000000")
        #expect(twoWaybills[1].channel == .jd)
        #expect(twoWaybills[1].trackingNumber == "JD0000000000000")

        let englishIsCode = try #require(parser.parse("Duoduo Station pickup code is 884210").first)
        #expect(englishIsCode.channel == .duoduo)
        #expect(englishIsCode.pickupCode == "884210")

        #expect(parser.parse("Your verification code is 654321").isEmpty)
    }

    @Test("Does not leak first multi-line SMS channel or station into subsequent other-channel SMS")
    func doesNotLeakMultiLineTaggedSMSIntoNextSMS() {
        let withStation = """
        【多多驿站】您的包裹已到达Demo Station B
        取件码：12-3-0000
        【校园快递点】您的包裹已到达East Point，核销码C2-15-08
        """
        let drafts1 = parser.parse(withStation)
        #expect(drafts1.count == 2)
        #expect(drafts1[0].channel == .duoduo)
        #expect(drafts1[0].stationLabel == "Demo Station B")
        #expect(drafts1[1].channel == .other)
        #expect(drafts1[1].pickupCode == "C2-15-08")
        #expect(drafts1[1].stationLabel == "East Point")

        let withoutStation = """
        【多多驿站】您的包裹已到达Demo Station B
        取件码：12-3-0000
        【校园快递点】核销码C2-15-08，请尽快取件。
        """
        let drafts2 = parser.parse(withoutStation)
        #expect(drafts2.count == 2)
        #expect(drafts2[1].channel == .other)
        #expect(drafts2[1].pickupCode == "C2-15-08")
        #expect(drafts2[1].stationLabel.isEmpty)
    }

    @Test("Preserves 12-digit labeled codes while masking 11-digit hyphenated mobile numbers")
    func preservesTwelveDigitCodeAndRejectsElevenDigitHyphenatedMobile() {
        let twelveDigit = parser.parse("【多多驿站】取件码：1380-0000-0000")
        #expect(twelveDigit.map(\.pickupCode) == ["1380-0000-0000"])

        let smsWithHyphenatedMobile = parser.parse("快递员138-0000-0000，取件码12-3-0000")
        #expect(smsWithHyphenatedMobile.map(\.pickupCode) == ["12-3-0000"])
    }

    @Test("Splits bare tracking and bare code lines symmetrically regardless of order")
    func splitsBareTrackingAndBareCodeSymmetrically() {
        let codeThenTracking = parser.parse("12-3-0000\nYT0000000000000")
        let trackingThenCode = parser.parse("YT0000000000000\n12-3-0000")

        #expect(codeThenTracking.count == 2)
        #expect(trackingThenCode.count == 2)
        #expect(trackingThenCode[0].isTrackingOnly)
        #expect(trackingThenCode[0].trackingNumber == "YT0000000000000")
        #expect(trackingThenCode[1].pickupCode == "12-3-0000")
        #expect(trackingThenCode[1].trackingNumber.isEmpty)
    }
}
