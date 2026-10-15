import AppKit

/// Rules for the in-overlay password field, kept out of the controller so they can be
/// unit-tested.
///
/// The field replaces the system Touch ID / password sheet. That sheet needed the overlay
/// lowered and the input tap off, and macOS turns on secure input while it is up, which
/// hides keystrokes from the tap — so Cmd+Tab, Force Quit (Cmd+Opt+Esc) and anything else
/// reached the apps behind the cover for as long as the sheet stayed open. The field never
/// lowers the overlay or stops the tap. Typing into it still turns on secure input, so
/// while it is focused the shortcuts that matter are refused by the system instead, via
/// these presentation options. They only apply while Lockpaw is the active app — and the
/// field can only be focused (so secure input can only be on) while Lockpaw is active.
enum PasswordEntryPolicy {
    /// `.disableProcessSwitching` and `.hideMenuBar` both require `.hideDock`.
    static let kioskOptions: NSApplication.PresentationOptions = [
        .hideDock,
        .hideMenuBar,
        .disableProcessSwitching,
        .disableForceQuit,
        .disableSessionTermination,
        .disableHideApplication,
        .disableAppleMenu
    ]

    /// The armed Touch ID path is off while the field is up (the LocalAuthentication agent
    /// would take activation and with it the presentation options), so a field left open
    /// and unattended closes itself and hands the sensor back.
    static func hasExpired(
        lastActivity: Date,
        now: Date,
        timeout: TimeInterval = Constants.Timing.passwordEntryIdleTimeout
    ) -> Bool {
        now.timeIntervalSince(lastActivity) >= timeout
    }

    /// Key equivalents that reach the app while the field is focused. Lockpaw is a regular
    /// app with a main menu for as long as the field is up, so Cmd+, (Settings) or a
    /// future menu item would otherwise act behind the overlay. Nothing the field needs
    /// uses Command.
    static func swallowsKeyEquivalent(modifiers: NSEvent.ModifierFlags) -> Bool {
        modifiers.contains(.command)
    }
}
