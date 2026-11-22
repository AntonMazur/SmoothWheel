import AppKit
import QuartzCore
import Testing
@testable import SmoothWheelAppCore

/// Samples the actual Core Animation presentation tree at fixed offsets.
@MainActor
private final class SettingsFrameProbe {
    static let sampleRate = 120.0
    private let layer: CALayer
    private let witness = CALayer()
    private let start: TimeInterval

    init(root: NSView) throws {
        root.wantsLayer = true
        layer = try #require(root.layer)
        start = layer.convertTime(CACurrentMediaTime(), from: nil)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.speed = 0
        layer.timeOffset = start
        layer.addSublayer(witness)
        let sweep = CABasicAnimation(keyPath: "opacity")
        sweep.beginTime = start
        sweep.duration = 1
        sweep.fromValue = 0
        sweep.toValue = 1
        sweep.timingFunction = CAMediaTimingFunction(name: .linear)
        witness.add(sweep, forKey: "test.frame-clock")
        CATransaction.commit()
    }

    func presentation(at seconds: Double) async throws -> CALayer {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.timeOffset = start + seconds
        CATransaction.commit()
        CATransaction.flush()

        // The witness distinguishes the requested time from an older committed frame.
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(1)
        while clock.now < deadline {
            if let opacity = witness.presentation()?.opacity,
               abs(Double(opacity) - seconds) < 0.002,
               let presentation = layer.presentation() {
                return presentation
            }
            try await Task.sleep(for: .milliseconds(2))
        }
        return try #require(nil as CALayer?, "Core Animation did not present the requested frame at \(seconds) s")
    }

    func finish() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        witness.removeFromSuperlayer()
        layer.speed = 1
        layer.timeOffset = 0
        CATransaction.commit()
    }
}

@MainActor
private struct SettingsFrameRaster {
    let bitmap: NSBitmapImageRep

    init(layer: CALayer, size: CGSize) throws {
        let width = Int(size.width)
        let height = Int(size.height)
        bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil,
            pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bitmapFormat: [],
            bytesPerRow: width * 4, bitsPerPixel: 32))
        let context = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
        layer.render(in: context.cgContext)
    }

    /// A saturated magenta marker is visible only when a panel lets the background through.
    func backgroundSignal(at point: CGPoint) throws -> Int {
        let x = Int(point.x)
        let y = bitmap.pixelsHigh - 1 - Int(point.y)
        try #require((0..<bitmap.pixelsWide).contains(x) && (0..<bitmap.pixelsHigh).contains(y))
        let pixels = try #require(bitmap.bitmapData)
        let offset = y * bitmap.bytesPerRow + x * 4
        try #require(pixels[offset + 3] == 255, "Frame probe must sample an opaque window")
        return min(Int(pixels[offset]), Int(pixels[offset + 2])) - Int(pixels[offset + 1])
    }

    /// Measures contrast between the rendered heading and its card in a text-only region.
    func headingContrast(in rect: CGRect) throws -> Int {
        let x = Int(rect.minX)..<Int(rect.maxX)
        let y = (bitmap.pixelsHigh - Int(rect.maxY))..<(bitmap.pixelsHigh - Int(rect.minY))
        try #require(x.lowerBound >= 0 && x.upperBound <= bitmap.pixelsWide && !x.isEmpty)
        try #require(y.lowerBound >= 0 && y.upperBound <= bitmap.pixelsHigh && !y.isEmpty)
        let pixels = try #require(bitmap.bitmapData)
        var dimmest = 255
        var brightest = 0
        for row in y {
            for column in x {
                let green = Int(pixels[row * bitmap.bytesPerRow + column * 4 + 1])
                dimmest = min(dimmest, green)
                brightest = max(brightest, green)
            }
        }
        return brightest - dimmest
    }

    func write(to url: URL) throws {
        try #require(bitmap.representation(using: .png, properties: [:])).write(to: url)
    }
}

@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["SMOOTHWHEEL_UI_SNAPSHOTS"] == "1"))
struct SettingsFrameTests {
    @Test @MainActor func samplesLiveSettingsTransitionFrames() async throws {
        _ = NSApplication.shared
        for (appearance, mode) in [(NSAppearance.Name.aqua, "light"), (.darkAqua, "dark")] {
            try await verifyTransitions(appearance: appearance, mode: mode)
        }
    }

    @MainActor private func verifyTransitions(appearance: NSAppearance.Name, mode: String) async throws {
        let (suite, defaults) = try presetDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let engine = ScrollEngine(targets: ReplayTarget(), uptime: { 1 }, postEvent: { _ in })
        let coordinator = AppDelegate(engine: engine, defaults: defaults)
        var reduceMotion = true
        let settings = SettingsWindowController(coordinator: coordinator, reduceMotion: { reduceMotion })
        coordinator.settings = settings
        let window = try #require(settings.window)
        let root = try #require(window.contentView)
        window.appearance = NSAppearance(named: appearance)
        root.wantsLayer = true
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderBack(nil)
        defer { window.close(); engine.stop() }

        func settle() {
            reduceMotion = true
            NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        }

        // Put the probe behind the overlapping area of both real panels. Calibrate it
        // against the rendered Settings page before either panel covers it.
        root.layoutSubtreeIfNeeded()
        let point = CGPoint(x: root.bounds.midX, y: root.bounds.midY - 32)
        let page = try #require(root.accessibilityChildren()?.last as? NSView)
        let marker = NSView(frame: page.convert(NSRect(x: point.x - 5, y: point.y - 5,
                                                        width: 10, height: 10), from: root))
        marker.wantsLayer = true
        marker.layer?.backgroundColor = NSColor(srgbRed: 1, green: 0, blue: 1, alpha: 1).cgColor
        page.addSubview(marker)
        window.displayIfNeeded()
        let calibration = try SettingsFrameProbe(root: root)
        let markerSignal: Int
        do {
            defer { calibration.finish() }
            let openPage = try await calibration.presentation(at: 0)
            markerSignal = try SettingsFrameRaster(layer: openPage, size: root.bounds.size).backgroundSignal(at: point)
        }
        try #require(markerSignal > 200, "The background probe must be visible in the calibration frame")

        var cases: [String: [String: Double]] = [:]
        func sample(_ name: String, duration: Double,
                    action: () throws -> (CALayer, SettingsFrameRaster) throws -> Void) async throws -> Int {
            root.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            let probe = try SettingsFrameProbe(root: root)
            defer { probe.finish() }
            _ = try await probe.presentation(at: 0)
            reduceMotion = false
            let inspect = try action()
            root.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            let rate = SettingsFrameProbe.sampleRate
            let last = Int((duration * rate).rounded(.down))
            let directory = artifactsRoot.appendingPathComponent("transition-frames")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for index in 0...last {
                let frame = try await probe.presentation(at: Double(index) / rate)
                try autoreleasepool {
                    let raster = try SettingsFrameRaster(layer: frame, size: root.bounds.size)
                    if [0, last / 2, last].contains(index) {
                        try raster.write(to: directory.appendingPathComponent("\(mode)-\(name)-\(index).png"))
                    }
                    try inspect(frame, raster)
                }
            }
            _ = try await probe.presentation(at: duration + 1 / rate)
            return last + 1
        }

        func checkSwap(from outgoing: PresetCard, to incoming: PresetCard,
                       backgroundPeak: inout Double, raster: SettingsFrameRaster) throws {
            #expect(outgoing.contentView.isHiddenOrHasHiddenAncestor)
            #expect(!incoming.contentView.isHiddenOrHasHiddenAncestor)
            var layer = outgoing.contentView.layer?.presentation()
            while let candidate = layer, !candidate.isHidden { layer = candidate.superlayer }
            if outgoing.contentView.layer?.presentation() != nil {
                #expect(layer?.isHidden == true, "Outgoing content survived in the presentation tree")
            }
            let signal = Double(try raster.backgroundSignal(at: point))
            backgroundPeak = max(backgroundPeak, signal)
            #expect(signal <= 12, "Settings background showed through the overlap")
        }

        func presentedBounds(of view: NSView, in presentation: CALayer) throws -> CGRect {
            let presented = try #require(view.layer?.presentation())
            return presentation.convert(presented.bounds, from: presented)
        }

        settings.showPresetLibrary()
        let picker = try #require(settings.presetPresentation as? PresetLibraryController)
        let oldCard = try #require(picker.view as? PresetCard)
        let save = try #require(picker.contentView.subviews.compactMap { $0 as? NSButton }.first { $0.title == "Save" })
        var outgoingOpacity: [Float] = []
        var headingContrast: [Int] = []
        var backgroundPeak = -255.0
        let openFrames = try await sample("open-save", duration: DesignTokens.Motion.fast) {
            let outgoing = try #require(oldCard.superview)
            save.performClick(nil)
            let incoming = try #require(settings.presetPresentation?.view as? DesignAlertPanel)
            let heading = root.convert(incoming.title.bounds, from: incoming.title)
            return { _, raster in
                try checkSwap(from: oldCard, to: incoming, backgroundPeak: &backgroundPeak, raster: raster)
                outgoingOpacity.append(try #require(outgoing.layer?.presentation()?.opacity))
                headingContrast.append(try raster.headingContrast(in: heading))
            }
        }
        #expect(outgoingOpacity.first.map { $0 > 0.95 } == true)
        #expect(outgoingOpacity.last.map { $0 < 0.1 } == true)
        #expect(zip(outgoingOpacity, outgoingOpacity.dropFirst()).allSatisfy { $1 <= $0 + 0.01 })
        let settledContrast = try #require(headingContrast.last)
        let firstContrast = try #require(headingContrast.first)
        let minimumContrast = try #require(headingContrast.min())
        #expect(settledContrast >= 100, "The heading probe must sample visible text")
        #expect(minimumContrast >= settledContrast - 12, "The outgoing picker covered the Save heading")
        cases["openSave"] = ["frames": Double(openFrames), "peakBackgroundSignal": backgroundPeak,
                             "firstHeadingContrast": Double(firstContrast), "minHeadingContrast": Double(minimumContrast),
                             "settledHeadingContrast": Double(settledContrast)]

        settle()
        let editor = try #require(settings.presetPresentation as? PresetNameController)
        let editorCard = try #require(editor.view as? PresetCard)
        var incomingOpacity: [Float] = []
        backgroundPeak = -255
        let cancelFrames = try await sample("cancel-save", duration: DesignTokens.Motion.fast) {
            editor.cancelOperation(nil)
            let incoming = try #require(oldCard.superview)
            return { _, raster in
                try checkSwap(from: editorCard, to: oldCard, backgroundPeak: &backgroundPeak, raster: raster)
                incomingOpacity.append(try #require(incoming.layer?.presentation()?.opacity))
            }
        }
        #expect(incomingOpacity.first.map { $0 < 0.05 } == true)
        #expect(incomingOpacity.last.map { $0 > 0.95 } == true)
        #expect(zip(incomingOpacity, incomingOpacity.dropFirst()).allSatisfy { $1 >= $0 - 0.01 })
        cases["cancelSave"] = ["frames": Double(cancelFrames), "peakBackgroundSignal": backgroundPeak]

        settle()
        save.performClick(nil)
        let nameEditor = try #require(settings.presetPresentation as? PresetNameController)
        nameEditor.nameField.stringValue = "Evening"
        nameEditor.validateName()
        var savedPositions: [Double] = []
        var savedOpacity: [Float] = []
        let saveFrames = try await sample("save-row", duration: DesignTokens.Motion.normal) {
            nameEditor.submitButton.performClick(nil)
            let updated = try #require(settings.presetPresentation as? PresetLibraryController)
            let saved = try #require(updated.rows.last)
            #expect(saved.checked)
            return { frame, _ in
                savedPositions.append(try presentedBounds(of: saved, in: frame).midY)
                savedOpacity.append(try #require(saved.layer?.presentation()?.opacity))
            }
        }
        let saveDrift = try #require(savedPositions.max()) - (try #require(savedPositions.min()))
        #expect(saveDrift <= 0.5, "Added preset moved while fading")
        #expect(savedOpacity.first.map { $0 < 0.05 } == true)
        #expect(savedOpacity.last.map { $0 > 0.95 } == true)
        #expect(zip(savedOpacity, savedOpacity.dropFirst()).allSatisfy { $1 >= $0 - 0.01 })
        cases["saveRow"] = ["frames": Double(saveFrames), "verticalDriftPt": saveDrift]

        settle()
        marker.removeFromSuperview()
        let second = try coordinator.savePreset(name: "Work")
        settings.showPresetManager(selecting: second.id)
        let manager = try #require(settings.presetManager)
        let survivor = try #require(manager.rows.first)
        let departing = try #require(manager.rows.last)
        manager.delete.performClick(nil)
        let confirmation = try #require(settings.presetPresentation as? PresetDeleteController)
        root.layoutSubtreeIfNeeded()
        let initialDepartureY = root.convert(departing.bounds, from: departing).midY
        let initialSurvivorY = root.convert(survivor.bounds, from: survivor).midY
        var deleteDrift = 0.0
        var survivorDrift = 0.0
        var deleteOpacity: [Float] = []
        let deleteFrames = try await sample("delete-row", duration: DesignTokens.Motion.fast) {
            confirmation.delete.performClick(nil)
            let retirement = try #require(departing.superview)
            return { frame, _ in
                let oldY = try presentedBounds(of: departing, in: frame).midY
                let retainedY = try presentedBounds(of: survivor, in: frame).midY
                deleteDrift = max(deleteDrift, abs(oldY - initialDepartureY))
                survivorDrift = max(survivorDrift, abs(retainedY - initialSurvivorY))
                deleteOpacity.append(try #require(retirement.layer?.presentation()?.opacity))
            }
        }
        #expect(deleteDrift <= 0.5, "The departing row slipped out of its original slot")
        #expect(survivorDrift <= 0.5, "The unaffected row moved")
        #expect(deleteOpacity.first.map { $0 > 0.95 } == true)
        #expect(deleteOpacity.last.map { $0 < 0.1 } == true)
        #expect(zip(deleteOpacity, deleteOpacity.dropFirst()).allSatisfy { $1 <= $0 + 0.01 })
        cases["deleteRow"] = ["frames": Double(deleteFrames),
                              "departingDriftPt": deleteDrift, "survivorDriftPt": survivorDrift]

        settle()
        let activePreset = try #require(coordinator.presetStore.presets.first)
        try coordinator.applySavedPreset(activePreset.id)
        settings.showPresetManager(selecting: activePreset.id)
        let renameManager = try #require(settings.presetManager)
        let activeRow = try #require(renameManager.rows.first)
        let checkmark = try #require(activeRow.subviews.compactMap { $0 as? NSImageView }.first)
        var missingCheckmarks = 0
        func checkMark(_: CALayer, _: SettingsFrameRaster) throws {
            var layer: CALayer? = try #require(checkmark.layer?.presentation())
            while let candidate = layer {
                if candidate.isHidden || candidate.opacity < 0.99 {
                    missingCheckmarks += 1
                    return
                }
                layer = candidate.superlayer
            }
        }
        let renameFrames = try await sample("open-rename", duration: DesignTokens.Motion.fast) {
            renameManager.rename.performClick(nil)
            return checkMark
        }
        settle()
        let renameEditor = try #require(settings.presetPresentation as? PresetNameController)
        let cancelRenameFrames = try await sample("cancel-rename", duration: DesignTokens.Motion.fast) {
            renameEditor.cancelOperation(nil)
            return checkMark
        }
        #expect(missingCheckmarks == 0, "The active preset checkmark disappeared during Rename")
        cases["rename"] = ["frames": Double(renameFrames + cancelRenameFrames),
                           "missingCheckmarkFrames": Double(missingCheckmarks)]

        try presetEvidence("transition-frames-\(mode)", ["rateHz": SettingsFrameProbe.sampleRate, "backgroundCalibration": markerSignal,
                                                       "transitions": cases])
    }
}
