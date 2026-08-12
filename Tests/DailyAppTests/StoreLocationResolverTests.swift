import Foundation
import XCTest
@testable import DailyApp

final class StoreLocationResolverTests: XCTestCase {
    func testStoreURLUsesApplicationSupportBundleDirectoryAndDailyFilename() throws {
        let root = URL(fileURLWithPath: "/tmp/Daily Store Test", isDirectory: true)

        let location = StoreLocationResolver(
            bundleIdentifier: "com.daily.todo",
            applicationSupportRoot: root
        )

        XCTAssertEqual(
            location.directoryURL.path,
            "/tmp/Daily Store Test/com.daily.todo"
        )
        XCTAssertEqual(
            location.storeURL.path,
            "/tmp/Daily Store Test/com.daily.todo/Daily.store"
        )
    }

    func testPrepareDirectoryCreatesOnlyBundleSpecificDirectory() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let location = StoreLocationResolver(
            bundleIdentifier: "com.daily.todo",
            applicationSupportRoot: root
        )

        try location.prepareDirectory(fileManager: .default)

        var isDirectory: ObjCBool = false
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: location.directoryURL.path,
                isDirectory: &isDirectory
            )
        )
        XCTAssertTrue(isDirectory.boolValue)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root.appending(path: "default.store").path
            )
        )
    }
}
