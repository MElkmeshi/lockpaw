import Foundation

/// Which agent sessions are working right now, tracked from hook events, so "Sleep when
/// agents finish" can tell when the last one is done. Also compiled into the CLI, so the
/// activity wire format lives in one place. Keep this file Foundation-only.
///
/// Activity reports are a separate distributed notification from pings, sent by
/// `lockpaw activity`. A turn starting or a tool finishing must never glow the lock
/// screen, and an app that doesn't know them simply ignores them.
///
/// Only agents with turn-start hooks can be tracked: Claude Code (`UserPromptSubmit`,
/// `PostToolUse`, `SessionEnd`) and Gemini CLI (`BeforeAgent`, `AfterTool`, `SessionEnd`).
/// Codex, Cursor, Copilot and Aider only say when a turn finishes.
struct AgentActivity {
    enum Event: Equatable {
        /// A turn started, or a tool finished inside one: a sign of life.
        case working
        /// The turn ended, or the agent is blocked on the user.
        case idle
        /// The session closed.
        case ended
    }

    /// One decoded activity report.
    struct Report: Equatable {
        let agent: String?
        let sessionID: String
        let event: Event
    }

    /// Distributed notification `lockpaw activity` posts.
    static let distributedName = "com.eriknielsen.lockpaw.activity"

    /// A working session with no sign of life for this long counts as done. Claude Code
    /// sends no `Stop` when a turn is interrupted with Esc, and a killed process sends no
    /// `SessionEnd`, so without this one stale entry would keep the Mac awake for good.
    /// A heartbeat arrives after every tool call, so a real turn only goes this long
    /// without one during a single very long command.
    static let staleAfter: TimeInterval = 30 * 60

    // MARK: - Mapping

    static func event(forHook hookEvent: String?) -> Event? {
        switch hookEvent {
        case "UserPromptSubmit", "PostToolUse", "BeforeAgent", "AfterTool": return .working
        case "SessionEnd": return .ended
        default: return nil
        }
    }

    /// What a ping says about its session. A session blocked on the user counts as idle:
    /// it can't progress until they come back, and the ping has already told them.
    static func event(for kind: AgentPing.Kind) -> Event? {
        switch kind {
        case .finished, .failed, .rateLimited, .permission, .needsInput: return .idle
        case .attention: return nil
        }
    }

    // MARK: - CLI side

    /// What `lockpaw activity` sends: the agent, the hook event and the session id. Nothing
    /// else leaves the hook. Nil when the payload isn't a tracked event or has no session:
    /// there is nothing to track then. That includes a payload too big or too slow to parse
    /// (`PostToolUse` carries the tool's output), which costs one heartbeat and nothing more.
    static func userInfo(arguments: [String], stdinPayload: [String: Any]) -> [String: String]? {
        guard let hookEvent = stdinPayload[AgentPing.Key.hookEvent] as? String,
              event(forHook: hookEvent) != nil,
              let session = stdinPayload[AgentPing.Key.sessionID] as? String, !session.isEmpty else { return nil }
        var info = [AgentPing.Key.hookEvent: hookEvent, AgentPing.Key.sessionID: session]
        if let index = arguments.firstIndex(of: "--agent"), arguments.indices.contains(index + 1),
           !arguments[index + 1].isEmpty {
            info[AgentPing.Key.agent] = arguments[index + 1]
        }
        return info
    }

    // MARK: - App side

    static func report(from userInfo: [AnyHashable: Any]?) -> Report? {
        guard let hookEvent = userInfo?[AgentPing.Key.hookEvent] as? String,
              let event = event(forHook: hookEvent),
              let session = userInfo?[AgentPing.Key.sessionID] as? String, !session.isEmpty else { return nil }
        let agent = (userInfo?[AgentPing.Key.agent] as? String).flatMap { $0.isEmpty ? nil : $0 }
        return Report(agent: agent.map(AgentPing.displayName(forAgent:)), sessionID: session, event: event)
    }

    // MARK: - Tracking

    /// Working sessions, keyed by agent and session id, with their last sign of life.
    private var working: [String: Date] = [:]

    mutating func record(_ event: Event, agent: String?, sessionID: String?, at now: Date) {
        guard let sessionID else { return }
        let key = "\(agent ?? "-")/\(sessionID)"
        switch event {
        case .working: working[key] = now
        case .idle, .ended: working[key] = nil
        }
        working = working.filter { now.timeIntervalSince($0.value) < Self.staleAfter }
    }

    mutating func record(_ report: Report, at now: Date) {
        record(report.event, agent: report.agent, sessionID: report.sessionID, at: now)
    }

    func workingSessions(at now: Date) -> Int {
        working.values.filter { now.timeIntervalSince($0) < Self.staleAfter }.count
    }
}
