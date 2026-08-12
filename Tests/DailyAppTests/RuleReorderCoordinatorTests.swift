import Foundation
import XCTest
@testable import DailyApp

final class RuleReorderCoordinatorTests: XCTestCase {
    private let first = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private let second = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    private let third = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!

    func testDropMovesSourceBeforeTarget() {
        XCTAssertEqual(
            RuleReorderCoordinator.reordered(
                ids: [first, second, third],
                moving: third,
                before: first
            ),
            [third, first, second]
        )
    }

    func testSelfDropAndUnknownIDsAreNoOps() {
        XCTAssertNil(
            RuleReorderCoordinator.reordered(
                ids: [first, second],
                moving: first,
                before: first
            )
        )
        XCTAssertNil(
            RuleReorderCoordinator.reordered(
                ids: [first, second],
                moving: third,
                before: first
            )
        )
    }

    func testMoveByOffsetClampsAtEdges() {
        XCTAssertNil(
            RuleReorderCoordinator.reordered(
                ids: [first, second],
                moving: first,
                offset: -1
            )
        )
        XCTAssertNil(
            RuleReorderCoordinator.reordered(
                ids: [first, second],
                moving: second,
                offset: 1
            )
        )
        XCTAssertEqual(
            RuleReorderCoordinator.reordered(
                ids: [first, second],
                moving: second,
                offset: -1
            ),
            [second, first]
        )
    }
}
