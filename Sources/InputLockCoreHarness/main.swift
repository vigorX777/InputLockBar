import Foundation
import InputLockCore

struct HarnessFailure: Error, CustomStringConvertible {
    let description: String
}

@inline(__always)
func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else {
        throw HarnessFailure(description: message)
    }
}

@inline(__always)
func expectEqual<T: Equatable>(_ lhs: @autoclosure () -> T, _ rhs: @autoclosure () -> T, _ message: String) throws {
    let left = lhs()
    let right = rhs()
    guard left == right else {
        throw HarnessFailure(description: "\(message). Expected \(right), got \(left)")
    }
}

@main
struct InputLockCoreHarness {
    static func main() throws {
        let tests: [(String, () throws -> Void)] = [
            ("resolver finds selectable enabled target", testResolverFindsSelectableEnabledTarget),
            ("resolver rejects disabled target", testResolverRejectsDisabledTarget),
            ("engine schedules correction only inside activation window", testEngineSchedulesCorrectionOnlyInsideActivationWindow),
            ("engine ignores its own correction loop", testEngineIgnoresItsOwnProgrammaticCorrectionLoop),
            ("engine retries at most twice within retry window", testEngineRetriesAtMostTwiceWithinRetryWindow),
            ("paused engine does not schedule corrections", testPausedEngineDoesNotScheduleCorrections),
            ("settings store persists values", testSettingsStorePersistsValues),
        ]

        for (name, test) in tests {
            do {
                try test()
                print("PASS \(name)")
            } catch {
                fputs("FAIL \(name): \(error)\n", stderr)
                Foundation.exit(1)
            }
        }
    }

    private static func testResolverFindsSelectableEnabledTarget() throws {
        let resolver = TargetInputSourceResolver()
        let sources = [
            InputSourceDescriptor(id: "com.apple.keylayout.ABC", localizedName: "ABC", isSelectable: true, isEnabled: true),
            InputSourceDescriptor(id: "com.tencent.inputmethod.wetype.pinyin", localizedName: "微信输入法", isSelectable: true, isEnabled: true),
        ]

        let match = resolver.resolve(targetID: "com.tencent.inputmethod.wetype.pinyin", among: sources)
        try expectEqual(match?.id, "com.tencent.inputmethod.wetype.pinyin", "Resolver should return the exact enabled target")
    }

    private static func testResolverRejectsDisabledTarget() throws {
        let resolver = TargetInputSourceResolver()
        let sources = [
            InputSourceDescriptor(id: "com.tencent.inputmethod.wetype.pinyin", localizedName: "微信输入法", isSelectable: true, isEnabled: false),
        ]

        let match = resolver.resolve(targetID: "com.tencent.inputmethod.wetype.pinyin", among: sources)
        try expect(match == nil, "Disabled target should not be considered available")
    }

    private static func testEngineSchedulesCorrectionOnlyInsideActivationWindow() throws {
        var engine = InputLockEngine(targetInputSourceID: "com.tencent.inputmethod.wetype.pinyin")

        engine.handleAppActivated(bundleID: "com.apple.TextEdit", at: 100)
        let reaction = engine.handleInputSourceChanged(to: "com.apple.keylayout.ABC", at: 100.2)

        try expectEqual(engine.frontmostAppBundleID, "com.apple.TextEdit", "Engine should remember the frontmost app")
        try expectEqual(engine.activationWindowUntil, 100.8, "Engine should open an 800ms activation window")
        try expectEqual(
            reaction.correction,
            CorrectionRequest(token: 1, targetInputSourceID: "com.tencent.inputmethod.wetype.pinyin", delay: 0.12, attempt: 1),
            "Change inside the activation window should schedule correction"
        )

        let manualReaction = engine.handleInputSourceChanged(to: "com.apple.keylayout.ABC", at: 101.0)
        try expect(manualReaction.correction == nil, "Change outside the window should be treated as manual")
    }

    private static func testEngineIgnoresItsOwnProgrammaticCorrectionLoop() throws {
        var engine = InputLockEngine(targetInputSourceID: "com.tencent.inputmethod.wetype.pinyin")

        engine.handleAppActivated(bundleID: "com.apple.TextEdit", at: 200)
        let reaction = engine.handleInputSourceChanged(to: "com.apple.keylayout.ABC", at: 200.1)
        guard let token = reaction.correction?.token else {
            throw HarnessFailure(description: "Expected an initial correction token")
        }

        engine.noteCorrectionAttemptStarted(token: token, at: 200.22)
        let selfTriggered = engine.handleInputSourceChanged(to: "com.apple.keylayout.ABC", at: 200.27)

        try expect(selfTriggered.correction == nil, "Self-triggered change should not schedule another correction")
        try expectEqual(engine.pendingCorrectionToken, token, "Pending correction token should be preserved")
    }

    private static func testEngineRetriesAtMostTwiceWithinRetryWindow() throws {
        var engine = InputLockEngine(targetInputSourceID: "com.tencent.inputmethod.wetype.pinyin")

        engine.handleAppActivated(bundleID: "com.apple.TextEdit", at: 300)
        let first = engine.handleInputSourceChanged(to: "com.apple.keylayout.ABC", at: 300.1)
        guard let token = first.correction?.token else {
            throw HarnessFailure(description: "Expected an initial correction token")
        }

        engine.noteCorrectionAttemptStarted(token: token, at: 300.22)
        let second = engine.handlePostCorrectionCheck(token: token, currentInputSourceID: "com.apple.keylayout.ABC", at: 300.35)
        try expectEqual(second.correction?.attempt, 2, "First failed attempt should schedule retry #1")

        engine.noteCorrectionAttemptStarted(token: token, at: 300.47)
        let third = engine.handlePostCorrectionCheck(token: token, currentInputSourceID: "com.apple.keylayout.ABC", at: 300.62)
        try expectEqual(third.correction?.attempt, 3, "Second failed attempt should schedule retry #2")

        engine.noteCorrectionAttemptStarted(token: token, at: 300.74)
        let exhausted = engine.handlePostCorrectionCheck(token: token, currentInputSourceID: "com.apple.keylayout.ABC", at: 300.9)
        try expect(exhausted.correction == nil, "Third failed attempt should stop retrying")
        try expect(engine.pendingCorrectionToken == nil, "Retry exhaustion should clear pending correction state")
    }

    private static func testPausedEngineDoesNotScheduleCorrections() throws {
        var engine = InputLockEngine(targetInputSourceID: "com.tencent.inputmethod.wetype.pinyin", isPaused: true)

        engine.handleAppActivated(bundleID: "com.apple.TextEdit", at: 400)
        let reaction = engine.handleInputSourceChanged(to: "com.apple.keylayout.ABC", at: 400.2)

        try expect(reaction.correction == nil, "Paused engine should not schedule corrections")
    }

    private static func testSettingsStorePersistsValues() throws {
        let suiteName = "InputLockCoreHarness.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw HarnessFailure(description: "Expected isolated UserDefaults suite")
        }
        defaults.removePersistentDomain(forName: suiteName)

        let store = InputLockSettingsStore(defaults: defaults)
        store.save(InputLockSettings(
            targetInputSourceID: "com.tencent.inputmethod.wetype.pinyin",
            isPaused: true,
            launchAtLoginEnabled: true
        ))

        let restored = store.load()
        try expectEqual(restored.targetInputSourceID, "com.tencent.inputmethod.wetype.pinyin", "Stored target input source should round-trip")
        try expect(restored.isPaused, "Stored pause flag should round-trip")
        try expect(restored.launchAtLoginEnabled, "Stored launch-at-login flag should round-trip")
    }
}
