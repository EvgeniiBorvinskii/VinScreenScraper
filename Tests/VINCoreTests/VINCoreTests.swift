import XCTest
@testable import VINCore

final class VINCoreTests: XCTestCase {
    func testExtractSingleVIN() {
        let vin = makeVIN(prefix16: "1HGCM82633A00435")
        XCTAssertEqual(vin.count, 17)
        XCTAssertTrue(VINExtractor.passesCheckDigit(vin))

        let text = "Vehicle id: \(vin) end"
        let result = VINExtractor.extract(from: text, strictCheckDigit: true)
        XCTAssertEqual(result.vins, [vin])
    }

    func testExtractMultipleVINsColumnFormat() {
        let v1 = makeVIN(prefix16: "1HGCM82633A00435")
        let v2 = makeVIN(prefix16: "5YJSA1E14HF00001")

        let text = "\(v1)\nOther stuff\n\(v2)"
        let result = VINExtractor.extract(from: text, strictCheckDigit: true)
        XCTAssertEqual(Set(result.vins), Set([v1, v2]))

        let formatted = VINExtractor.formatForClipboard([v1, v2], style: .columnWithCommas)
        XCTAssertEqual(formatted, "\(v1),\n\(v2)")
    }

    func testDoesNotInventVINsFromProse() {
        let prose = """
        WVWZZZ3CZWE012345,
        1HGCM82633A004352

        Strict check digit validation
        SCREEN FORMAT COMMA COLUMN SCRAPER
        NGRPV11D0YV0G1DUN garbage should not all match
        """
        let result = VINExtractor.extract(from: prose, strictCheckDigit: true)
        // Only the known-valid Honda example should survive (VW sample fails check digit).
        XCTAssertEqual(result.vins, ["1HGCM82633A004352"])
    }

    func testOCRConfusionIOQ() {
        let vin = makeVIN(prefix16: "1HGCM82633A00435")
        var messed = Array(vin)
        if let idx = messed.firstIndex(of: "0") {
            messed[idx] = "O"
        }
        let dirty = String(messed)
        let result = VINExtractor.extract(from: "VIN \(dirty)", strictCheckDigit: true)
        XCTAssertTrue(result.vins.contains(vin), "Expected to recover \(vin) from \(dirty), got \(result.vins)")
    }

    func testRejectsInvalidCheckDigitWhenStrict() {
        let vin = makeVIN(prefix16: "1HGCM82633A00435")
        var bad = Array(vin)
        bad[8] = bad[8] == "1" ? "2" : "1"
        let badVIN = String(bad)
        XCTAssertFalse(VINExtractor.passesCheckDigit(badVIN))

        let result = VINExtractor.extract(from: badVIN, strictCheckDigit: true)
        XCTAssertFalse(result.vins.contains(badVIN))
    }

    func testIgnoresLongMashedAlphanumeric() {
        // Old bug: sliding window over a long run produced dozens of false VINs.
        let mash = "NGRPV11D0YV0G1DUN1PEKUMBB1GENEHNA3VNYHKTBB1AENU7B301GENUTE06NACTTBCV"
        let result = VINExtractor.extract(from: mash, strictCheckDigit: true)
        XCTAssertTrue(result.vins.isEmpty, "Got unexpected VINs: \(result.vins)")
    }

    private func makeVIN(prefix16: String) -> String {
        precondition(prefix16.count == 16)
        let p = Array(prefix16)
        let before = String(p[0..<8])
        let after = String(p[8..<16])
        let check = computeCheckDigit(before: before, after: after)
        return before + String(check) + after
    }

    private func computeCheckDigit(before: String, after: String) -> Character {
        let vin = before + "0" + after
        let transliteration: [Character: Int] = [
            "A": 1, "B": 2, "C": 3, "D": 4, "E": 5, "F": 6, "G": 7, "H": 8,
            "J": 1, "K": 2, "L": 3, "M": 4, "N": 5, "P": 7, "R": 9,
            "S": 2, "T": 3, "U": 4, "V": 5, "W": 6, "X": 7, "Y": 8, "Z": 9,
            "0": 0, "1": 1, "2": 2, "3": 3, "4": 4, "5": 5, "6": 6, "7": 7, "8": 8, "9": 9,
        ]
        let weights = [8, 7, 6, 5, 4, 3, 2, 10, 0, 9, 8, 7, 6, 5, 4, 3, 2]
        var sum = 0
        for (i, ch) in vin.enumerated() where i != 8 {
            sum += (transliteration[ch] ?? 0) * weights[i]
        }
        let rem = sum % 11
        return rem == 10 ? "X" : Character(String(rem))
    }
}
