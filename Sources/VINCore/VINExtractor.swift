import Foundation

public enum VINCopyFormat: String, Sendable {
    case columnWithCommas
    case columnOnly
    case commaSeparated
}

public enum VINExtractor {
    private static let illegal: Set<Character> = ["I", "O", "Q"]

    private static let transliteration: [Character: Int] = [
        "A": 1, "B": 2, "C": 3, "D": 4, "E": 5, "F": 6, "G": 7, "H": 8,
        "J": 1, "K": 2, "L": 3, "M": 4, "N": 5, "P": 7, "R": 9,
        "S": 2, "T": 3, "U": 4, "V": 5, "W": 6, "X": 7, "Y": 8, "Z": 9,
        "0": 0, "1": 1, "2": 2, "3": 3, "4": 4, "5": 5, "6": 6, "7": 7, "8": 8, "9": 9,
    ]

    private static let weights = [8, 7, 6, 5, 4, 3, 2, 10, 0, 9, 8, 7, 6, 5, 4, 3, 2]

    /// Substrings that appear when OCR reads UI/docs — never real VIN bodies.
    private static let bannedFragments = [
        "CHECK", "DIGIT", "STRICT", "SCREEN", "FORMAT", "COMMA", "COLUMN",
        "SCRAPER", "CLIPBOARD", "EXTRACT", "NUMBER", "VEHICLE", "OPTION",
        "COPY", "PASTE", "ERROR", "VALID", "FALSE", "TRUE", "RESULT",
    ]

    public struct Result: Equatable, Sendable {
        public let vins: [String]
        public let rawText: String
        public init(vins: [String], rawText: String) {
            self.vins = vins
            self.rawText = rawText
        }
    }

    /// Extract unique VINs from OCR text.
    ///
    /// Strategy (accuracy-first):
    /// 1. Only consider discrete alphanumeric tokens (not sliding across paragraphs).
    /// 2. Accept length 17 exactly, or 16…19 with safe OCR fixes / trim.
    /// 3. Prefer ISO 3779 check digit; reject junk that looks like English/UI text.
    public static func extract(from text: String, strictCheckDigit: Bool) -> Result {
        let tokens = tokenize(text.uppercased())
        var found: [String] = []
        var seen = Set<String>()

        for token in tokens {
            for candidate in candidates(from: token) {
                guard !seen.contains(candidate) else { continue }
                guard isPlausibleVIN(candidate) else { continue }

                let checkOK = passesCheckDigit(candidate)
                if strictCheckDigit && !checkOK { continue }
                if !strictCheckDigit && !checkOK && !isWellFormed(candidate) { continue }
                if !checkOK && strictCheckDigit { continue }
                if !isWellFormed(candidate) { continue }

                // In non-strict mode still require check digit if we already have
                // check-digit hits — handled after loop via preference.
                seen.insert(candidate)
                found.append(candidate)
            }
        }

        let withCheck = found.filter(passesCheckDigit)
        let vins: [String]
        if !withCheck.isEmpty {
            vins = withCheck
        } else if !strictCheckDigit {
            vins = found.filter(isWellFormed)
        } else {
            vins = []
        }

        return Result(vins: vins, rawText: text)
    }

    public static func formatForClipboard(_ vins: [String], style: VINCopyFormat) -> String {
        switch style {
        case .columnWithCommas:
            return vins.enumerated().map { idx, vin in
                idx == vins.count - 1 ? vin : "\(vin),"
            }.joined(separator: "\n")
        case .columnOnly:
            return vins.joined(separator: "\n")
        case .commaSeparated:
            return vins.joined(separator: ", ")
        }
    }

    // MARK: - Tokenization

    /// Split on anything that is not a VIN-ish character. Keeps tokens separate
    /// so prose like "CHECK DIGIT" never becomes a sliding-window VIN.
    private static func tokenize(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""

        func flush() {
            let t = current
            current = ""
            guard !t.isEmpty else { return }
            // Only consider near-VIN lengths — never long mashed paragraphs.
            if (15...20).contains(t.count) {
                tokens.append(t)
            }
        }

        for ch in text {
            if isVINIsh(ch) {
                current.append(ch)
            } else {
                flush()
            }
        }
        flush()
        return tokens
    }

    private static func isVINIsh(_ ch: Character) -> Bool {
        ch.isLetter || ch.isNumber || ch == "|"
    }

    // MARK: - Candidates from a single token

    private static func candidates(from token: String) -> [String] {
        let cleaned = String(token.filter { isVINIsh($0) }).uppercased()
        var out = Set<String>()

        func consider(_ s: String) {
            let chars = Array(s)
            switch chars.count {
            case 17:
                out.insert(s)
            case 16, 18, 19, 20:
                // OCR sometimes drops/adds 1–3 chars; only try aligned windows
                // inside this short token — never across sentences.
                guard chars.count >= 17 else { return }
                for i in 0...(chars.count - 17) {
                    out.insert(String(chars[i..<(i + 17)]))
                }
            default:
                break
            }
        }

        consider(cleaned)
        consider(applySafeOCRFixes(cleaned))

        // Soft L→1 only if no check-digit hit yet among current set.
        if !out.contains(where: { isWellFormed($0) && passesCheckDigit($0) }) {
            let soft = String(applySafeOCRFixes(cleaned).map { $0 == "L" ? Character("1") : $0 })
            consider(soft)
        }

        return Array(out)
    }

    /// Only map characters that are illegal in real VINs.
    private static func applySafeOCRFixes(_ s: String) -> String {
        String(s.map { ch -> Character in
            switch ch {
            case "O", "Q": return "0"
            case "I", "|": return "1"
            default: return ch
            }
        })
    }

    // MARK: - Plausibility

    private static func isWellFormed(_ vin: String) -> Bool {
        guard vin.count == 17 else { return false }
        guard vin.allSatisfy({ ($0.isLetter || $0.isNumber) && !illegal.contains($0) }) else { return false }
        let check = vin[vin.index(vin.startIndex, offsetBy: 8)]
        return check.isNumber || check == "X"
    }

    /// Extra guards beyond check digit — kills OCR junk that randomly passes mod-11.
    private static func isPlausibleVIN(_ vin: String) -> Bool {
        guard isWellFormed(vin) else { return false }

        let letters = vin.filter(\.isLetter).count
        let digits = vin.filter(\.isNumber).count
        // Real VINs mix letters and digits (WMI + numeric fields).
        guard letters >= 2, digits >= 4 else { return false }

        // Position 10 = model year code (no 0, U, Z).
        let yearCodes = Set("ABCDEFGHJKLMNPRSTVWXY123456789")
        let yearChar = vin[vin.index(vin.startIndex, offsetBy: 9)]
        guard yearCodes.contains(yearChar) else { return false }

        // Positions 12–17 (serial) are predominantly numeric on real vehicles.
        let serial = vin.suffix(6)
        let serialDigits = serial.filter(\.isNumber).count
        guard serialDigits >= 3 else { return false }

        // Reject UI/doc English glued into the token (e.g. …CHECKDIGIT…).
        for banned in bannedFragments {
            if vin.contains(banned) { return false }
        }

        // Too many identical characters in a row (OCR noise). Allow "ZZZ" (common EU filler).
        if hasRepeatedChar(vin, count: 5) { return false }

        return true
    }

    private static func hasRepeatedChar(_ vin: String, count: Int) -> Bool {
        var last: Character?
        var run = 0
        for ch in vin {
            if ch == last {
                run += 1
                if run >= count { return true }
            } else {
                last = ch
                run = 1
            }
        }
        return false
    }

    /// ISO 3779 check digit (position 9).
    public static func passesCheckDigit(_ vin: String) -> Bool {
        guard vin.count == 17 else { return false }
        var sum = 0
        for (i, ch) in vin.enumerated() {
            guard let val = transliteration[ch] else { return false }
            sum += val * weights[i]
        }
        let rem = sum % 11
        let expected: Character = rem == 10 ? "X" : Character(String(rem))
        let actual = vin[vin.index(vin.startIndex, offsetBy: 8)]
        return actual == expected
    }
}
