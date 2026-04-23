import XCTest
@testable import PDFSealMaster

@MainActor
final class AppRouterM5Tests: XCTestCase {
    func testShowSettingsAndHelpRoutes() {
        let router = AppRouter()

        router.showSettings()
        XCTAssertEqual(router.currentRoute, .settings)

        router.showHelp()
        XCTAssertEqual(router.currentRoute, .help)

        router.showHome()
        XCTAssertEqual(router.currentRoute, .home)
    }
}
