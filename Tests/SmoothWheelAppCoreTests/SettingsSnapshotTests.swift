import AppKit
import ScrollCore
import Testing
@testable import SmoothWheelAppCore

private struct VisibleControl: Codable {
    let type: String
    let text: String
    let frame: [Int]
    let value: String?
}
private struct SettingsSnapshot: Codable {
    let width: Int
    let height: Int
    let nativeCloseButton: Bool
    let controls: [VisibleControl]
}

@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["SMOOTHWHEEL_UI_SNAPSHOTS"] == "1"))
struct SettingsSnapshotTests {
    @Test @MainActor func actualSettingsWindowSnapshots() async throws {
        _ = NSApplication.shared
        print("Snapshot host: reduceTransparency=\(NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency), increaseContrast=\(NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast); fixture decorative background enabled")
        try #require(ProcessInfo.processInfo.operatingSystemVersion.majorVersion == 26,
                "UI goldens target macOS 26; other OS versions need separately reviewed baselines")
        let scenarios: [(String, Int, Bool, Bool, Bool)] = [
            ("paused-light", 0, false, false, false), ("active-light", 0, false, true, false),
            ("active-dark", 0, true, true, false), ("exclusions-empty-light", 1, false, true, false),
            ("exclusions-populated-light", 1, false, true, true), ("exclusions-populated-dark", 1, true, true, true),
            ("playground-light", 2, false, true, false), ("playground-dark", 2, true, true, false)
        ]
        for (name, page, dark, active, populated) in scenarios {
            // AppKit rendering is synchronous; let unrelated main-loop tests and
            // delayed resolver/diagnostic callbacks run between captures.
            try await Task.sleep(for: .milliseconds(1))
            let suite = "local.smoothwheel.tests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let engine = ScrollEngine(targets: ReplayTarget(), uptime: { 1 }, postEvent: { _ in })
            engine.speed = ScrollPreset.balanced.speed; engine.smoothing = ScrollPreset.balanced.smoothing
            engine.enabled = active
            if populated { engine.excluded = ["test.excluded.chat", "test.excluded.game"] }
            let coordinator = AppDelegate(engine: engine, defaults: defaults)
            let controller = SettingsWindowController(coordinator: coordinator, permissionGranted: { active }, resourceURL: {
                repositoryRoot.appendingPathComponent("Resources/\($0).png")
            }, allowsDecorativeBackground: { true })
            let window = try #require(controller.window)
            defer { window.close(); engine.stop() }
            let appearance = try #require(NSAppearance(named: dark ? .darkAqua : .aqua))
            window.appearance = appearance
            controller.select(page); controller.synchronizeControls()
            let root = try #require(window.contentView)
            window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
            window.orderBack(nil)
            root.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            var controls: [VisibleControl] = []
            func visit(_ view: NSView) {
                guard !view.isHidden else { return }
                var text: String?
                var value: String?
                if let field = view as? NSTextField { text = field.stringValue }
                else if let button = view as? NSButton { text = button.title.isEmpty ? button.accessibilityLabel() ?? "" : button.title; value = String(button.state.rawValue) }
                else if let slider = view as? NSSlider { text = slider.accessibilityLabel(); value = String(format: "%.3f", slider.doubleValue) }
                if let text, !text.isEmpty {
                    let rect = root.convert(view.bounds, from: view)
                    controls.append(VisibleControl(type: String(describing: type(of: view)), text: text,
                        frame: [rect.minX, rect.minY, rect.width, rect.height].map { Int($0.rounded()) }, value: value))
                }
                for child in view.subviews { visit(child) }
            }
            visit(root)
            try assertJSONSnapshot(SettingsSnapshot(width: Int(root.bounds.width), height: Int(root.bounds.height),
                nativeCloseButton: window.styleMask.contains(.closable), controls: controls), name: "settings-\(name)")
            try assertImageSnapshot(view: root, appearance: appearance, name: "settings-\(name)")
        }
    }
}

@MainActor private func assertImageSnapshot(view: NSView, appearance: NSAppearance, name: String) throws {
    let width = Int(view.bounds.width), height = Int(view.bounds.height)
    let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bitmapFormat: [], bytesPerRow: width * 4, bitsPerPixel: 32))
    bitmap.size = view.bounds.size
    let context = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
    appearance.performAsCurrentDrawingAppearance {
        view.displayIgnoringOpacity(view.bounds, in: context)
    }
    let pixels = try #require(bitmap.bitmapData)
    let visiblePixels = (0..<(width * height)).filter { pixels[$0 * 4 + 3] > 0 }.count
    try #require(visiblePixels > width * height / 2, "Refusing a blank UI snapshot")
    let range = (0..<(width * height)).map { pixels[$0 * 4] }
    try #require(Int(range.max() ?? 0) - Int(range.min() ?? 0) > 32, "Refusing a uniform UI snapshot")
    let actualData = try #require(bitmap.representation(using: .png, properties: [:]))
    let baselineURL = testRoot.appendingPathComponent("Snapshots/\(name).png")
    try actualData.write(to: artifactsRoot.appendingPathComponent("\(name).actual.png"))
    if ProcessInfo.processInfo.environment["SMOOTHWHEEL_RECORD_SNAPSHOTS"] == "1" {
        guard ProcessInfo.processInfo.environment["CI"] == nil else { Issue.record("Cannot record UI goldens in CI"); return }
        try actualData.write(to: baselineURL)
    }
    let expectedData = try Data(contentsOf: baselineURL)
    let expected = try #require(NSBitmapImageRep(data: expectedData))
    #expect(expected.pixelsWide == width && expected.pixelsHigh == height)
    guard expected.pixelsWide == width, expected.pixelsHigh == height else { return }
    let actual = try #require(NSBitmapImageRep(data: actualData))
    let a = try #require(actual.bitmapData), b = try #require(expected.bitmapData)
    #expect(actual.samplesPerPixel == expected.samplesPerPixel)
    guard actual.samplesPerPixel == expected.samplesPerPixel else { return }
    let channels = actual.samplesPerPixel
    var changed = 0, totalError = 0
    for y in 0..<height {
        for x in 0..<width {
            var largest = 0
            for c in 0..<min(3, channels) {
                let delta = abs(Int(a[y * actual.bytesPerRow + x * channels + c]) - Int(b[y * expected.bytesPerRow + x * channels + c]))
                largest = max(largest, delta); totalError += delta
            }
            if largest > 12 { changed += 1 }
        }
    }
    let fraction = Double(changed) / Double(width * height)
    let meanError = Double(totalError) / Double(width * height * 3)
    let report = ["changedPixelFraction": fraction, "meanChannelError": meanError]
    try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        .write(to: artifactsRoot.appendingPathComponent("\(name).comparison.json"))
    if fraction > 0.01 || meanError > 1.0 {
        try expectedData.write(to: artifactsRoot.appendingPathComponent("\(name).expected.png"))
        let difference = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bitmapFormat: [], bytesPerRow: width * 4, bitsPerPixel: 32))
        let diff = try #require(difference.bitmapData)
        for y in 0..<height {
            for x in 0..<width {
                let ai = y * actual.bytesPerRow + x * channels, bi = y * expected.bytesPerRow + x * channels
                let delta = (0..<3).map { abs(Int(a[ai + $0]) - Int(b[bi + $0])) }.max() ?? 0
                let i = y * difference.bytesPerRow + x * 4
                diff[i] = UInt8(min(255, delta * 4)); diff[i + 1] = 0; diff[i + 2] = 0; diff[i + 3] = 255
            }
        }
        try difference.representation(using: .png, properties: [:])?.write(to: artifactsRoot.appendingPathComponent("\(name).diff.png"))
        Issue.record("UI snapshot changed: \(name), \(fraction * 100)% pixels; inspect expected/actual images and layout JSON")
    } else {
        // Do not leave an earlier failure's diff beside a passing capture.
        for suffix in ["expected.png", "diff.png"] {
            try? FileManager.default.removeItem(at: artifactsRoot.appendingPathComponent("\(name).\(suffix)"))
        }
    }
}

@Test @MainActor func exclusionSettingsPersistAndReloadFromIsolatedDefaults() throws {
    let suite = "local.smoothwheel.tests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let engine = ScrollEngine(targets: ReplayTarget(), uptime: { 1 }, postEvent: { _ in })
    let coordinator = AppDelegate(engine: engine, defaults: defaults)
    engine.excluded = ["test.chat", "test.game"]; engine.speed = 2; engine.smoothing = 0.63; engine.reversed = true
    coordinator.saveSettings()
    let reloaded = try #require(UserDefaults(suiteName: suite))
    #expect(Set(reloaded.stringArray(forKey: "excluded") ?? []) == engine.excluded)
    #expect(reloaded.double(forKey: "speed") == 2)
    #expect(reloaded.double(forKey: "smoothing") == 0.63)
    #expect(reloaded.bool(forKey: "reversed"))
    engine.excluded.remove("test.chat"); coordinator.saveSettings()
    #expect(reloaded.stringArray(forKey: "excluded") == ["test.game"])
}
