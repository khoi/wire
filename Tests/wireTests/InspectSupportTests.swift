@preconcurrency import ApplicationServices
import XCTest
@testable import wire

final class InspectSupportTests: XCTestCase {
    func testInspectElementNameUsesWindowButtonSubroleWhenTitleIsMissing() {
        XCTAssertEqual(
            inspectElementName(
                .init(
                    role: "AXButton",
                    title: nil,
                    description: nil,
                    help: nil,
                    value: nil,
                    subrole: "AXCloseButton"
                )
            ),
            "close button"
        )
        XCTAssertEqual(
            inspectElementName(
                .init(
                    role: "AXButton",
                    title: nil,
                    description: nil,
                    help: "this button also has an action to zoom the window",
                    value: nil,
                    subrole: "AXFullScreenButton"
                )
            ),
            "full screen button"
        )
        XCTAssertEqual(
            inspectElementName(
                .init(
                    role: "AXButton",
                    title: nil,
                    description: nil,
                    help: nil,
                    value: nil,
                    subrole: "AXMinimizeButton"
                )
            ),
            "minimize button"
        )
    }

    func testInspectElementNamePrefersTitleOverSubrole() {
        XCTAssertEqual(
            inspectElementName(
                .init(
                    role: "AXButton",
                    title: "Continue",
                    description: nil,
                    help: nil,
                    value: nil,
                    subrole: "AXCloseButton"
                )
            ),
            "Continue"
        )
    }

    func testAXErrorDetailIncludesCaseAndCode() {
        let detail = axErrorDetail(.actionUnsupported)
        XCTAssertTrue(detail.contains("actionUnsupported"))
        XCTAssertTrue(detail.contains(String(AXError.actionUnsupported.rawValue)))
    }
}
