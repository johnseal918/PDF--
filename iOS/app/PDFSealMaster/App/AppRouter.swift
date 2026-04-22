import Foundation

final class AppRouter: ObservableObject {
    enum Route: Hashable {
        case home
        case editor(EditorSession)
        case stampImport
        case signaturePad
    }

    @Published var currentRoute: Route = .home

    func showHome() {
        currentRoute = .home
    }

    func showEditor(session: EditorSession) {
        currentRoute = .editor(session)
    }

    func showStampImport() {
        currentRoute = .stampImport
    }

    func showSignaturePad() {
        currentRoute = .signaturePad
    }
}
