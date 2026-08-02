import XCTest
@testable import Momentum

final class MomentumAppTests: XCTestCase {
    func testPreviewContainerUsesTheV1Schema() throws {
        let container = try ModelContainerFactory.makePreview()

        XCTAssertNotNil(container)
    }
}
