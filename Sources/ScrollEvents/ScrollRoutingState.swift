import Foundation

public struct ScrollTarget: Equatable, Sendable {
    public let owner: String
    public let bounds: CGRect
    public init(owner: String, bounds: CGRect) { self.owner = owner; self.bounds = bounds }
}

/// A wheel burst must never alternate between raw and synthesized events because
/// an asynchronous target lookup temporarily failed or completed late.
public struct ScrollRoutingState {
    public enum Mode: Equatable { case native, smooth }
    public struct Decision {
        public let mode: Mode
        public let resetMotion: Bool
    }
    public static let burstGap = 0.18
    private var lastInput: Double?
    private var owner: String?
    private var recipientPID: Int64?
    private var mode: Mode?
    public init() {}

    public mutating func decide(target: ScrollTarget?, excluded: Set<String>, time: Double) -> Decision {
        decide(owner: target?.owner, excluded: excluded, time: time)
    }

    public mutating func decide(owner nextOwner: String?, excluded: Set<String>, time: Double,
                                recipientPID nextPID: Int64? = nil) -> Decision {
        // A different OS-assigned receiver is a different transaction, even
        // without an input pause. A late AX result alone cannot prove that.
        let changedRecipient = recipientPID != nil && nextPID != nil && recipientPID != nextPID
        let continuing = !changedRecipient && (lastInput.map { time >= $0 && time - $0 < Self.burstGap } ?? false)
        lastInput = time; recipientPID = nextPID
        if continuing, mode == .native {
            return Decision(mode: .native, resetMotion: false)
        }
        let next: Mode = excluded.isEmpty ? .smooth : nextOwner.map { excluded.contains($0) ? .native : .smooth } ?? .native
        let reset = changedRecipient || mode != next || owner != nextOwner
        owner = nextOwner; mode = next
        return Decision(mode: next, resetMotion: reset)
    }

    public mutating func useNativeForBurst() { mode = .native; owner = nil }
    public mutating func reset() { self = Self() }
}
