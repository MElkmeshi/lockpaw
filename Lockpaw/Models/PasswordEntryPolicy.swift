import AppKit

/// Rules for the in-overlay password field, kept out of the controller so they can be
/// unit-tested.
///
/// The field replaces the system Touch ID / password dialog. That dialog needed the overlay
/// lowered and the input tap letting keys through, and macOS turns on secure input while it
/// is up, which hides keystrokes from the tap anyway — so Cmd+Tab, Force Quit (Cmd+Opt+Esc)
/// and anything else reached the apps behind the cover for as long as it stayed open.
///
/// The field never lowers the overlay, and the tap stays installed, but the tap is not the
/// keyboard guard while the field is focused: typing into it turns on secure input, so the
/// tap sees no keys at all. During entry the guards are these presentation options, which
/// the system enforces itself, and the Command-key filter below. The options only apply
/// while Lockpaw is the active app — and the field can only be focused (so secure input can
/// only be on) while Lockpaw is active.
///
/// `.disableForceQuit` is deliberate even though Force Quit is the usual way out of a hung
/// app: with the field up, Lockpaw is frontmost, so Cmd+Opt+Esc then Return force-quits
/// Lockpaw itself — the reported bypass, minus the visible dialog. The exposure is bounded
/// to while the field is open (it closes itself after 30 idle seconds). Session
/// termination is left alone: `TerminationPolicy` already refuses a logout's quit while
/// locked.
enum PasswordEntryPolicy {
    /// `.disableProcessSwitching` and `.hideMenuBar` both require `.hideDock`.
    static let kioskOptions: NSApplication.PresentationOptions = [
        .hideDock,
        .hideMenuBar,
        .disableProcessSwitching,
        .disableForceQuit,
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
