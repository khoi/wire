import AppKit
import XCTest
@testable import wire

final class AppListFilteringTests: XCTestCase {
    func testShouldListRegularApps() {
        XCTAssertTrue(
            LiveAppSystem.shouldListApplication(
                isTerminated: false,
                activationPolicy: .regular,
                includeAccessory: false
            )
        )
    }

    func testShouldNotListAccessoryAppsByDefault() {
        XCTAssertFalse(
            LiveAppSystem.shouldListApplication(
                isTerminated: false,
                activationPolicy: .accessory,
                includeAccessory: false
            )
        )
    }

    func testShouldListAccessoryAppsWhenIncluded() {
        XCTAssertTrue(
            LiveAppSystem.shouldListApplication(
                isTerminated: false,
                activationPolicy: .accessory,
                includeAccessory: true
            )
        )
    }

    func testShouldNotListProhibitedApps() {
        XCTAssertFalse(
            LiveAppSystem.shouldListApplication(
                isTerminated: false,
                activationPolicy: .prohibited,
                includeAccessory: true
            )
        )
    }

    func testShouldNotListTerminatedApps() {
        XCTAssertFalse(
            LiveAppSystem.shouldListApplication(
                isTerminated: true,
                activationPolicy: .regular,
                includeAccessory: true
            )
        )
    }
}
