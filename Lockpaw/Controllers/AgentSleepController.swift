import AppKit
import IOKit.pwr_mgt
import os.log

private let logger = Logger(subsystem: "com.eriknielsen.lockpaw", category: "AgentSleep")

/// "Sleep when agents finish", app side. Tracks agent sessions from activity reports and
/// pings for the whole life of the app (a session that started before the lock counts),
/// and while locked runs `AgentSleepPolicy` on every report and on a slow tick. The
/// policy decides; this class only gathers the inputs and carries out the actions.
@MainActor
final class AgentSleepController {
    static let shared = AgentSleepController()

    private var activity = AgentActivity()
    private var policyState = AgentSleepPolicy.State()
    private var locked = false
    private var timer: Timer?
    private var observers: [Any] = []
    private var releaseHolds: (() -> Void)?
    private var restoreHolds: (() -> Void)?

    private var enabled: Bool { UserDefaults.standard.bool(forKey: AgentSleepPolicy.enabledKey) }

    private var delay: TimeInterval {
        let minutes = UserDefaults.standard.object(forKey: AgentSleepPolicy.delayKey) as? Int
        return AgentSleepPolicy.delay(minutes: minutes ?? AgentSleepPolicy.defaultDelayMinutes)
    }

    private init() {
        observers.append(NotificationCenter.default.addObserver(
            forName: .lockpawAgentActivity, object: nil, queue: .main
        ) { [weak self] notification in
            guard let report = AgentActivity.report(from: notification.userInfo) else { return }
            Task { @MainActor in self?.record(report) }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: .lockpawPing, object: nil, queue: .main
        ) { [weak self] notification in
            let ping = AgentPing.from(userInfo: notification.userInfo)
            guard let event = AgentActivity.event(for: ping.kind), let session = ping.sessionID else { return }
            Task { @MainActor in
                self?.record(AgentActivity.Report(agent: ping.agent, sessionID: session, event: event))
            }
        })
        // Hardware keyboard and scroll input while locked (InputBlocker's tap, throttled),
        // and typing in the lock screen's password field.
        observers.append(NotificationCenter.default.addObserver(
            forName: .lockpawPhysicalInput, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.locked else { return }
                self.policyState = AgentSleepPolicy.notingPresence(self.policyState, now: Date())
            }
        })
    }

    // MARK: - Lock lifecycle

    /// `release` lets the Mac sleep (Lockpaw's idle assertion); `restore` puts it back.
    func lockBegan(releaseHolds release: @escaping () -> Void, restoreHolds restore: @escaping () -> Void) {
        releaseHolds = release
        restoreHolds = restore
        locked = true
        policyState = AgentSleepPolicy.State()
        evaluate()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: Constants.Timing.agentSleepCheckInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.evaluate() }
        }
    }

    func lockEnded() {
        locked = false
        timer?.invalidate()
        timer = nil
        releaseHolds = nil
        restoreHolds = nil
        evaluate()
    }

    // MARK: - Policy

    private func record(_ report: AgentActivity.Report) {
        activity.record(report, at: Date())
        if locked { evaluate() }
    }

    private func evaluate() {
        let now = Date()
        let (next, action) = AgentSleepPolicy.step(
            policyState,
            enabled: enabled,
            locked: locked,
            workingSessions: activity.workingSessions(at: now),
            now: now,
            delay: delay
        )
        policyState = next

        switch action {
        case .none:
            break
        case .sleep:
            logger.notice("every tracked agent session has finished — sleeping")
            releaseHolds?()
            // Lid-closed mode's pmset disablesleep refuses even an explicit sleep, so it
            // has to be lifted (and the helper has to say so) before asking.
            LidSleepController.shared.setReleasedForAgents(true) {
                Self.sleepNow()
            }
        case .restoreHolds:
            logger.notice("agent work resumed (or the setting was turned off) — holding sleep off again")
            restoreHolds?()
            LidSleepController.shared.setReleasedForAgents(false)
        }
    }

    /// The console user may ask for sleep. Forced sleep overrides idle-sleep assertions,
    /// other apps' included; only `disablesleep` (lifted above) can refuse it.
    private static func sleepNow() {
        let port = IOPMFindPowerManagement(mach_port_t(MACH_PORT_NULL))
        guard port != 0 else {
            logger.error("IOPMFindPowerManagement failed — can't request sleep")
            return
        }
        let result = IOPMSleepSystem(port)
        IOServiceClose(port)
        if result != kIOReturnSuccess { logger.error("IOPMSleepSystem failed: \(result)") }
    }
}
