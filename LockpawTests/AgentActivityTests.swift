import XCTest
@testable import Lockpaw

final class AgentActivityTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_000)

    // MARK: - Mapping

    func testTurnStartsAndToolsAreWork_sessionEndEnds() {
        XCTAssertEqual(AgentActivity.event(forHook: "UserPromptSubmit"), .working)
        XCTAssertEqual(AgentActivity.event(forHook: "PostToolUse"), .working)
        XCTAssertEqual(AgentActivity.event(forHook: "BeforeAgent"), .working)
        XCTAssertEqual(AgentActivity.event(forHook: "AfterTool"), .working)
        XCTAssertEqual(AgentActivity.event(forHook: "SessionEnd"), .ended)
        XCTAssertNil(AgentActivity.event(forHook: "Stop"), "Stop is a ping, not activity")
        XCTAssertNil(AgentActivity.event(forHook: nil))
    }

    func testPingsEndTheTurn_exceptABarePing() {
        for kind: AgentPing.Kind in [.finished, .failed, .rateLimited, .permission, .needsInput] {
            XCTAssertEqual(AgentActivity.event(for: kind), .idle, "\(kind)")
        }
        XCTAssertNil(AgentActivity.event(for: .attention))
    }

    // MARK: - Wire format

    func testCLI_sendsOnlyAgentEventAndSession() {
        let info = AgentActivity.userInfo(
            arguments: ["activity", "--agent", "claude"],
            stdinPayload: [
                "hook_event_name": "PostToolUse",
                "session_id": "abc",
                "cwd": "/Users/me/secret-project",
                "tool_input": ["command": "ls"],
                "tool_response": "lots of output",
                "transcript_path": "/Users/me/.claude/x.jsonl",
            ]
        )
        XCTAssertEqual(info, ["agent": "claude", "hook_event_name": "PostToolUse", "session_id": "abc"])
    }

    func testCLI_sendsNothingWithoutATrackedEventOrSession() {
        XCTAssertNil(AgentActivity.userInfo(arguments: [], stdinPayload: [:]),
                     "an unparseable payload (too big, too slow) is no report, never a bare ping")
        XCTAssertNil(AgentActivity.userInfo(arguments: [], stdinPayload: ["hook_event_name": "PostToolUse"]))
        XCTAssertNil(AgentActivity.userInfo(arguments: [], stdinPayload: ["hook_event_name": "Stop", "session_id": "a"]))
    }

    func testReport_roundTripsWithTheDisplayName() {
        let info = AgentActivity.userInfo(
            arguments: ["activity", "--agent", "claude"],
            stdinPayload: ["hook_event_name": "UserPromptSubmit", "session_id": "abc"]
        )
        XCTAssertEqual(
            AgentActivity.report(from: info),
            AgentActivity.Report(agent: "Claude Code", sessionID: "abc", event: .working)
        )
        XCTAssertNil(AgentActivity.report(from: nil))
    }

    func testReportAndPing_trackTheSameSession() {
        // The ping path names the agent by display name too, so Stop clears the entry
        // the activity report made.
        var activity = AgentActivity()
        activity.record(AgentActivity.report(from: [
            "agent": "claude", "hook_event_name": "UserPromptSubmit", "session_id": "abc",
        ])!, at: t0)
        let stop = AgentPing.from(userInfo: ["agent": "claude", "hook_event_name": "Stop", "session_id": "abc"])
        activity.record(AgentActivity.event(for: stop.kind)!, agent: stop.agent, sessionID: stop.sessionID, at: t0)
        XCTAssertEqual(activity.workingSessions(at: t0), 0)
    }

    // MARK: - Tracking

    func testWorkingUntilIdleOrEnded() {
        var activity = AgentActivity()
        activity.record(.working, agent: "Claude Code", sessionID: "a", at: t0)
        activity.record(.working, agent: "Claude Code", sessionID: "b", at: t0)
        XCTAssertEqual(activity.workingSessions(at: t0), 2)

        activity.record(.idle, agent: "Claude Code", sessionID: "a", at: t0)
        XCTAssertEqual(activity.workingSessions(at: t0), 1)

        activity.record(.ended, agent: "Claude Code", sessionID: "b", at: t0)
        XCTAssertEqual(activity.workingSessions(at: t0), 0)
    }

    func testSameSessionIdUnderAnotherAgent_isAnotherSession() {
        var activity = AgentActivity()
        activity.record(.working, agent: "Claude Code", sessionID: "a", at: t0)
        activity.record(.idle, agent: "Gemini CLI", sessionID: "a", at: t0)
        XCTAssertEqual(activity.workingSessions(at: t0), 1)
    }

    func testSessionlessReports_areIgnored() {
        var activity = AgentActivity()
        activity.record(.working, agent: "Claude Code", sessionID: nil, at: t0)
        XCTAssertEqual(activity.workingSessions(at: t0), 0)
    }

    func testHeartbeatKeepsASessionAlive_silenceGoesStale() {
        // Esc sends no Stop and a killed process no SessionEnd; a stale entry must not
        // keep the Mac awake for good.
        var activity = AgentActivity()
        activity.record(.working, agent: "Claude Code", sessionID: "a", at: t0)
        let almost = t0.addingTimeInterval(AgentActivity.staleAfter - 1)
        XCTAssertEqual(activity.workingSessions(at: almost), 1)

        activity.record(.working, agent: "Claude Code", sessionID: "a", at: almost)
        XCTAssertEqual(activity.workingSessions(at: t0.addingTimeInterval(AgentActivity.staleAfter + 60)), 1)
        XCTAssertEqual(activity.workingSessions(at: almost.addingTimeInterval(AgentActivity.staleAfter)), 0)
    }
}
