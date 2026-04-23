import Foundation

enum IssueLogLevel: String, Sendable {
    case info
    case warning
    case error
    case feedback
}

enum IssueLogCategory: String, Sendable {
    case documentImport = "document.import"
    case stampImport = "stamp.import"
    case signatureImport = "signature.import"
    case draftRecovery = "draft.recovery"
    case draftSave = "draft.save"
    case export = "export"
    case purchase = "purchase"
    case feedback = "feedback"
}

protocol IssueLogService: Sendable {
    func record(
        level: IssueLogLevel,
        category: IssueLogCategory,
        message: String,
        context: [String: String]
    ) async

    func recordError(
        _ message: String,
        error: Error,
        category: IssueLogCategory,
        context: [String: String]
    ) async

    func recordFeedback(
        _ message: String,
        category: IssueLogCategory,
        context: [String: String]
    ) async
}

actor FileIssueLogService: IssueLogService {
    private let fileManager: FileManager
    private let lineFormatter: DateFormatter
    private let fileNameFormatter: DateFormatter

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager

        let lineFormatter = DateFormatter()
        lineFormatter.locale = Locale(identifier: "en_US_POSIX")
        lineFormatter.timeZone = .current
        lineFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        self.lineFormatter = lineFormatter

        let fileNameFormatter = DateFormatter()
        fileNameFormatter.locale = Locale(identifier: "en_US_POSIX")
        fileNameFormatter.timeZone = .current
        fileNameFormatter.dateFormat = "yyyy-MM-dd"
        self.fileNameFormatter = fileNameFormatter
    }

    func record(
        level: IssueLogLevel,
        category: IssueLogCategory,
        message: String,
        context: [String: String] = [:]
    ) async {
        do {
            let line = makeEntryLine(
                level: level,
                category: category,
                message: message,
                context: context
            )
            try append(line: line)
        } catch {
            // Runtime logging must never block the product flow.
        }
    }

    func recordError(
        _ message: String,
        error: Error,
        category: IssueLogCategory,
        context: [String: String] = [:]
    ) async {
        let nsError = error as NSError
        let enrichedContext = context.merging([
            "errorDomain": nsError.domain,
            "errorCode": String(nsError.code),
            "errorType": String(describing: type(of: error))
        ], uniquingKeysWith: { current, _ in current })

        await record(
            level: .error,
            category: category,
            message: "\(message) | \(String(describing: error))",
            context: enrichedContext
        )
    }

    func recordFeedback(
        _ message: String,
        category: IssueLogCategory,
        context: [String: String] = [:]
    ) async {
        await record(level: .feedback, category: category, message: message, context: context)
    }

    private func makeEntryLine(
        level: IssueLogLevel,
        category: IssueLogCategory,
        message: String,
        context: [String: String]
    ) -> String {
        let timestamp = lineFormatter.string(from: Date())
        let contextParts = context
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " | ")

        if contextParts.isEmpty {
            return "[\(timestamp)] [\(level.rawValue)] [\(category.rawValue)] \(message)\n"
        }

        return "[\(timestamp)] [\(level.rawValue)] [\(category.rawValue)] \(message) | \(contextParts)\n"
    }

    private func append(line: String) throws {
        let logFileURL = try logFileURL()
        try ensureDirectoryExists(for: logFileURL)

        let data = Data(line.utf8)
        if fileManager.fileExists(atPath: logFileURL.path) {
            let handle = try FileHandle(forWritingTo: logFileURL)
            defer { handle.closeFile() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } else {
            try data.write(to: logFileURL, options: .atomic)
        }
    }

    private func logFileURL() throws -> URL {
        let root = try applicationSupportDirectory()
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("Runtime", isDirectory: true)

        let fileName = "\(fileNameFormatter.string(from: Date())).md"
        return root.appendingPathComponent(fileName, isDirectory: false)
    }

    private func ensureDirectoryExists(for fileURL: URL) throws {
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    private func applicationSupportDirectory() throws -> URL {
        guard let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw CocoaError(.fileNoSuchFile)
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
