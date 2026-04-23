import Foundation

enum ActualSizeInspectionSeverity: Equatable {
    case pass
    case warning
}

struct ActualSizeInspectionResult: Equatable {
    var severity: ActualSizeInspectionSeverity
    var headline: String
    var detail: String
}

protocol ActualSizeInspectionService {
    func inspect(
        object: EditorObject,
        pageSizeMM: MillimeterSize
    ) -> ActualSizeInspectionResult
}

struct DefaultActualSizeInspectionService: ActualSizeInspectionService {
    func inspect(
        object: EditorObject,
        pageSizeMM: MillimeterSize
    ) -> ActualSizeInspectionResult {
        if let stamp = object.stampPlacement {
            return inspectStamp(stamp, pageSizeMM: pageSizeMM)
        }

        if let signature = object.signaturePlacement {
            return inspectSignature(signature, pageSizeMM: pageSizeMM)
        }

        return ActualSizeInspectionResult(
            severity: .warning,
            headline: "检查失败",
            detail: "未识别对象类型，无法执行实际尺寸检查。"
        )
    }

    private func inspectStamp(
        _ stamp: StampPlacement,
        pageSizeMM: MillimeterSize
    ) -> ActualSizeInspectionResult {
        let widthRatio = safeRatio(stamp.widthMM, pageSizeMM.width)
        let heightRatio = safeRatio(stamp.heightMM, pageSizeMM.height)
        let areaRatio = safeRatio(stamp.widthMM * stamp.heightMM, pageSizeMM.width * pageSizeMM.height)

        var warnings: [String] = []
        if stamp.widthMM < 8 || stamp.heightMM < 8 {
            warnings.append("尺寸过小")
        }
        if stamp.widthMM > pageSizeMM.width * 0.45 || stamp.heightMM > pageSizeMM.height * 0.45 {
            warnings.append("尺寸过大")
        }
        if areaRatio < 0.003 {
            warnings.append("覆盖面积偏小")
        }

        if warnings.isEmpty {
            return ActualSizeInspectionResult(
                severity: .pass,
                headline: "印章实尺检查：通过",
                detail: stampDetail(
                    widthMM: stamp.widthMM,
                    heightMM: stamp.heightMM,
                    widthRatio: widthRatio,
                    heightRatio: heightRatio
                )
            )
        }

        return ActualSizeInspectionResult(
            severity: .warning,
            headline: "印章实尺检查：需关注（\(warnings.joined(separator: "、"))）",
            detail: stampDetail(
                widthMM: stamp.widthMM,
                heightMM: stamp.heightMM,
                widthRatio: widthRatio,
                heightRatio: heightRatio
            )
        )
    }

    private func inspectSignature(
        _ signature: SignaturePlacement,
        pageSizeMM: MillimeterSize
    ) -> ActualSizeInspectionResult {
        let widthRatio = safeRatio(signature.widthMM, pageSizeMM.width)
        let heightRatio = safeRatio(signature.heightMM, pageSizeMM.height)
        let areaRatio = safeRatio(signature.widthMM * signature.heightMM, pageSizeMM.width * pageSizeMM.height)

        var warnings: [String] = []
        if signature.widthMM < 12 || signature.heightMM < 5 {
            warnings.append("尺寸过小")
        }
        if signature.widthMM > pageSizeMM.width * 0.7 || signature.heightMM > pageSizeMM.height * 0.25 {
            warnings.append("尺寸过大")
        }
        if areaRatio < 0.0015 {
            warnings.append("覆盖面积偏小")
        }

        if warnings.isEmpty {
            return ActualSizeInspectionResult(
                severity: .pass,
                headline: "签名实尺检查：通过",
                detail: signatureDetail(
                    widthMM: signature.widthMM,
                    heightMM: signature.heightMM,
                    widthRatio: widthRatio,
                    heightRatio: heightRatio
                )
            )
        }

        return ActualSizeInspectionResult(
            severity: .warning,
            headline: "签名实尺检查：需关注（\(warnings.joined(separator: "、"))）",
            detail: signatureDetail(
                widthMM: signature.widthMM,
                heightMM: signature.heightMM,
                widthRatio: widthRatio,
                heightRatio: heightRatio
            )
        )
    }

    private func stampDetail(
        widthMM: Double,
        heightMM: Double,
        widthRatio: Double,
        heightRatio: Double
    ) -> String {
        "尺寸 \(String(format: "%.1f", widthMM)) × \(String(format: "%.1f", heightMM)) mm，约占纸面宽 \(String(format: "%.1f", widthRatio * 100))% / 高 \(String(format: "%.1f", heightRatio * 100))%。"
    }

    private func signatureDetail(
        widthMM: Double,
        heightMM: Double,
        widthRatio: Double,
        heightRatio: Double
    ) -> String {
        "尺寸 \(String(format: "%.1f", widthMM)) × \(String(format: "%.1f", heightMM)) mm，约占纸面宽 \(String(format: "%.1f", widthRatio * 100))% / 高 \(String(format: "%.1f", heightRatio * 100))%。"
    }

    private func safeRatio(_ numerator: Double, _ denominator: Double) -> Double {
        guard denominator > 0 else {
            return 0
        }
        return max(numerator, 0) / denominator
    }
}
