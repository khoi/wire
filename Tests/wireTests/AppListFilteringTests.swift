import AppKit
import XCTest
@testable import wire

final class AppListFilteringTests: XCTestCase {
    func testShouldListRegularApps() {
        XCTAssertTrue(
            LiveAppSystem.shouldListApplication(
                isTerminated: false,
                activationPolicy: .regular
            )
        )
    }

    func testShouldListAccessoryApps() {
        XCTAssertTrue(
            LiveAppSystem.shouldListApplication(
                isTerminated: false,
                activationPolicy: .accessory
            )
        )
    }

    func testShouldNotListProhibitedApps() {
        XCTAssertFalse(
            LiveAppSystem.shouldListApplication(
                isTerminated: false,
                activationPolicy: .prohibited
            )
        )
    }

    func testShouldNotListTerminatedApps() {
        XCTAssertFalse(
            LiveAppSystem.shouldListApplication(
                isTerminated: true,
                activationPolicy: .regular
            )
        )
    }
}
