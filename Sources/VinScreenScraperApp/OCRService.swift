import Foundation
@preconcurrency import Vision
import CoreGraphics
import AppKit

enum OCRError: LocalizedError {
    case noText
    case visionFailed(String)

    var errorDescription: String? {
        switch self {
        case .noText: return "No text recognized in the selected area"
        case .visionFailed(let m): return "OCR error: \(m)"
        }
    }
}

struct OCRResult {
    /// Best-guess lines (top candidate per region), newline-joined.
    let primaryText: String
    /// Alternate candidates kept separate (one string per candidate line).
    let alternateLines: [String]
}

enum OCRService {
    static func recognize(in image: CGImage) async throws -> OCRResult {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: OCRError.visionFailed(error.localizedDescription))
                    return
                }
                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                var primary: [String] = []
                var alternates: [String] = []

                for obs in observations {
                    let cands = obs.topCandidates(3)
                    guard let top = cands.first else { continue }
                    primary.append(top.string)
                    for cand in cands.dropFirst() {
                        alternates.append(cand.string)
                    }
                }

                let primaryText = primary.joined(separator: "\n")
                if primaryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    continuation.resume(throwing: OCRError.noText)
                } else {
                    continuation.resume(returning: OCRResult(primaryText: primaryText, alternateLines: alternates))
                }
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            request.recognitionLanguages = ["en-US"]
            if #available(macOS 13.0, *) {
                request.automaticallyDetectsLanguage = false
            }
            request.minimumTextHeight = 0.015

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(throwing: OCRError.visionFailed(error.localizedDescription))
                }
            }
        }
    }

    /// Tesseract only as fallback when Vision found nothing useful.
    static func recognizeWithTesseract(image: CGImage) -> String? {
        let tesseract = "/opt/homebrew/bin/tesseract"
        guard FileManager.default.isExecutableFile(atPath: tesseract) else { return nil }

        let tmpDir = FileManager.default.temporaryDirectory
        let pngURL = tmpDir.appendingPathComponent("vin_ocr_\(UUID().uuidString).png")
        let outBase = tmpDir.appendingPathComponent("vin_ocr_out_\(UUID().uuidString)")

        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else { return nil }
        do {
            try data.write(to: pngURL)
        } catch {
            return nil
        }
        defer {
            try? FileManager.default.removeItem(at: pngURL)
            try? FileManager.default.removeItem(at: outBase.appendingPathExtension("txt"))
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: tesseract)
        proc.arguments = [
            pngURL.path,
            outBase.path,
            "-l", "eng",
            "--psm", "6",
            "-c", "tessedit_char_whitelist=ABCDEFGHJKLMNPRSTUVWXYZ0123456789abcdefghjklmnprstuvwxyzIlOQ|",
        ]
        proc.standardOutput = Pipe()
        proc.standardError = Pipe()
        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            return nil
        }
        let txtURL = outBase.appendingPathExtension("txt")
        return try? String(contentsOf: txtURL, encoding: .utf8)
    }
}
