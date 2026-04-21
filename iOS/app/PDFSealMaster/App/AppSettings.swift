import Foundation

final class AppSettings: ObservableObject {
    @Published var prefersRecentFilesOnHome = true
    @Published var autoSaveDrafts = true
    @Published var defaultPreviewMode: PreviewMode = .original
}
