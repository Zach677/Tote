import Foundation

public struct PickupParser: Sendable {
    public init() {}

    public func parse(_ text: String) -> [ParsedParcelDraft] {
        let standardized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !standardized.isEmpty else { return [] }

        let segments = splitIntoSegments(standardized)
        var rawDrafts: [ParsedParcelDraft] = []

        for segment in segments {
            rawDrafts.append(contentsOf: parseSegment(segment))
        }

        return deduplicateIntraInput(rawDrafts)
    }
}

// MARK: - Segmentation

private extension PickupParser {
    struct Segment {
        var text: String
        var inheritedChannel: PickupChannel?
        var inheritedStation: String
    }

    struct LineInspection {
        var rawLine: String
        var hasCode: Bool
        var hasTracking: Bool
        var hasLabeledTracking: Bool
        var explicitChannel: PickupChannel?
        var station: String
        var startsWithHeaderTag: Bool
        var isBareCodeOnly: Bool
        var isBareTrackingOnly: Bool
    }

    func splitIntoSegments(_ text: String) -> [Segment] {
        let paragraphs = splitParagraphs(text)
        var segments: [Segment] = []

        for paragraph in paragraphs {
            let expanded = splitConcatenatedSMSHeaders(in: paragraph)
            let lines = expanded
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            guard !lines.isEmpty else { continue }

            let inspections = lines.map(inspectLine)
            segments.append(contentsOf: groupLines(inspections))
        }

        return segments
    }

    func splitParagraphs(_ text: String) -> [String] {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        var paragraphs: [String] = []
        var current: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                if !current.isEmpty {
                    paragraphs.append(current.joined(separator: "\n"))
                    current.removeAll()
                }
            } else {
                current.append(String(line))
            }
        }

        if !current.isEmpty {
            paragraphs.append(current.joined(separator: "\n"))
        }

        return paragraphs
    }

    func splitConcatenatedSMSHeaders(in paragraph: String) -> String {
        let nsRange = NSRange(paragraph.startIndex..., in: paragraph)
        return Patterns.concatenatedHeader.stringByReplacingMatches(
            in: paragraph,
            options: [],
            range: nsRange,
            withTemplate: "$1\n$2"
        )
    }

    func inspectLine(_ line: String) -> LineInspection {
        let normalized = ParcelNormalization.normalizeFullwidthAndDashes(line)
        let masked = computeMaskedRanges(in: normalized)
        let trackings = extractTrackingNumbers(in: normalized, maskedRanges: masked)
        let trackingSpans = trackings.map(\.range)
        let codes = extractPickupCodes(
            in: normalized,
            maskedRanges: masked + trackingSpans,
            allowStandalone: trackings.isEmpty
        )
        let explicitChannel = detectExplicitChannel(in: normalized)
        let station = extractStationLabel(in: line, normalized: normalized)
        let startsWithHeaderTag = line.hasPrefix("【") || line.hasPrefix("[")

        let isBareCodeOnly = codes.count == 1 && trackings.isEmpty && isStandaloneLine(normalized, matching: codes[0].range)
        let isBareTrackingOnly = trackings.count == 1 && codes.isEmpty && !trackings[0].isLabeled && isStandaloneLine(normalized, matching: trackings[0].range)

        return LineInspection(
            rawLine: line,
            hasCode: !codes.isEmpty,
            hasTracking: !trackings.isEmpty,
            hasLabeledTracking: trackings.contains(where: \.isLabeled),
            explicitChannel: explicitChannel,
            station: station,
            startsWithHeaderTag: startsWithHeaderTag,
            isBareCodeOnly: isBareCodeOnly,
            isBareTrackingOnly: isBareTrackingOnly
        )
    }

    func isStandaloneLine(_ text: String, matching range: Range<String.Index>) -> Bool {
        let before = text[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        let after = text[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        return before.isEmpty && after.isEmpty
    }

    func groupLines(_ inspections: [LineInspection]) -> [Segment] {
        // Capture leading context-only lines (e.g. a family header line naming the station)
        // only when the paragraph does not start with an independent SMS header tag.
        var preambleChannel: PickupChannel?
        var preambleStation = ""
        if inspections.first?.startsWithHeaderTag == false {
            for item in inspections {
                if item.hasCode || item.hasTracking {
                    break
                }
                if preambleChannel == nil, let channel = item.explicitChannel {
                    preambleChannel = channel
                }
                if preambleStation.isEmpty, !item.station.isEmpty {
                    preambleStation = item.station
                }
            }
        }

        var segments: [Segment] = []
        var buffer: [LineInspection] = []

        func flushBuffer() {
            guard !buffer.isEmpty else { return }
            let joined = buffer.map(\.rawLine).joined(separator: "\n")
            let isIndependentTaggedSMS = buffer.first?.startsWithHeaderTag == true
            segments.append(
                Segment(
                    text: joined,
                    inheritedChannel: isIndependentTaggedSMS ? nil : preambleChannel,
                    inheritedStation: isIndependentTaggedSMS ? "" : preambleStation
                )
            )
            buffer.removeAll()
        }

        for item in inspections {
            guard !buffer.isEmpty else {
                buffer.append(item)
                continue
            }

            let bufferHasCode = buffer.contains(where: \.hasCode)
            let bufferHasTracking = buffer.contains(where: \.hasTracking)
            let bufferStartedWithHeader = buffer.first?.startsWithHeaderTag == true
            let bufferChannel = buffer.compactMap(\.explicitChannel).first
            let bufferIsBareCode = buffer.count == 1 && buffer[0].isBareCodeOnly
            let bufferIsBareTracking = buffer.count == 1 && buffer[0].isBareTrackingOnly

            let startsNewSMS = item.startsWithHeaderTag && (bufferHasCode || bufferHasTracking || bufferStartedWithHeader)
            let secondCodeLine = item.hasCode && bufferHasCode
            let secondTrackingLine = item.hasTracking && !item.hasCode && bufferHasTracking
            let bareTrackingAfterBareCode = item.isBareTrackingOnly && bufferIsBareCode
            let bareCodeAfterBareTracking = item.isBareCodeOnly && bufferIsBareTracking
            let channelSwitch = item.explicitChannel != nil
                && bufferChannel != nil
                && item.explicitChannel != bufferChannel
                && (bufferHasCode || bufferHasTracking)

            if startsNewSMS || secondCodeLine || secondTrackingLine || bareTrackingAfterBareCode || bareCodeAfterBareTracking || channelSwitch {
                flushBuffer()
            }

            buffer.append(item)
        }

        flushBuffer()
        return segments
    }
}

// MARK: - Segment Parsing

private extension PickupParser {
    struct MatchedToken {
        var value: String
        var range: Range<String.Index>
        var isLabeled: Bool
    }

    func parseSegment(_ segment: Segment) -> [ParsedParcelDraft] {
        let normalized = ParcelNormalization.normalizeFullwidthAndDashes(segment.text)
        let maskedRanges = computeMaskedRanges(in: normalized)

        let trackingMatches = deduplicateMatches(
            extractTrackingNumbers(in: normalized, maskedRanges: maskedRanges),
            normalizer: ParcelNormalization.normalizeTrackingNumber
        )
        let trackingSpans = trackingMatches.map(\.range)

        let codeMatches = deduplicateMatches(
            extractPickupCodes(
                in: normalized,
                maskedRanges: maskedRanges + trackingSpans,
                allowStandalone: trackingMatches.isEmpty
            ),
            normalizer: ParcelNormalization.normalizePickupCode
        )

        guard !codeMatches.isEmpty || !trackingMatches.isEmpty else { return [] }

        let explicitChannel = detectExplicitChannel(in: normalized) ?? segment.inheritedChannel
        let station = extractStationLabel(in: segment.text, normalized: normalized)
        let resolvedStation = station.isEmpty ? segment.inheritedStation : station

        if codeMatches.isEmpty {
            return trackingMatches.map { tracking in
                let channel = explicitChannel ?? inferChannel(fromTrackingNumber: tracking.value) ?? .other
                return ParsedParcelDraft(
                    pickupCode: "",
                    trackingNumber: tracking.value,
                    channel: channel,
                    stationLabel: resolvedStation,
                    note: ""
                )
            }
        }

        if codeMatches.count == 1 {
            let trackingValue = trackingMatches.first?.value ?? ""
            let channel = explicitChannel
                ?? inferChannel(fromTrackingNumber: trackingValue)
                ?? inferChannel(fromPickupCode: codeMatches[0].value)
                ?? .other
            return [
                ParsedParcelDraft(
                    pickupCode: codeMatches[0].value,
                    trackingNumber: trackingValue,
                    channel: channel,
                    stationLabel: resolvedStation,
                    note: ""
                ),
            ]
        }

        if trackingMatches.count == codeMatches.count {
            return zip(codeMatches, trackingMatches).map { code, tracking in
                let channel = explicitChannel
                    ?? inferChannel(fromTrackingNumber: tracking.value)
                    ?? inferChannel(fromPickupCode: code.value)
                    ?? .other
                return ParsedParcelDraft(
                    pickupCode: code.value,
                    trackingNumber: tracking.value,
                    channel: channel,
                    stationLabel: resolvedStation,
                    note: ""
                )
            }
        }

        return codeMatches.enumerated().map { index, code in
            let trackingValue = (index == 0 && trackingMatches.count == 1) ? trackingMatches[0].value : ""
            let channel = explicitChannel
                ?? inferChannel(fromTrackingNumber: trackingValue)
                ?? inferChannel(fromPickupCode: code.value)
                ?? .other
            return ParsedParcelDraft(
                pickupCode: code.value,
                trackingNumber: trackingValue,
                channel: channel,
                stationLabel: resolvedStation,
                note: ""
            )
        }
    }

    func deduplicateMatches(
        _ matches: [MatchedToken],
        normalizer: (String) -> String
    ) -> [MatchedToken] {
        var seen: Set<String> = []
        var unique: [MatchedToken] = []

        for match in matches {
            let key = normalizer(match.value)
            guard !key.isEmpty, seen.insert(key).inserted else { continue }
            unique.append(match)
        }

        return unique
    }
}

// MARK: - Channel Detection

private extension PickupParser {
    func detectExplicitChannel(in normalized: String) -> PickupChannel? {
        // Explicit physical pickup points always outrank courier brands and tracking prefixes
        // so an SF or JD parcel delivered to a station or locker groups under its pickup point.
        if let pickupPoint = earliestMatch(in: normalized, rules: ChannelRules.explicitPickupPoints) {
            return pickupPoint
        }
        if let secondaryStation = earliestMatch(in: normalized, rules: ChannelRules.secondaryStationHints) {
            return secondaryStation
        }
        if let courierChannel = earliestMatch(in: normalized, rules: ChannelRules.couriers) {
            return courierChannel
        }
        if let standaloneStation = earliestMatch(in: normalized, rules: ChannelRules.standaloneStationHints) {
            return standaloneStation
        }
        return nil
    }

    func earliestMatch(
        in text: String,
        rules: [(regex: NSRegularExpression, channel: PickupChannel)]
    ) -> PickupChannel? {
        let nsRange = NSRange(text.startIndex..., in: text)
        var bestLocation = Int.max
        var bestChannel: PickupChannel?

        for rule in rules {
            guard let match = rule.regex.firstMatch(in: text, options: [], range: nsRange) else {
                continue
            }
            if match.range.location < bestLocation {
                bestLocation = match.range.location
                bestChannel = rule.channel
            }
        }

        return bestChannel
    }

    func inferChannel(fromTrackingNumber trackingNumber: String) -> PickupChannel? {
        let normalized = ParcelNormalization.normalizeTrackingNumber(trackingNumber)
        guard !normalized.isEmpty else { return nil }
        if normalized.hasPrefix("SF") {
            return .sfExpress
        }
        if normalized.hasPrefix("JD") {
            return .jd
        }
        return nil
    }

    func inferChannel(fromPickupCode pickupCode: String) -> PickupChannel? {
        let cleaned = ParcelNormalization.normalizePickupCode(pickupCode)
        guard !cleaned.isEmpty else { return nil }

        if matchesWhole(cleaned, regex: Patterns.stationShelfCode) {
            return .station
        }
        if matchesWhole(cleaned, regex: Patterns.lockerEightDigitCode) {
            return .locker
        }
        if matchesWhole(cleaned, regex: Patterns.jdTwoPartCode) {
            return .jd
        }
        if matchesWhole(cleaned, regex: Patterns.sfFourDigitCode) {
            return .sfExpress
        }
        return nil
    }
}

// MARK: - Noise Masking

private extension PickupParser {
    func computeMaskedRanges(in normalized: String) -> [Range<String.Index>] {
        let nsRange = NSRange(normalized.startIndex..., in: normalized)
        var ranges: [Range<String.Index>] = []

        for regex in Patterns.noisePatterns {
            for match in regex.matches(in: normalized, options: [], range: nsRange) {
                if let range = Range(match.range, in: normalized) {
                    ranges.append(range)
                }
            }
        }

        return ranges
    }

    func overlaps(_ range: Range<String.Index>, maskedRanges: [Range<String.Index>]) -> Bool {
        maskedRanges.contains { $0.overlaps(range) }
    }
}

// MARK: - Tracking Extraction

private extension PickupParser {
    func extractTrackingNumbers(
        in normalized: String,
        maskedRanges: [Range<String.Index>]
    ) -> [MatchedToken] {
        let nsRange = NSRange(normalized.startIndex..., in: normalized)
        var tokens: [MatchedToken] = []

        // 1. Labeled tracking numbers
        for match in Patterns.labeledTracking.matches(in: normalized, options: [], range: nsRange) {
            guard match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: normalized),
                  !overlaps(range, maskedRanges: maskedRanges)
            else { continue }

            let candidate = ParcelNormalization.cleanDisplayTrackingNumber(String(normalized[range]))
            guard isValidTrackingCandidate(candidate) else { continue }
            tokens.append(MatchedToken(value: candidate, range: range, isLabeled: true))
        }

        // 2. Carrier-prefixed waybills
        for match in Patterns.carrierTracking.matches(in: normalized, options: [], range: nsRange) {
            guard let range = Range(match.range, in: normalized),
                  !overlaps(range, maskedRanges: maskedRanges),
                  !overlaps(range, maskedRanges: tokens.map(\.range))
            else { continue }

            let candidate = ParcelNormalization.cleanDisplayTrackingNumber(String(normalized[range]))
            tokens.append(MatchedToken(value: candidate, range: range, isLabeled: false))
        }

        // 3. Standalone 12-16 digit numeric waybills
        for match in Patterns.numericTracking.matches(in: normalized, options: [], range: nsRange) {
            guard let range = Range(match.range, in: normalized),
                  !overlaps(range, maskedRanges: maskedRanges),
                  !overlaps(range, maskedRanges: tokens.map(\.range))
            else { continue }

            let candidate = ParcelNormalization.cleanDisplayTrackingNumber(String(normalized[range]))
            guard !isMobilePhoneNumber(candidate) else { continue }
            tokens.append(MatchedToken(value: candidate, range: range, isLabeled: false))
        }

        return tokens.sorted { $0.range.lowerBound < $1.range.lowerBound }
    }

    func isValidTrackingCandidate(_ candidate: String) -> Bool {
        let stripped = candidate.replacingOccurrences(of: "-", with: "")
        guard stripped.count >= 10, stripped.count <= 18 else { return false }
        guard !isMobilePhoneNumber(stripped) else { return false }
        let digitCount = stripped.unicodeScalars.filter { ("0" ... "9").contains(Character($0)) }.count
        return digitCount >= 6
    }

    func isMobilePhoneNumber(_ digits: String) -> Bool {
        guard digits.count == 11 else { return false }
        let nsRange = NSRange(digits.startIndex..., in: digits)
        return Patterns.mobilePhone.firstMatch(in: digits, options: [], range: nsRange) != nil
    }
}

// MARK: - Pickup Code Extraction

private extension PickupParser {
    func extractPickupCodes(
        in normalized: String,
        maskedRanges: [Range<String.Index>],
        allowStandalone: Bool
    ) -> [MatchedToken] {
        let nsRange = NSRange(normalized.startIndex..., in: normalized)
        var tokens: [MatchedToken] = []

        // 1. Keyword-labeled pickup codes (including comma/enumeration-separated lists)
        for match in Patterns.labeledCodePrefix.matches(in: normalized, options: [], range: nsRange) {
            guard let prefixRange = Range(match.range, in: normalized) else { continue }
            var cursor = prefixRange.upperBound
            var matchedCount = 0

            while cursor < normalized.endIndex {
                let tailNSRange = NSRange(cursor ..< normalized.endIndex, in: normalized)
                let connectorRegex = matchedCount == 0 ? Patterns.initialCodeConnector : Patterns.listCodeSeparator

                if let connectorMatch = connectorRegex.firstMatch(in: normalized, options: [.anchored], range: tailNSRange),
                   let connectorRange = Range(connectorMatch.range, in: normalized)
                {
                    cursor = connectorRange.upperBound
                } else if matchedCount > 0 {
                    break
                }

                let candidateTail = NSRange(cursor ..< normalized.endIndex, in: normalized)
                guard let codeMatch = Patterns.labeledCodeToken.firstMatch(in: normalized, options: [.anchored], range: candidateTail),
                      let codeRange = Range(codeMatch.range, in: normalized)
                else { break }

                if overlaps(codeRange, maskedRanges: maskedRanges) || overlaps(codeRange, maskedRanges: tokens.map(\.range)) {
                    break
                }

                let candidate = ParcelNormalization.cleanDisplayCode(String(normalized[codeRange]))
                guard isValidLabeledCode(candidate) else { break }

                tokens.append(MatchedToken(value: candidate, range: codeRange, isLabeled: true))
                matchedCount += 1
                cursor = codeRange.upperBound
            }
        }

        // 1b. Reversed Chinese phrasing such as "凭884210取件"
        for match in Patterns.pingActionCode.matches(in: normalized, options: [], range: nsRange) {
            guard match.numberOfRanges > 1,
                  let codeRange = Range(match.range(at: 1), in: normalized),
                  !overlaps(codeRange, maskedRanges: maskedRanges),
                  !overlaps(codeRange, maskedRanges: tokens.map(\.range))
            else { continue }

            let candidate = ParcelNormalization.cleanDisplayCode(String(normalized[codeRange]))
            guard isValidLabeledCode(candidate) else { continue }
            tokens.append(MatchedToken(value: candidate, range: codeRange, isLabeled: true))
        }

        // 2. Unlabeled hyphenated shelf/locker codes
        for match in Patterns.hyphenatedCode.matches(in: normalized, options: [], range: nsRange) {
            guard let codeRange = Range(match.range, in: normalized),
                  !overlaps(codeRange, maskedRanges: maskedRanges),
                  !overlaps(codeRange, maskedRanges: tokens.map(\.range))
            else { continue }

            let candidate = ParcelNormalization.cleanDisplayCode(String(normalized[codeRange]))
            guard isValidUnlabeledHyphenatedCode(candidate) else { continue }
            tokens.append(MatchedToken(value: candidate, range: codeRange, isLabeled: false))
        }

        // 3. Standalone bare code (or channel keyword + bare code) when nothing else matched
        if tokens.isEmpty, allowStandalone {
            if let standalone = extractStandaloneCode(in: normalized, maskedRanges: maskedRanges) {
                tokens.append(standalone)
            }
        }

        return tokens.sorted { $0.range.lowerBound < $1.range.lowerBound }
    }

    func isValidLabeledCode(_ candidate: String) -> Bool {
        guard candidate.count >= 4, candidate.count <= 16 else { return false }
        guard !isMobilePhoneNumber(candidate.replacingOccurrences(of: "-", with: "")) else { return false }
        guard !looksLikeCalendarDate(candidate) else { return false }
        return candidate.unicodeScalars.contains { ("0" ... "9").contains(Character($0)) }
    }

    func isValidUnlabeledHyphenatedCode(_ candidate: String) -> Bool {
        guard candidate.count >= 4, candidate.count <= 16 else { return false }
        guard !isMobilePhoneNumber(candidate.replacingOccurrences(of: "-", with: "")) else { return false }
        guard !looksLikeCalendarDate(candidate) else { return false }

        let parts = candidate.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 2, parts.count <= 4 else { return false }
        guard parts.allSatisfy({ !$0.isEmpty }) else { return false }

        let digitCount = candidate.unicodeScalars.filter { ("0" ... "9").contains(Character($0)) }.count
        guard digitCount >= 3 else { return false }

        if parts.count == 2 {
            let first = parts[0]
            let second = parts[1]
            let firstValid = matchesWhole(first, regex: Patterns.twoPartFirst)
            let secondValid = matchesWhole(second, regex: Patterns.twoPartSecond)
            return firstValid && secondValid
        }

        return parts.allSatisfy { matchesWhole($0, regex: Patterns.multiPartSegment) }
    }

    func looksLikeCalendarDate(_ candidate: String) -> Bool {
        let parts = candidate.split(separator: "-")
        if parts.count == 3,
           let year = Int(parts[0]), (1900 ... 2099).contains(year),
           let month = Int(parts[1]), (1 ... 12).contains(month),
           let day = Int(parts[2]), (1 ... 31).contains(day)
        {
            return true
        }
        if parts.count == 2,
           parts[0].count <= 2, parts[1].count <= 2,
           let month = Int(parts[0]), (1 ... 12).contains(month),
           let day = Int(parts[1]), (1 ... 31).contains(day)
        {
            return true
        }
        return false
    }

    func extractStandaloneCode(
        in normalized: String,
        maskedRanges: [Range<String.Index>]
    ) -> MatchedToken? {
        let trimmed = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("\n") else { return nil }

        let fullRange = normalized.startIndex ..< normalized.endIndex
        guard !overlaps(fullRange, maskedRanges: maskedRanges) else { return nil }

        if isValidStandaloneToken(trimmed) {
            return MatchedToken(
                value: ParcelNormalization.cleanDisplayCode(trimmed),
                range: fullRange,
                isLabeled: false
            )
        }

        // Allow "<Channel> <6-8 digit code>" shorthand such as "宜小集 884210"
        let nsRange = NSRange(trimmed.startIndex..., in: trimmed)
        let stripped = Patterns.leadingOrTrailingChannel.stringByReplacingMatches(
            in: trimmed,
            options: [],
            range: nsRange,
            withTemplate: ""
        ).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ":：")))

        guard !stripped.isEmpty, stripped != trimmed, isValidStandaloneToken(stripped) else {
            return nil
        }

        let tokenRange = normalized.range(of: stripped) ?? fullRange
        guard !overlaps(tokenRange, maskedRanges: maskedRanges) else { return nil }

        return MatchedToken(
            value: ParcelNormalization.cleanDisplayCode(stripped),
            range: tokenRange,
            isLabeled: false
        )
    }

    func isValidStandaloneToken(_ token: String) -> Bool {
        if matchesWhole(token, regex: Patterns.sfFourDigitCode) {
            return !looksLikeCalendarYear(token)
        }
        return matchesWhole(token, regex: Patterns.standaloneDigits)
            || matchesWhole(token, regex: Patterns.standaloneAlphanumeric)
    }

    func looksLikeCalendarYear(_ token: String) -> Bool {
        guard token.count == 4, let year = Int(token) else { return false }
        return (1900 ... 2099).contains(year)
    }

    func matchesWhole(_ text: String, regex: NSRegularExpression) -> Bool {
        let nsRange = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: nsRange) else {
            return false
        }
        return match.range.location == 0 && match.range.length == nsRange.length
    }
}

// MARK: - Station Label Extraction

private extension PickupParser {
    func extractStationLabel(in original: String, normalized: String) -> String {
        let sources = [original, normalized]
        for source in sources {
            let nsRange = NSRange(source.startIndex..., in: source)
            for regex in Patterns.stationPatterns {
                for match in regex.matches(in: source, options: [], range: nsRange) {
                    guard match.numberOfRanges > 1,
                          let range = Range(match.range(at: 1), in: source)
                    else { continue }

                    let candidate = cleanStationCandidate(String(source[range]))
                    if isValidStationLabel(candidate) {
                        return candidate
                    }
                }
            }
        }
        return ""
    }

    func cleanStationCandidate(_ raw: String) -> String {
        let trimSet = CharacterSet.whitespacesAndNewlines
            .union(CharacterSet(charactersIn: ":：,，.。;；!！?？【】[]()（）\"'“”「」"))
        return raw.trimmingCharacters(in: trimSet)
    }

    func isValidStationLabel(_ candidate: String) -> Bool {
        guard candidate.count >= 2, candidate.count <= 40 else { return false }
        let lowered = candidate.lowercased()

        let blockedSubstrings = [
            "取件码", "取货码", "提货码", "开柜码", "核销码", "运单号", "单号",
            "pickup code", "tracking", "http://", "https://", "时间",
        ]
        if blockedSubstrings.contains(where: { lowered.contains($0) }) {
            return false
        }

        let blockedPrefixes = ["您的", "请", "凭", "您", "预计", "已", "the ", "your "]
        if blockedPrefixes.contains(where: { lowered.hasPrefix($0) }) {
            return false
        }

        let nsRange = NSRange(candidate.startIndex..., in: candidate)
        if Patterns.temporalStationNoise.firstMatch(in: candidate, options: [], range: nsRange) != nil {
            return false
        }

        let hasLetterOrHan = candidate.unicodeScalars.contains { scalar in
            CharacterSet.letters.contains(scalar)
        }
        guard hasLetterOrHan else { return false }

        if isValidUnlabeledHyphenatedCode(ParcelNormalization.cleanDisplayCode(candidate)) {
            return false
        }

        return true
    }
}

// MARK: - Intra-Input Deduplication

private extension PickupParser {
    func deduplicateIntraInput(_ drafts: [ParsedParcelDraft]) -> [ParsedParcelDraft] {
        var result: [ParsedParcelDraft] = []

        for draft in drafts {
            if let existingIndex = matchingDraftIndex(for: draft, in: result) {
                result[existingIndex] = mergeIntraInput(draft, into: result[existingIndex])
            } else {
                result.append(draft)
            }
        }

        return result
    }

    func matchingDraftIndex(for draft: ParsedParcelDraft, in existing: [ParsedParcelDraft]) -> Int? {
        if draft.hasPickupCode {
            if let index = existing.firstIndex(where: { candidate in
                guard candidate.hasPickupCode,
                      candidate.channel == draft.channel,
                      candidate.normalizedPickupCode == draft.normalizedPickupCode
                else { return false }

                // Never merge two parcels that carry distinct non-empty tracking numbers.
                if draft.hasTrackingNumber,
                   candidate.hasTrackingNumber,
                   draft.normalizedTrackingNumber != candidate.normalizedTrackingNumber
                {
                    return false
                }
                return true
            }) {
                return index
            }
        }

        if draft.hasTrackingNumber {
            if let index = existing.firstIndex(where: {
                $0.hasTrackingNumber
                    && $0.normalizedTrackingNumber == draft.normalizedTrackingNumber
            }) {
                return index
            }
        }

        return nil
    }

    func mergeIntraInput(_ incoming: ParsedParcelDraft, into existing: ParsedParcelDraft) -> ParsedParcelDraft {
        var merged = existing
        if !merged.hasPickupCode, incoming.hasPickupCode {
            merged.pickupCode = incoming.pickupCode
        }
        if !merged.hasTrackingNumber, incoming.hasTrackingNumber {
            merged.trackingNumber = incoming.trackingNumber
        }
        if merged.channel == .other, incoming.channel != .other {
            merged.channel = incoming.channel
        } else if !merged.channel.isPhysicalPickupPoint, incoming.channel.isPhysicalPickupPoint {
            merged.channel = incoming.channel
        }
        if merged.stationLabel.isEmpty, !incoming.stationLabel.isEmpty {
            merged.stationLabel = incoming.stationLabel
        }
        if merged.note.isEmpty, !incoming.note.isEmpty {
            merged.note = incoming.note
        }
        return merged
    }
}

// MARK: - Compiled Patterns

private enum ChannelRules {
    static let explicitPickupPoints: [(regex: NSRegularExpression, channel: PickupChannel)] = [
        (
            makeRegex(
                #"多多买菜|多多驿站|多多自提|菜鸟驿站|兔喜|妈妈驿站|近邻宝驿站|校园驿站|(?<!京东)(?<!顺丰)(?<!京东快递)(?<!京东物流)(?<!顺丰快递)(?<!顺丰速运)驿站|\bduoduo\s+station\b|\bcainiao\s+station\b"#,
                options: .caseInsensitive
            ),
            .station
        ),
        (
            makeRegex(
                #"宜小集|丰巢|智能柜|快递柜|自提柜|\byixiaoji\b|\biepple\b|\b(?:smart\s+)?locker\b"#,
                options: .caseInsensitive
            ),
            .locker
        ),
    ]

    static let secondaryStationHints: [(regex: NSRegularExpression, channel: PickupChannel)] = [
        (makeRegex(#"拼多多|多多|菜鸟裹裹|菜鸟|\bduoduo\b|\bpinduoduo\b|\bcainiao\b"#, options: .caseInsensitive), .station),
    ]

    static let couriers: [(regex: NSRegularExpression, channel: PickupChannel)] = [
        (makeRegex(#"京东快递服务站|京东快递站|京东快递|京东物流|京东|\bjd\b"#, options: .caseInsensitive), .jd),
        (makeRegex(#"顺丰速运|顺丰快递|顺丰|\bsf\s*express\b|\bsf\b"#, options: .caseInsensitive), .sfExpress),
    ]

    static let standaloneStationHints: [(regex: NSRegularExpression, channel: PickupChannel)] = [
        (
            makeRegex(
                #"(?:^\s*station[\s:：]+[A-Za-z0-9-]+$|^[A-Za-z0-9-]+[\s:：]+station\s*$)"#,
                options: .caseInsensitive
            ),
            .station
        ),
    ]
}

private enum Patterns {
    static let concatenatedHeader = makeRegex(#"([。！!；;])\s*(【)"#)

    static let noisePatterns: [NSRegularExpression] = [
        // URLs
        makeRegex(#"[A-Za-z][A-Za-z0-9+.-]*://\S+"#),
        // Verification / OTP / non-parcel codes
        makeRegex(#"(?:验证码|校验码|动态码|安全码|(?:\b(?:verification|verify|security|auth|error|status|zip|postal|area|promo|coupon|invite|referral|discount|gift|redeem|access|pass|pin|backup|recovery|confirmation)\s+code\b))[\s:：为是#]*(?:\bis\b\s*)?[A-Za-z0-9-]{3,12}"#, options: .caseInsensitive),
        // Full calendar dates: 2026-11-26, 2026/11/26, 2026.11.26, 2026年11月26日
        makeRegex(#"(?<![A-Za-z0-9-])(?:19|20)\d{2}[-/.年](?:0?[1-9]|1[0-2])[-/.月](?:0?[1-9]|[12]\d|3[01])日?(?![A-Za-z0-9-])"#),
        // Year-month: 2026-11
        makeRegex(#"(?<![A-Za-z0-9-])(?:19|20)\d{2}[-/.年](?:0?[1-9]|1[0-2])月?(?![A-Za-z0-9-])"#),
        // Time ranges and times: 08:30-21:00, 18:20, 09:30:00
        makeRegex(#"(?<![A-Za-z0-9])\d{1,2}:\d{2}(?::\d{2})?(?:\s*-\s*\d{1,2}:\d{2}(?::\d{2})?)?(?![A-Za-z0-9])"#),
        // Prices and currencies
        makeRegex(#"[¥￥$]\s*\d+(?:\.\d+)?"#),
        makeRegex(#"(?<![A-Za-z0-9-])\d+(?:\.\d+)?\s*(?:元|块|RMB|CNY|USD)(?![A-Za-z0-9])"#, options: .caseInsensitive),
        // Labeled phone / hotline / last-4 digits
        makeRegex(#"(?:电话|联系|致电|详询|客服|热线|手机|tel|phone)[\s:：]*[+\d][\d-\s]{6,16}\d"#, options: .caseInsensitive),
        makeRegex(#"(?:手机)?尾号[\s:：为是]*\d{4}"#),
        // 11-digit mobile numbers (plain and hyphenated)
        makeRegex(#"(?<![A-Za-z0-9-])1[3-9]\d{9}(?![A-Za-z0-9-])"#),
        makeRegex(#"(?<![A-Za-z0-9-])1[3-9]\d-\d{4}-\d{4}(?![A-Za-z0-9-])"#),
        // 400/800 service hotlines and domestic landlines
        makeRegex(#"(?<![A-Za-z0-9-])[48]00-\d{3}-\d{4}(?![A-Za-z0-9-])"#),
        makeRegex(#"(?<![A-Za-z0-9-])0\d{2,3}-\d{7,8}(?![A-Za-z0-9-])"#),
    ]

    static let mobilePhone = makeRegex(#"^1[3-9]\d{9}$"#)

    static let labeledTracking = makeRegex(
        #"(?:快递单号|运单号|物流单号|单号|\btracking(?:\s*(?:number|no\.?|#))?|\bwaybill(?:\s*(?:number|no\.?|#))?)[\s:：为是#]*([A-Za-z0-9]{10,18})(?![A-Za-z0-9])"#,
        options: .caseInsensitive
    )

    static let carrierTracking = makeRegex(
        #"(?<![A-Za-z0-9])(?:SF\d{12,13}|JD(?:VA|VB|VC|VE|X|V|G|A)?\d{10,13}|YT\d{13}|JT\d{13}|DPK\d{12}|EMS\d{10,13}|E[A-Z]\d{9}CN)(?![A-Za-z0-9])"#,
        options: .caseInsensitive
    )

    static let numericTracking = makeRegex(#"(?<![A-Za-z0-9-])\d{12,16}(?![A-Za-z0-9-])"#)

    static let labeledCodePrefix = makeRegex(
        #"(?:凭取件码|取件码|取货码|凭码|提货码|开柜码|开箱码|核销码|领取码|\b(?:pickup|pick-up|collection|locker)\s*code\b|\bcode\b)"#,
        options: .caseInsensitive
    )

    static let initialCodeConnector = makeRegex(#"[\s:：,，为是【\[\(（“"'「]*(?:\bis\b[\s:：【\[\(（“"'「]*)?"#, options: .caseInsensitive)
    static let listCodeSeparator = makeRegex(#"[\]】\)）”"'」]*\s*(?:[、,，/&]|和|及|与)\s*[【\[\(（“"'「]*"#)
    static let labeledCodeToken = makeRegex(#"[A-Za-z0-9]{1,8}(?:-[A-Za-z0-9]{1,8}){0,3}(?![A-Za-z0-9-])"#)

    static let pingActionCode = makeRegex(#"凭\s*([A-Za-z0-9]{1,8}(?:-[A-Za-z0-9]{1,8}){0,3})\s*(?:取件|取货|开柜|开箱|领取|提货)"#)

    static let hyphenatedCode = makeRegex(#"(?<![A-Za-z0-9-])[A-Za-z0-9]{1,5}(?:-[A-Za-z0-9]{1,6}){1,3}(?![A-Za-z0-9-])"#)
    static let twoPartFirst = makeRegex(#"^(?:[A-Za-z]{1,2}\d{0,3}|\d{1,4})$"#)
    static let twoPartSecond = makeRegex(#"^(?:\d{3,6}|[A-Za-z]\d{2,5})$"#)
    static let multiPartSegment = makeRegex(#"^(?:[A-Za-z]{0,2}\d{1,5}|\d{1,4}[A-Za-z]?)$"#)

    static let standaloneDigits = makeRegex(#"^\d{6,8}$"#)
    static let standaloneAlphanumeric = makeRegex(#"^[A-Za-z]{1,2}\d{4,7}$"#)

    static let stationShelfCode = makeRegex(#"^\d{1,3}-\d{1,2}-\d{3,5}$"#)
    static let lockerEightDigitCode = makeRegex(#"^\d{8}$"#)
    static let jdTwoPartCode = makeRegex(#"^[A-Za-z]\d{1,2}-\d{4}$"#)
    static let sfFourDigitCode = makeRegex(#"^\d{4}$"#)

    private static let standaloneChannelToken = #"(?:多多买菜|多多驿站|多多自提|拼多多|多多|菜鸟驿站|菜鸟裹裹|菜鸟|兔喜|妈妈驿站|近邻宝驿站|校园驿站|驿站|宜小集|丰巢|智能柜|快递柜|自提柜|顺丰速运|顺丰快递|顺丰|京东快递服务站|京东快递站|京东快递|京东物流|京东|\b(?:duoduo(?:\s+station)?|pinduoduo|yixiaoji|iepple|cainiao|sf(?:\s*express)?|jd|(?:smart\s+)?locker|station)\b)"#

    static let leadingOrTrailingChannel = makeRegex(
        "(?:^\(standaloneChannelToken)[\\s:：]*|[\\s:：]*\(standaloneChannelToken)$)",
        options: .caseInsensitive
    )

    private static let chineseStationCaptureAndTerminator = #"(?:[（(][^）)\n]{1,10}[）)]\s*)?[【\[]?([^\n，,。；;！!？?（(\[【\]】]+?)[】\]]?(?=\s*(?:领取|取件|取货|取走|尽早取|尽快取|及时取|请及时取|取包裹|取快递|开柜|开箱|自提|凭|取件码|取货码|提货码|开柜码|核销码|已经等很久|已等|等您|滞留|的包裹|[，,。；;！!？?（(\n]|$))"#

    static let stationPatterns: [NSRegularExpression] = [
        // High-confidence Chinese arrival verbs first so generic "在3天内..." does not shadow "到<Station>"
        makeRegex(#"(?:已到达|已送达|已投放至|已存放至|已存入|已入柜|已放入|已放至|已入|已到|到达|送达|投放至|存放至|存入|放至|前往|请到|请至)\s*"# + chineseStationCaptureAndTerminator),
        // Fallback Chinese location prepositions: skip temporal clauses like "在3天内..." so "到<Station>" still matches
        makeRegex(#"(?:到|至|在)(?!\s*(?:\d+\s*(?:天|日|小时|分钟|月)|(?:19|20)\d{2}[-/.年]|今[天日]|明[天日]))\s*"# + chineseStationCaptureAndTerminator),
        // English station clauses: "arrived at North Pickup Point", "ready at Demo Locker"
        makeRegex(#"\b(?:arrived at|ready at|delivered to|stored at|available at|at)\s+([A-Za-z0-9][A-Za-z0-9\s#-]{1,39}?)(?=\s*(?:[.,;!\n\(]|\b(?:pickup|pick-up|locker|collection)?\s*code\b|\bwith\b|$))"#, options: .caseInsensitive),
    ]

    static let temporalStationNoise = makeRegex(#"^(?:\d+\s*(?:天|日|小时|分钟|月)|(?:19|20)\d{2}[-/.年]|今[天日]|明[天日])"#)
}

private func makeRegex(
    _ pattern: String,
    options: NSRegularExpression.Options = []
) -> NSRegularExpression {
    // Patterns are compile-time constants covered by unit tests.
    do {
        return try NSRegularExpression(pattern: pattern, options: options)
    } catch {
        preconditionFailure("Invalid regex pattern: \(pattern) — \(error)")
    }
}
