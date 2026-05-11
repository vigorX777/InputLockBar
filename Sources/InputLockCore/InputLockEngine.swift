import Foundation

public struct CorrectionRequest: Equatable, Sendable {
    public let token: Int
    public let targetInputSourceID: String
    public let delay: TimeInterval
    public let attempt: Int

    public init(token: Int, targetInputSourceID: String, delay: TimeInterval, attempt: Int) {
        self.token = token
        self.targetInputSourceID = targetInputSourceID
        self.delay = delay
        self.attempt = attempt
    }
}

public struct EngineReaction: Equatable, Sendable {
    public let correction: CorrectionRequest?
    public let clearedPendingCorrection: Bool

    public init(correction: CorrectionRequest?, clearedPendingCorrection: Bool = false) {
        self.correction = correction
        self.clearedPendingCorrection = clearedPendingCorrection
    }

    public static let none = EngineReaction(correction: nil)
}

private struct PendingCorrection: Sendable {
    let token: Int
    let startedAt: TimeInterval
    var attemptsStarted: Int
}

public struct InputLockEngine: Sendable {
    public static let activationWindowDuration: TimeInterval = 0.8
    public static let correctionDelay: TimeInterval = 0.12
    public static let selfTriggeredGracePeriod: TimeInterval = 0.25
    public static let retryWindowDuration: TimeInterval = 1.0
    public static let maxAttempts = 3

    public var targetInputSourceID: String
    public var isPaused: Bool
    public private(set) var frontmostAppBundleID: String?
    public private(set) var activationWindowUntil: TimeInterval?
    public private(set) var lastProgrammaticCorrectionAt: TimeInterval?
    public var pendingCorrectionToken: Int? { pendingCorrection?.token }

    private var pendingCorrection: PendingCorrection?
    private var nextToken = 1

    public init(targetInputSourceID: String, isPaused: Bool = false) {
        self.targetInputSourceID = targetInputSourceID
        self.isPaused = isPaused
    }

    public mutating func applySettings(_ settings: InputLockSettings) {
        targetInputSourceID = settings.targetInputSourceID
        isPaused = settings.isPaused
        if isPaused || targetInputSourceID.isEmpty {
            clearPendingCorrection()
        }
    }

    public mutating func handleAppActivated(bundleID: String?, at timestamp: TimeInterval) {
        frontmostAppBundleID = bundleID
        activationWindowUntil = timestamp + Self.activationWindowDuration
    }

    public mutating func handleInputSourceChanged(to newInputSourceID: String, at timestamp: TimeInterval) -> EngineReaction {
        if isPaused || targetInputSourceID.isEmpty {
            let cleared = clearPendingCorrection()
            return EngineReaction(correction: nil, clearedPendingCorrection: cleared)
        }

        if newInputSourceID == targetInputSourceID {
            let cleared = clearPendingCorrection()
            return EngineReaction(correction: nil, clearedPendingCorrection: cleared)
        }

        if let lastProgrammaticCorrectionAt,
           timestamp - lastProgrammaticCorrectionAt <= Self.selfTriggeredGracePeriod {
            return .none
        }

        guard let activationWindowUntil, timestamp <= activationWindowUntil else {
            let cleared = clearPendingCorrection()
            return EngineReaction(correction: nil, clearedPendingCorrection: cleared)
        }

        let token = nextToken
        nextToken += 1
        pendingCorrection = PendingCorrection(token: token, startedAt: timestamp, attemptsStarted: 0)
        return EngineReaction(
            correction: CorrectionRequest(
                token: token,
                targetInputSourceID: targetInputSourceID,
                delay: Self.correctionDelay,
                attempt: 1
            )
        )
    }

    public mutating func noteCorrectionAttemptStarted(token: Int, at timestamp: TimeInterval) {
        guard var pendingCorrection, pendingCorrection.token == token else {
            return
        }

        pendingCorrection.attemptsStarted = min(pendingCorrection.attemptsStarted + 1, Self.maxAttempts)
        self.pendingCorrection = pendingCorrection
        lastProgrammaticCorrectionAt = timestamp
    }

    public mutating func handlePostCorrectionCheck(token: Int, currentInputSourceID: String, at timestamp: TimeInterval) -> EngineReaction {
        guard let pendingCorrection, pendingCorrection.token == token else {
            return .none
        }

        if isPaused || currentInputSourceID == targetInputSourceID {
            let cleared = clearPendingCorrection()
            return EngineReaction(correction: nil, clearedPendingCorrection: cleared)
        }

        let isWithinRetryWindow = timestamp - pendingCorrection.startedAt <= Self.retryWindowDuration
        let canRetryAgain = pendingCorrection.attemptsStarted < Self.maxAttempts
        guard isWithinRetryWindow, canRetryAgain else {
            let cleared = clearPendingCorrection()
            return EngineReaction(correction: nil, clearedPendingCorrection: cleared)
        }

        return EngineReaction(
            correction: CorrectionRequest(
                token: pendingCorrection.token,
                targetInputSourceID: targetInputSourceID,
                delay: Self.correctionDelay,
                attempt: pendingCorrection.attemptsStarted + 1
            )
        )
    }

    @discardableResult
    private mutating func clearPendingCorrection() -> Bool {
        guard pendingCorrection != nil else {
            return false
        }

        pendingCorrection = nil
        return true
    }
}
