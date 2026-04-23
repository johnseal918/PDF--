import XCTest
@testable import PDFSealMaster

final class ReleaseReadinessServiceTests: XCTestCase {
    func testEvaluateAutoChecksPassesWithValidInputs() {
        let service = ReleaseReadinessService()
        let metadata = ReleaseBuildMetadata(
            bundleIdentifier: "com.johnseal918.pdfsealmaster",
            marketingVersion: "1.2.0",
            buildNumber: "15"
        )

        let checks = service.evaluateAutoChecks(
            metadata: metadata,
            productID: "com.johnseal918.pdfsealmaster.pro.lifetime"
        )

        XCTAssertEqual(checks.count, 4)
        XCTAssertTrue(checks.allSatisfy { $0.status == .pass })
    }

    func testEvaluateAutoChecksReturnsAttentionForInvalidInputs() {
        let service = ReleaseReadinessService()
        let metadata = ReleaseBuildMetadata(
            bundleIdentifier: "pdfsealmaster",
            marketingVersion: "v1",
            buildNumber: "0"
        )

        let checks = service.evaluateAutoChecks(
            metadata: metadata,
            productID: "pro"
        )

        XCTAssertEqual(checks.count, 4)
        XCTAssertTrue(checks.allSatisfy { $0.status == .attention })
    }
}
