import Foundation

struct DraftSnapshotSummary: Identifiable, Equatable {
    let id: UUID
    let documentID: UUID
    let documentName: String
    let updatedAt: Date
    let pageCount: Int
}

protocol DraftRecoveryService {
    func saveDraft(session: EditorSession) async throws
    func restoreLatestDraft() async throws -> EditorSession?
    func restoreDraft(for documentID: UUID) async throws -> EditorSession?
    func loadDraftSummaries() async throws -> [DraftSnapshotSummary]
    func clearDraft(for documentID: UUID) async throws
}

final class InMemoryDraftRecoveryService: DraftRecoveryService {
    private var sessionsByDocumentID: [UUID: EditorSession] = [:]

    func saveDraft(session: EditorSession) async throws {
        sessionsByDocumentID[session.document.id] = session
    }

    func restoreLatestDraft() async throws -> EditorSession? {
        sessionsByDocumentID.values.max { lhs, rhs in
            lhs.document.updatedAt < rhs.document.updatedAt
        }
    }

    func restoreDraft(for documentID: UUID) async throws -> EditorSession? {
        sessionsByDocumentID[documentID]
    }

    func loadDraftSummaries() async throws -> [DraftSnapshotSummary] {
        sessionsByDocumentID.values
            .map { session in
                DraftSnapshotSummary(
                    id: session.document.id,
                    documentID: session.document.id,
                    documentName: session.document.name,
                    updatedAt: session.document.updatedAt,
                    pageCount: session.document.pageCount
                )
            }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func clearDraft(for documentID: UUID) async throws {
        sessionsByDocumentID.removeValue(forKey: documentID)
    }
}

final class FileDraftRecoveryService: DraftRecoveryService {
    private enum StorageError: Error {
        case applicationSupportUnavailable
    }

    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder

        self.decoder = JSONDecoder()
    }

    func saveDraft(session: EditorSession) async throws {
        let documentURL = try documentFileURL(for: session.document.id)
        let draftURL = try draftFileURL(for: session.document.id)
        try ensureDocumentDirectoryExists(for: session.document.id)
        let documentData = try encoder.encode(session.document)
        try documentData.write(to: documentURL, options: .atomic)
        let draftData = try encoder.encode(session)
        try draftData.write(to: draftURL, options: .atomic)
    }

    func restoreLatestDraft() async throws -> EditorSession? {
        try loadAllSessions()
            .max { lhs, rhs in
                lhs.document.updatedAt < rhs.document.updatedAt
            }
    }

    func restoreDraft(for documentID: UUID) async throws -> EditorSession? {
        let draftURL = try draftFileURL(for: documentID)
        guard fileManager.fileExists(atPath: draftURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: draftURL)
        return try decoder.decode(EditorSession.self, from: data)
    }

    func loadDraftSummaries() async throws -> [DraftSnapshotSummary] {
        try loadAllSessions()
            .map { session in
                DraftSnapshotSummary(
                    id: session.document.id,
                    documentID: session.document.id,
                    documentName: session.document.name,
                    updatedAt: session.document.updatedAt,
                    pageCount: session.document.pageCount
                )
            }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func clearDraft(for documentID: UUID) async throws {
        let draftURL = try draftFileURL(for: documentID)
        guard fileManager.fileExists(atPath: draftURL.path) else {
            return
        }

        try fileManager.removeItem(at: draftURL)
    }

    private func loadAllSessions() throws -> [EditorSession] {
        let documentsRoot = try documentsRootDirectory()
        guard fileManager.fileExists(atPath: documentsRoot.path) else {
            return []
        }

        let documentDirectories = try fileManager.contentsOfDirectory(
            at: documentsRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        var sessions: [EditorSession] = []
        for directoryURL in documentDirectories {
            let draftURL = directoryURL.appendingPathComponent("draft.json", isDirectory: false)
            guard fileManager.fileExists(atPath: draftURL.path) else {
                continue
            }

            do {
                let data = try Data(contentsOf: draftURL)
                let session = try decoder.decode(EditorSession.self, from: data)
                sessions.append(session)
            } catch {
                continue
            }
        }

        return sessions
    }

    private func ensureDocumentDirectoryExists(for documentID: UUID) throws {
        let directoryURL = try documentDirectoryURL(for: documentID)
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    private func draftFileURL(for documentID: UUID) throws -> URL {
        try documentDirectoryURL(for: documentID).appendingPathComponent("draft.json", isDirectory: false)
    }

    private func documentFileURL(for documentID: UUID) throws -> URL {
        try documentDirectoryURL(for: documentID).appendingPathComponent("document.json", isDirectory: false)
    }

    private func documentDirectoryURL(for documentID: UUID) throws -> URL {
        try documentsRootDirectory().appendingPathComponent(documentID.uuidString, isDirectory: true)
    }

    private func documentsRootDirectory() throws -> URL {
        let applicationSupportURL = try applicationSupportDirectory()
        let documentsURL = applicationSupportURL
            .appendingPathComponent("Documents", isDirectory: true)
        try fileManager.createDirectory(
            at: documentsURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
        return documentsURL
    }

    private func applicationSupportDirectory() throws -> URL {
        guard let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw StorageError.applicationSupportUnavailable
        }

        let appSupportURL = baseURL
            .appendingPathComponent("PDFSealMaster", isDirectory: true)
        try fileManager.createDirectory(
            at: appSupportURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
        return appSupportURL
    }
}
