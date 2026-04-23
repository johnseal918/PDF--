import XCTest
@testable import PDFSealMaster

final class PurchaseServiceTests: XCTestCase {
    func testInMemoryPurchaseServiceStartsAsFree() async {
        let service = InMemoryPurchaseService(initialState: .free)

        let state = await service.currentEntitlements()
        let canExport = await service.canUse(.export)
        let canUseCustomLibrary = await service.canUse(.customStampLibrary)

        XCTAssertEqual(state, .free)
        XCTAssertFalse(canExport)
        XCTAssertFalse(canUseCustomLibrary)
    }

    func testInMemoryPurchaseServiceUnlocksAfterPurchase() async throws {
        let service = InMemoryPurchaseService(initialState: .free)

        try await service.purchasePro()

        let state = await service.currentEntitlements()
        let canExport = await service.canUse(.export)
        let canBinding = await service.canUse(.bindingStamp)
        let canUnify = await service.canUse(.unifyStampSize)
        let canUseCustomLibrary = await service.canUse(.customStampLibrary)

        XCTAssertEqual(state, .pro)
        XCTAssertTrue(canExport)
        XCTAssertTrue(canBinding)
        XCTAssertTrue(canUnify)
        XCTAssertTrue(canUseCustomLibrary)
    }

    func testLocalPurchaseServicePersistsUnlockFlag() async throws {
        let suiteName = "PDFSealMasterTests.PurchaseService.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create isolated user defaults")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)

        let service = LocalPurchaseService(defaults: defaults)
        let initialState = await service.currentEntitlements()
        XCTAssertEqual(initialState, .free)

        try await service.purchasePro()
        let purchasedState = await service.currentEntitlements()
        let canUseCustomLibrary = await service.canUse(.customStampLibrary)
        XCTAssertEqual(purchasedState, .pro)
        XCTAssertTrue(canUseCustomLibrary)

        defaults.removePersistentDomain(forName: suiteName)
    }
}
