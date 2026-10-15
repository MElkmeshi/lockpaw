import XCTest
@testable import Lockpaw

final class PasswordEntryPolicyTests: XCTestCase {
    func testKioskBlocksTheReportedEscapes() {
        let options = PasswordEntryPolicy.kioskOptions
        // Cmd+Tab and Cmd+Opt+Esc both reached other apps while the old system sheet was up.
        XCTAssertTrue(options.contains(.disableProcessSwitching))
        XCTAssertTrue(options.contains(.disableForceQuit))
        XCTAssertTrue(options.contains(.disableHideApplication))
    }

    func testSessionTerminationIsLeftToTheQuitGuard() {
        XCTAssertFalse(PasswordEntryPolicy.kioskOptions.contains(.disableSessionTermination))
    }

    func testKioskOptionsAreAValidCombination() {
        // AppKit raises if these are set without .hideDock.
        let options = PasswordEntryPolicy.kioskOptions
        XCTAssertTrue(options.contains(.hideDock))
        XCTAssertFalse(options.contains(.autoHideDock))
    }

    func testFieldStaysOpenWhileRecentlyUsed() {
        let now = Date()
        XCTAssertFalse(PasswordEntryPolicy.hasExpired(lastActivity: now, now: now, timeout: 30))
        XCTAssertFalse(PasswordEntryPolicy.hasExpired(lastActivity: now.addingTimeInterval(-29.9), now: now, timeout: 30))
    }

    func testFieldClosesWhenIdle() {
        let now = Date()
        XCTAssertTrue(PasswordEntryPolicy.hasExpired(lastActivity: now.addingTimeInterval(-30), now: now, timeout: 30))
        XCTAssertTrue(PasswordEntryPolicy.hasExpired(lastActivity: .distantPast, now: now))
    }

    func testCommandKeyEquivalentsAreSwallowed() {
        XCTAssertTrue(PasswordEntryPolicy.swallowsKeyEquivalent(modifiers: [.command]))
        XCTAssertTrue(PasswordEntryPolicy.swallowsKeyEquivalent(modifiers: [.command, .shift]))
        XCTAssertTrue(PasswordEntryPolicy.swallowsKeyEquivalent(modifiers: [.command, .option]))
    }

    func testPlainTypingPassesThrough() {
        XCTAssertFalse(PasswordEntryPolicy.swallowsKeyEquivalent(modifiers: []))
        XCTAssertFalse(PasswordEntryPolicy.swallowsKeyEquivalent(modifiers: [.shift]))
        XCTAssertFalse(PasswordEntryPolicy.swallowsKeyEquivalent(modifiers: [.option]))
    }
}
