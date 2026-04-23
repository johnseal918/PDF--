import Foundation

enum PreviewJudgementSeverity: Equatable {
    case pass
    case warning
}

struct PreviewJudgementResult: Equatable {
    var severity: PreviewJudgementSeverity
    var headline: String
    var detail: String
    var simulatedScale: Double
}

protocol PreviewModeService {
    func inspect(
        mode: PreviewMode,
        selectedObject: EditorObject?,
        page: PageModel?
    ) -> PreviewJudgementResult
}

struct DefaultPreviewModeService: PreviewModeService {
    func inspect(
        mode: PreviewMode,
        selectedObject: EditorObject?,
        page: PageModel?
    ) -> PreviewJudgementResult {
        guard let page else {
            return PreviewJudgementResult(
                severity: .warning,
                headline: "Preview inspection unavailable",
                detail: "Current page metadata is invalid. Preview judgement cannot be generated.",
                simulatedScale: 1
            )
        }

        let simulatedScale = makeSimulatedScale(mode: mode, page: page)

        guard let selectedObject else {
            let headline = mode == .original
                ? "Original preview active"
                : "Low-resolution matched preview active"
            return PreviewJudgementResult(
                severity: .pass,
                headline: headline,
                detail: "No object selected. Preview mode affects judgement only and does not change coordinates or export output.",
                simulatedScale: simulatedScale
            )
        }

        if let stamp = selectedObject.stampPlacement {
            return inspectStamp(stamp, mode: mode, simulatedScale: simulatedScale)
        }

        if let signature = selectedObject.signaturePlacement {
            return inspectSignature(signature, mode: mode, simulatedScale: simulatedScale)
        }

        return PreviewJudgementResult(
            severity: .warning,
            headline: "Preview inspection unavailable",
            detail: "Object type is not recognized. Low-resolution judgement cannot be generated.",
            simulatedScale: simulatedScale
        )
    }

    private func inspectStamp(
        _ stamp: StampPlacement,
        mode: PreviewMode,
        simulatedScale: Double
    ) -> PreviewJudgementResult {
        let simulatedWidth = stamp.widthMM * simulatedScale
        let simulatedHeight = stamp.heightMM * simulatedScale
        let minEdge = min(simulatedWidth, simulatedHeight)

        if mode == .matchedLowRes && minEdge < 8 {
            return PreviewJudgementResult(
                severity: .warning,
                headline: "Stamp may look blurry in matched low-res preview",
                detail: "Current size \(format(stamp.widthMM)) x \(format(stamp.heightMM)) mm; simulated low-res visual size \(format(simulatedWidth)) x \(format(simulatedHeight)) mm. Consider increasing size and verifying again.",
                simulatedScale: simulatedScale
            )
        }

        let headline = mode == .original
            ? "Stamp clarity baseline is normal in original preview"
            : "Stamp clarity is acceptable in matched low-res preview"
        return PreviewJudgementResult(
            severity: .pass,
            headline: headline,
            detail: "Current size \(format(stamp.widthMM)) x \(format(stamp.heightMM)) mm; simulated low-res visual size \(format(simulatedWidth)) x \(format(simulatedHeight)) mm. This is preview-only and does not affect export.",
            simulatedScale: simulatedScale
        )
    }

    private func inspectSignature(
        _ signature: SignaturePlacement,
        mode: PreviewMode,
        simulatedScale: Double
    ) -> PreviewJudgementResult {
        let simulatedWidth = signature.widthMM * simulatedScale
        let simulatedHeight = signature.heightMM * simulatedScale
        let minEdge = min(simulatedWidth, simulatedHeight)

        if mode == .matchedLowRes && minEdge < 5 {
            return PreviewJudgementResult(
                severity: .warning,
                headline: "Signature may look faint in matched low-res preview",
                detail: "Current size \(format(signature.widthMM)) x \(format(signature.heightMM)) mm; simulated low-res visual size \(format(simulatedWidth)) x \(format(simulatedHeight)) mm. Consider increasing signature height and re-checking.",
                simulatedScale: simulatedScale
            )
        }

        let headline = mode == .original
            ? "Signature clarity baseline is normal in original preview"
            : "Signature clarity is acceptable in matched low-res preview"
        return PreviewJudgementResult(
            severity: .pass,
            headline: headline,
            detail: "Current size \(format(signature.widthMM)) x \(format(signature.heightMM)) mm; simulated low-res visual size \(format(simulatedWidth)) x \(format(simulatedHeight)) mm. This is preview-only and does not affect export.",
            simulatedScale: simulatedScale
        )
    }

    private func makeSimulatedScale(mode: PreviewMode, page: PageModel) -> Double {
        let fitScaleX = safeRatio(page.contentRectInA4PT.size.width, page.a4CanvasSizePT.width)
        let fitScaleY = safeRatio(page.contentRectInA4PT.size.height, page.a4CanvasSizePT.height)
        let baseScale = min(fitScaleX, fitScaleY)
        let modeScale: Double = mode == .matchedLowRes ? 0.62 : 1
        return clamp(baseScale * modeScale, min: 0.35, max: 1)
    }

    private func format(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    private func safeRatio(_ numerator: Double, _ denominator: Double) -> Double {
        guard denominator > 0 else {
            return 0
        }
        return numerator / denominator
    }

    private func clamp(_ value: Double, min: Double, max: Double) -> Double {
        if value < min {
            return min
        }
        if value > max {
            return max
        }
        return value
    }
}
