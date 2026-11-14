/// Shared preset definitions for controls, matching, and default settings.
public enum ScrollPreset: String, CaseIterable, Sendable {
    case precise = "Precise"
    case balanced = "Balanced"
    case relaxed = "Relaxed"

    public var speed: Double {
        switch self { case .precise: return 0.8; case .balanced: return 1; case .relaxed: return 1.2 }
    }
    public var smoothing: Double {
        switch self { case .precise: return 0.15; case .balanced: return 0.45; case .relaxed: return 0.8 }
    }
    public static func matching(speed: Double, smoothing: Double) -> Self? {
        allCases.first { abs($0.speed - speed) < 0.01 && abs($0.smoothing - smoothing) < 0.01 }
    }
}
