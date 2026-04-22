import SwiftUI
import UIKit

struct SignaturePadView: View {
    let signatureAssetService: SignatureAssetService
    let draftRecoveryService: DraftRecoveryService
    let issueLogService: IssueLogService
    let onOpenDraft: (UUID) async -> Bool
    let onClose: () -> Void

    @State private var signatureName = ""
    @State private var strokes: [SignatureStroke] = []
    @State private var activeStrokePoints: [CGPoint] = []
    @State private var canvasViewSize = CGSize(width: 320, height: 180)
    @State private var signatures: [SignatureAsset] = []
    @State private var statusMessage = "Draw your signature and save it as a reusable asset."
    @State private var isSaving = false
    @State private var isLoading = false
    @State private var signatureToRename: SignatureAsset?
    @State private var signatureToDelete: SignatureAsset?
    @State private var signatureUsageByID: [UUID: SignatureAssetUsageSummary] = [:]
    @State private var referenceViewerAsset: SignatureAsset?
    @State private var isOpeningReferencedDraft = false
    @State private var renameInput = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Button("Close", action: onClose)
                Spacer()
                Text("Signature Pad")
                    .font(.headline)
                Spacer()
            }

            Text("M2: create, reuse, and manage signature assets.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            TextField("Signature name (optional)", text: $signatureName)
                .textFieldStyle(.roundedBorder)
                .disabled(isSaving)

            signatureCanvas

            HStack(spacing: 10) {
                Button("Clear") {
                    clearCanvas()
                }
                .buttonStyle(.bordered)
                .disabled(isSaving || !hasInk)

                Button("Save Signature") {
                    Task {
                        await saveSignature()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSaving || !hasInk)
            }

            if isSaving || isLoading {
                ProgressView(isSaving ? "Saving..." : "Loading...")
                    .font(.caption)
            }

            Text(statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)

            savedSignaturesSection

            Spacer(minLength: 0)
        }
        .padding(20)
        .task {
            await refreshSignatures()
        }
        .alert("Rename Signature", isPresented: isRenameDialogPresented, presenting: signatureToRename) { asset in
            TextField("Name", text: $renameInput)

            Button("Cancel", role: .cancel) {
                clearRenameDialog()
            }

            Button("Save") {
                Task {
                    await renameSignature(asset)
                }
            }
        } message: { asset in
            Text("Current name: \(asset.name)")
        }
        .alert("Delete Signature?", isPresented: isDeleteDialogPresented, presenting: signatureToDelete) { asset in
            Button("Delete", role: .destructive) {
                Task {
                    await deleteSignature(asset)
                }
            }

            Button("Cancel", role: .cancel) {
                signatureToDelete = nil
            }
        } message: { asset in
            if let usage = signatureUsageByID[asset.id], usage.hasReferences {
                Text("This signature is still used by \(usage.referencedPlacementCount) placement(s) in \(usage.referencedDraftCount) draft(s). Delete will be blocked.")
            } else {
                Text("This action cannot be undone: \(asset.name)")
            }
        }
        .sheet(item: $referenceViewerAsset) { asset in
            referenceViewerSheet(for: asset)
        }
    }

    private var signatureCanvas: some View {
        GeometryReader { geometry in
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.secondarySystemBackground))

                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color(.separator), lineWidth: 1)

                ForEach(strokes) { stroke in
                    signaturePath(points: stroke.points)
                        .stroke(
                            Color.primary,
                            style: StrokeStyle(
                                lineWidth: 2.8,
                                lineCap: .round,
                                lineJoin: .round
                            )
                        )
                }

                signaturePath(points: activeStrokePoints)
                    .stroke(
                        Color.primary,
                        style: StrokeStyle(
                            lineWidth: 2.8,
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        activeStrokePoints.append(value.location)
                    }
                    .onEnded { value in
                        activeStrokePoints.append(value.location)
                        commitActiveStroke()
                    }
            )
            .onAppear {
                canvasViewSize = geometry.size
            }
            .onChange(of: geometry.size) { newSize in
                canvasViewSize = newSize
            }
        }
        .frame(height: 180)
    }

    private var savedSignaturesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Saved signatures: \(signatures.count)")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Button("Refresh") {
                    Task {
                        await refreshSignatures()
                    }
                }
                .buttonStyle(.bordered)
                .font(.caption)
                .disabled(isLoading || isSaving)
            }

            if signatures.isEmpty {
                Text("No signature assets yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(signatures, id: \.id) { asset in
                            signatureCard(for: asset)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func signatureCard(for asset: SignatureAsset) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
                if let image = previewImage(for: asset) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 140, height: 56)
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.tertiarySystemBackground))
                        .overlay(
                            Text("Preview unavailable")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        )
                        .frame(width: 140, height: 56)
                }
            }
            .padding(8)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 10))

            Text(asset.name)
                .font(.caption)
                .lineLimit(1)

            Text(signatureUsageText(for: asset))
                .font(.caption2)
                .foregroundStyle(isSignatureInUse(asset.id) ? Color.orange : Color.secondary)
                .lineLimit(2)

            HStack(spacing: 8) {
                Button("Rename") {
                    signatureToRename = asset
                    renameInput = asset.name
                }
                .buttonStyle(.bordered)
                .font(.caption2)
                .disabled(isSaving || isLoading)

                Button("Delete", role: .destructive) {
                    signatureToDelete = asset
                }
                .buttonStyle(.bordered)
                .font(.caption2)
                .disabled(isSaving || isLoading || isSignatureInUse(asset.id))

                if isSignatureInUse(asset.id) {
                    Button("Refs") {
                        referenceViewerAsset = asset
                    }
                    .buttonStyle(.bordered)
                    .font(.caption2)
                    .disabled(isSaving || isLoading)
                }
            }
        }
        .padding(10)
        .frame(width: 180, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private func refreshSignatures() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let loadedSignatures = try await signatureAssetService.loadAllSignatureAssets()
            signatures = loadedSignatures
            let assetIDs = loadedSignatures.map(\.id)
            signatureUsageByID = try await draftRecoveryService.inspectSignatureAssetUsage(assetIDs: assetIDs)
        } catch {
            signatures = []
            signatureUsageByID = [:]
            statusMessage = "Failed to load signatures. Please retry."
            await issueLogService.recordError(
                "Failed to load signature assets",
                error: error,
                category: .signatureImport,
                context: ["scope": "loadAllSignatureAssets"]
            )
        }
    }

    private func saveSignature() async {
        guard hasInk else {
            statusMessage = "Please draw a signature first."
            return
        }

        isSaving = true
        defer { isSaving = false }

        var stagedURL: URL?
        defer {
            if let stagedURL {
                try? FileManager.default.removeItem(at: stagedURL)
            }
        }

        do {
            let resolvedName = makeSignatureName()
            let renderedImage = renderSignatureImage(targetSize: exportedCanvasSize)
            guard let pngData = renderedImage.pngData() else {
                throw AppError.fileImportFailed
            }

            let temporaryURL = try ImportStagingService.stageData(pngData, fileExtension: "png")
            stagedURL = temporaryURL

            _ = try await signatureAssetService.createSignatureAsset(
                name: resolvedName,
                sourcePath: temporaryURL.path,
                transparentImagePath: temporaryURL.path
            )

            clearCanvas()
            signatureName = ""
            statusMessage = "Signature saved. You can now reuse it in Editor."
            await issueLogService.recordFeedback(
                "Signature asset saved",
                category: .signatureImport,
                context: ["signatureName": resolvedName]
            )
            await refreshSignatures()
        } catch {
            statusMessage = "Signature save failed. Please retry."
            await issueLogService.recordError(
                "Failed to save signature asset",
                error: error,
                category: .signatureImport,
                context: ["signatureName": signatureName]
            )
        }
    }

    private var isRenameDialogPresented: Binding<Bool> {
        Binding(
            get: { signatureToRename != nil },
            set: { newValue in
                if !newValue {
                    clearRenameDialog()
                }
            }
        )
    }

    private var isDeleteDialogPresented: Binding<Bool> {
        Binding(
            get: { signatureToDelete != nil },
            set: { newValue in
                if !newValue {
                    signatureToDelete = nil
                }
            }
        )
    }

    private func clearRenameDialog() {
        signatureToRename = nil
        renameInput = ""
    }

    private func renameSignature(_ asset: SignatureAsset) async {
        let trimmedName = renameInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            statusMessage = "Signature name cannot be empty."
            clearRenameDialog()
            return
        }

        if trimmedName == asset.name {
            clearRenameDialog()
            return
        }

        do {
            _ = try await signatureAssetService.renameSignatureAsset(asset, to: trimmedName)
            statusMessage = "Signature renamed."
            await issueLogService.recordFeedback(
                "Signature rename succeeded",
                category: .signatureImport,
                context: [
                    "signatureID": asset.id.uuidString,
                    "newName": trimmedName
                ]
            )
            clearRenameDialog()
            await refreshSignatures()
        } catch {
            statusMessage = "Rename failed. Please retry."
            await issueLogService.recordError(
                "Signature rename failed",
                error: error,
                category: .signatureImport,
                context: [
                    "signatureID": asset.id.uuidString,
                    "newName": trimmedName
                ]
            )
        }
    }

    private func deleteSignature(_ asset: SignatureAsset) async {
        do {
            let usage: SignatureAssetUsageSummary
            if let cachedUsage = signatureUsageByID[asset.id] {
                usage = cachedUsage
            } else {
                usage = try await draftRecoveryService.inspectSignatureAssetUsage(assetID: asset.id)
            }

            if usage.hasReferences {
                signatureUsageByID[asset.id] = usage
                signatureToDelete = nil
                let sampleNames = usage.sampleDocumentNames.joined(separator: ", ")
                if sampleNames.isEmpty {
                    statusMessage = "Delete blocked: this signature is referenced by \(usage.referencedPlacementCount) placement(s) across \(usage.referencedDraftCount) draft(s)."
                } else {
                    statusMessage = "Delete blocked: referenced by \(usage.referencedPlacementCount) placement(s) in drafts (\(sampleNames))."
                }
                await issueLogService.recordFeedback(
                    "Signature delete blocked by draft references",
                    category: .signatureImport,
                    context: [
                        "signatureID": asset.id.uuidString,
                        "referencedDraftCount": String(usage.referencedDraftCount),
                        "referencedPlacementCount": String(usage.referencedPlacementCount)
                    ]
                )
                return
            }

            try await signatureAssetService.deleteSignatureAsset(asset)
            signatureToDelete = nil
            statusMessage = "Signature deleted."
            await issueLogService.recordFeedback(
                "Signature delete succeeded",
                category: .signatureImport,
                context: ["signatureID": asset.id.uuidString]
            )
            await refreshSignatures()
        } catch {
            statusMessage = "Delete failed. Please retry."
            await issueLogService.recordError(
                "Signature delete failed",
                error: error,
                category: .signatureImport,
                context: ["signatureID": asset.id.uuidString]
            )
        }
    }

    private func signatureUsageText(for asset: SignatureAsset) -> String {
        guard let usage = signatureUsageByID[asset.id], usage.hasReferences else {
            return "Draft references: none"
        }
        return "Draft references: \(usage.referencedPlacementCount) placement(s) / \(usage.referencedDraftCount) draft(s)"
    }

    private func isSignatureInUse(_ assetID: UUID) -> Bool {
        signatureUsageByID[assetID]?.hasReferences ?? false
    }

    private func referenceViewerSheet(for asset: SignatureAsset) -> some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("Referenced drafts for \(asset.name)")
                    .font(.headline)

                if let usage = signatureUsageByID[asset.id], usage.hasReferences {
                    Text("Total \(usage.referencedPlacementCount) placement(s) in \(usage.referencedDraftCount) draft(s).")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    List(usage.referencedDrafts, id: \.documentID) { draft in
                        HStack(alignment: .top, spacing: 10) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(draft.documentName)
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(1)
                                Text("Placements: \(draft.placementCount)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("Updated: \(draft.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer(minLength: 0)

                            Button("Open") {
                                Task {
                                    await openReferencedDraft(draft, asset: asset)
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .font(.caption)
                            .disabled(isOpeningReferencedDraft)
                        }
                        .padding(.vertical, 4)
                    }
                    .listStyle(.plain)
                } else {
                    Text("No draft references found.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        referenceViewerAsset = nil
                    }
                }
            }
        }
    }

    private func openReferencedDraft(_ draft: SignatureAssetDraftReference, asset: SignatureAsset) async {
        guard !isOpeningReferencedDraft else {
            return
        }

        isOpeningReferencedDraft = true
        defer { isOpeningReferencedDraft = false }

        let opened = await onOpenDraft(draft.documentID)
        if opened {
            referenceViewerAsset = nil
            statusMessage = "Opened draft \(draft.documentName) to resolve signature references."
            await issueLogService.recordFeedback(
                "Open referenced draft from signature usage",
                category: .signatureImport,
                context: [
                    "signatureID": asset.id.uuidString,
                    "documentID": draft.documentID.uuidString,
                    "documentName": draft.documentName,
                    "placementCount": String(draft.placementCount)
                ]
            )
        } else {
            statusMessage = "Failed to open referenced draft. Please retry from Home."
            await issueLogService.recordFeedback(
                "Open referenced draft failed from signature usage",
                category: .signatureImport,
                context: [
                    "signatureID": asset.id.uuidString,
                    "documentID": draft.documentID.uuidString,
                    "documentName": draft.documentName
                ]
            )
        }
    }

    private var hasInk: Bool {
        !strokes.isEmpty || !activeStrokePoints.isEmpty
    }

    private var exportedCanvasSize: CGSize {
        let width = max(canvasViewSize.width, 1)
        let height = max(canvasViewSize.height, 1)
        let targetWidth: CGFloat = 1400
        let targetHeight = max((height / width) * targetWidth, 280)
        return CGSize(width: targetWidth, height: targetHeight)
    }

    private func renderSignatureImage(targetSize: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false

        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let sourceSize = CGSize(
            width: max(canvasViewSize.width, 1),
            height: max(canvasViewSize.height, 1)
        )
        let allStrokes = activeStrokePoints.isEmpty
            ? strokes
            : strokes + [SignatureStroke(points: activeStrokePoints)]
        let scaleX = targetSize.width / sourceSize.width
        let scaleY = targetSize.height / sourceSize.height
        let baseLineWidth = max(min(scaleX, scaleY) * 2.8, 1.6)

        return renderer.image { context in
            context.cgContext.clear(CGRect(origin: .zero, size: targetSize))
            UIColor.black.setStroke()
            UIColor.black.setFill()

            for stroke in allStrokes where !stroke.points.isEmpty {
                let path = UIBezierPath()
                path.lineWidth = baseLineWidth
                path.lineCapStyle = .round
                path.lineJoinStyle = .round

                if stroke.points.count == 1, let point = stroke.points.first {
                    let scaled = CGPoint(x: point.x * scaleX, y: point.y * scaleY)
                    path.addArc(
                        withCenter: scaled,
                        radius: baseLineWidth / 2,
                        startAngle: 0,
                        endAngle: .pi * 2,
                        clockwise: true
                    )
                    path.fill()
                    continue
                }

                for (index, point) in stroke.points.enumerated() {
                    let scaled = CGPoint(x: point.x * scaleX, y: point.y * scaleY)
                    if index == 0 {
                        path.move(to: scaled)
                    } else {
                        path.addLine(to: scaled)
                    }
                }
                path.stroke()
            }
        }
    }

    private func previewImage(for asset: SignatureAsset) -> UIImage? {
        let imagePath = (asset.normalizedTransparentImagePath?.isEmpty == false)
            ? asset.normalizedTransparentImagePath
            : asset.originalSignaturePath
        guard let imagePath else {
            return nil
        }
        return UIImage(contentsOfFile: imagePath)
    }

    private func makeSignatureName() -> String {
        let trimmed = signatureName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "Signature-\(formatter.string(from: Date()))"
    }

    private func commitActiveStroke() {
        guard !activeStrokePoints.isEmpty else {
            return
        }
        strokes.append(SignatureStroke(points: activeStrokePoints))
        activeStrokePoints = []
    }

    private func clearCanvas() {
        strokes = []
        activeStrokePoints = []
    }

    private func signaturePath(points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else {
            return path
        }

        if points.count == 1 {
            path.addEllipse(in: CGRect(x: first.x - 1.2, y: first.y - 1.2, width: 2.4, height: 2.4))
            return path
        }

        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        return path
    }
}

private struct SignatureStroke: Identifiable, Hashable {
    let id: UUID
    var points: [CGPoint]

    init(id: UUID = UUID(), points: [CGPoint]) {
        self.id = id
        self.points = points
    }
}
