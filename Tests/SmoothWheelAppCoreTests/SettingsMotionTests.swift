import AppKit
import QuartzCore
import ScrollCore
import Testing
@testable import SmoothWheelAppCore

@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["SMOOTHWHEEL_UI_SNAPSHOTS"] == "1"))
struct SettingsMotionTests {
    @Test @MainActor func rapidReplacementAndReducedMotionPreserveFocus() throws {
        _ = NSApplication.shared
        let (suite, defaults) = try presetDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let engine = ScrollEngine(targets: ReplayTarget(), uptime: { 1 }, postEvent: { _ in })
        let coordinator = AppDelegate(engine: engine, defaults: defaults)
        var reduceMotion = false
        let settings = SettingsWindowController(coordinator: coordinator, reduceMotion: { reduceMotion })
        coordinator.settings = settings
        let window = try #require(settings.window)
        let root = try #require(window.contentView)
        window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
        window.orderBack(nil)
        defer { window.close(); engine.stop() }
        let launcher = try #require(buttons(in: root).first { $0.accessibilityLabel() == "Choose a scrolling preset" })

        func verifyRapidSequence() throws {
            settings.showPresetLibrary()
            let library = try #require(settings.presetPresentation as? PresetLibraryController)
            let save = try #require(buttons(in: library.view).first { $0.title == "Save" })
            let overlay = try #require(library.view.superview?.superview as? PresetOverlay)
            save.performClick(nil)
            let editor = try #require(settings.presetPresentation as? PresetNameController)
            #expect(editor.view.superview?.superview === overlay)
            #expect((root.accessibilityChildren()?.first as? NSView) === editor.view)
            #expect(editor.nameField.currentEditor() != nil)
            editor.cancelOperation(nil)
            #expect(settings.presetPresentation === library)
            #expect(window.firstResponder === save)
            settings.dismissPresetPresentation()
            #expect(settings.presetPresentation == nil && window.firstResponder === launcher)
            #expect(!editor.view.acceptsSettingsInput || editor.view.window == nil)
            #expect(departingSurfaces(in: root).count <= 1)
        }
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            window.appearance = NSAppearance(named: name)
            for _ in 0..<100 { try verifyRapidSequence() }
        }
        #expect(coordinator.presetStore.presets.isEmpty)
        var overlappingContents = 0
        func verifyOpaquePanelSwap() throws {
            reduceMotion = false
            settings.showPresetLibrary()
            let showing = try #require(settings.presetPresentation?.view.superview?.superview as? PresetOverlay)
            #expect(showing.layer?.animation(forKey: "smoothwheel.opacity")?.duration == 0.12)
            reduceMotion = true
            NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
            #expect(showing.layer?.animation(forKey: "smoothwheel.opacity") == nil)
            #expect(settings.presetPresentation?.view.superview?.superview === showing)
            reduceMotion = false
            settings.dismissPresetPresentation()
            #expect(showing.window === window)
            #expect(showing.layer?.animation(forKey: "smoothwheel.opacity")?.duration == 0.12)
            #expect(showing.hitTest(showing.frame.origin) == nil && !showing.isAccessibilityElement())
            #expect(showing.accessibilityChildren()?.isEmpty == true)
            settings.showPresetLibrary()
            #expect(settings.presetPresentation?.view.superview?.superview === showing)
            let reopened = try #require(settings.presetPresentation as? PresetLibraryController)
            let oldPanel = try #require(reopened.view.superview as? SettingsSurface)
            let oldRow = try #require(reopened.rows.first)
            let save = try #require(buttons(in: reopened.view).first { $0.title == "Save" })
            let unchanged = coordinator.configuration
            save.performClick(nil)
            let replacing = try #require(settings.presetPresentation as? PresetNameController)
            let replacementSurface = try #require(replacing.view.superview as? SettingsSurface)
            #expect(showing.subviews.last === replacementSurface)
            #expect(replacementSurface.layer?.opacity ?? 1 == 1)
            #expect(replacementSurface.layer?.animation(forKey: "smoothwheel.opacity") == nil)
            #expect(oldPanel.layer?.animation(forKey: "smoothwheel.opacity")?.duration == 0.12)
            #expect(oldPanel.window === window && !oldPanel.isInteractive)
            if !oldRow.isHiddenOrHasHiddenAncestor && !replacing.nameField.isHiddenOrHasHiddenAncestor {
                overlappingContents += 1
            }
            #expect(oldRow.isHiddenOrHasHiddenAncestor)
            #expect(!replacing.nameField.isHiddenOrHasHiddenAncestor)
            #expect(oldPanel.accessibilityChildren()?.isEmpty == true)
            #expect(oldPanel.hitTest(oldPanel.frame.origin) == nil)
            #expect(!window.makeFirstResponder(oldRow))
            oldRow.performClick(nil)
            #expect(coordinator.configuration == unchanged && settings.presetPresentation === replacing)
            replacing.cancelOperation(nil)
            #expect(settings.presetPresentation === reopened)
            #expect(oldPanel.isInteractive && window.firstResponder === save)
            #expect(!oldRow.isHiddenOrHasHiddenAncestor)
            #expect(buttons(in: reopened.view).first { $0.title == "Manage presets" }?.isHidden == true)

            save.performClick(nil)
            let settledEditor = try #require(settings.presetPresentation as? PresetNameController)
            settledEditor.nameField.stringValue = "Discarded"
            let editorSurface = try #require(settledEditor.view.superview as? SettingsSurface)
            reduceMotion = true
            NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
            reduceMotion = false
            settledEditor.cancelOperation(nil)
            #expect(editorSurface.window === window && !editorSurface.isInteractive)
            if !settledEditor.nameField.isHiddenOrHasHiddenAncestor && !oldRow.isHiddenOrHasHiddenAncestor {
                overlappingContents += 1
            }
            #expect(settledEditor.nameField.isHiddenOrHasHiddenAncestor)
            #expect(!oldRow.isHiddenOrHasHiddenAncestor)
            #expect(showing.subviews.last === reopened.view.superview)
            #expect(editorSurface.layer?.opacity ?? 1 == 1)
            #expect(editorSurface.layer?.animation(forKey: "smoothwheel.opacity") == nil)
            #expect(reopened.view.superview?.layer?.animation(forKey: "smoothwheel.opacity")?.duration == 0.12)
            #expect(settledEditor.nameField.currentEditor() == nil)
            let enter = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "\r",
                charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36))
            #expect(!editorSurface.performKeyEquivalent(with: enter))
            settledEditor.submit()
            #expect(coordinator.presetStore.presets.isEmpty && settings.presetPresentation === reopened)
            reduceMotion = true
            NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
            #expect(editorSurface.window == nil)
            #expect(showing.layer?.animationKeys()?.isEmpty != false)
            settings.dismissPresetPresentation()
            #expect(departingSurfaces(in: root).isEmpty)
            #expect(window.firstResponder === launcher)
        }
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            window.appearance = NSAppearance(named: name)
            try verifyOpaquePanelSwap()
        }
        try presetEvidence("motion-panels", ["rapidSequences": 200, "appearances": 2, "focusErrors": 0,
            "duplicateOutgoingVisuals": 0, "staleActionWrites": 0, "panelDurationMs": 120,
            "reduceMotionFinishesPresentation": true, "retainedOriginalPanel": true])
        try presetEvidence("panel-compositing", ["swapDirections": 2, "appearances": 2, "opaquePanels": 4,
            "opacityAnimationsPerSwap": 1, "panelDurationMs": 120, "swapsWithTwoVisibleContentViews": overlappingContents])

        let preset = try coordinator.presetStore.save(name: "Evening", configuration: coordinator.configuration)
        settings.showPresetManager(selecting: preset.id)
        let manager = try #require(settings.presetManager)
        let row = try #require(manager.rows.first)
        let checkmark = try #require(row.subviews.compactMap { $0 as? NSImageView }.first)
        var hiddenCheckmarks = 0
        var phantomFades = 0
        reduceMotion = false
        for appearanceName in [NSAppearance.Name.aqua, .darkAqua] {
            window.appearance = NSAppearance(named: appearanceName)
            CATransaction.begin()
            for _ in 0..<50 {
                manager.rename.performClick(nil)
                let editor = try #require(settings.presetPresentation as? PresetNameController)
                #expect(!row.isEnabled && manager.selectedID == preset.id)
                if checkmark.isHidden { hiddenCheckmarks += 1 }
                editor.cancelOperation(nil)
                #expect(row.isEnabled && !checkmark.isHidden && window.firstResponder === manager.rename)
                if !departingSurfaces(in: root).isEmpty {
                    phantomFades += 1
                }
            }
            CATransaction.commit()
        }
        try presetEvidence("rename-motion", ["renameOpenCloseCycles": 100, "appearances": 2,
            "hiddenCheckmarks": hiddenCheckmarks, "unpresentedDialogFades": phantomFades])
        #expect(hiddenCheckmarks == 0)
        #expect(phantomFades == 0)

        settings.select(0)
        settings.showPresetLibrary()
        reduceMotion = true
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        reduceMotion = false
        settings.dismissPresetPresentation()
        #expect(!departingSurfaces(in: root).isEmpty)
        window.close()
        #expect(departingSurfaces(in: root).isEmpty)
    }

    @Test @MainActor func switchRetargetingAndFailedEnableUseCommittedState() async throws {
        _ = NSApplication.shared
        let (suite, defaults) = try presetDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let engine = ScrollEngine(targets: ReplayTarget(), uptime: { 1 }, postEvent: { _ in })
        var granted = false
        var starts = 0
        let coordinator = AppDelegate(engine: engine, defaults: defaults, hasAccessibilityPermission: { granted },
                                      startEngine: { _ in starts += 1; return false })
        let settings = SettingsWindowController(coordinator: coordinator, permissionGranted: { granted }, reduceMotion: { false })
        let window = try #require(settings.window)
        let root = try #require(window.contentView)
        let enable = try #require(buttons(in: root).compactMap { $0 as? DesignSwitch }
            .first { $0.accessibilityLabel() == "Enable smooth scrolling" })
        let reverse = try #require(buttons(in: root).compactMap { $0 as? DesignSwitch }
            .first { $0.accessibilityLabel() == "Reverse mouse scroll direction" })
        window.setFrameOrigin(NSPoint(x: -10000, y: -10000)); window.orderBack(nil)
        defer { window.close(); engine.stop() }

        func waitUntil(_ condition: () -> Bool) async throws {
            let clock = ContinuousClock()
            let deadline = clock.now + .seconds(1)
            while !condition() && clock.now < deadline { try await Task.sleep(for: .milliseconds(8)) }
            try #require(condition())
        }

        for _ in 0..<100 { settings.refresh(); #expect(!enable.isAnimating && !reverse.isAnimating) }
        // Exercise the coordinator's result without opening a real system-permission sheet.
        enable.performClick(nil)
        settings.refresh()
        #expect(starts == 0 && !engine.enabled && enable.state == .off && !enable.isAnimating)
        granted = true
        enable.performClick(nil)
        settings.refresh()
        #expect(starts == 1 && !engine.enabled && enable.state == .off && !enable.isAnimating)

        coordinator.settings = settings
        engine.enabled = true
        settings.refresh()
        try await waitUntil { enable.visualProgress > 0 && enable.visualProgress < 1 }
        let beforeReversal = enable.visualProgress
        for i in 0..<100 {
            engine.enabled = i.isMultiple(of: 2) ? false : true
            settings.refresh()
            #expect(enable.state == (engine.enabled ? .on : .off))
            #expect(abs(enable.visualProgress - beforeReversal) <= 0.02)
        }
        try await waitUntil { enable.visualProgress == 1 && !enable.isAnimating }
        reverse.performClick(nil)
        #expect(engine.reversed && reverse.state == .on)
        try await waitUntil { reverse.visualProgress == 1 && !reverse.isAnimating }
        coordinator.resetScrolling()
        try await waitUntil { reverse.visualProgress == 0 && !reverse.isAnimating }
        window.close()
        #expect(!reverse.isAnimating && !enable.isAnimating)
        try presetEvidence("motion-switches", ["sameValueRefreshes": 100, "sameValueAnimationStarts": 0,
            "failedEnablePaths": 2, "failedEnableAnimations": 0, "rapidStateChanges": 100, "mismatchedStates": 0,
            "knobIntermediateProgressExercised": true, "reverseAndResetFinished": true])
    }

    @Test @MainActor func saveRevealAndListEditsPreserveStateAndGeometry() throws {
        _ = NSApplication.shared
        let (suite, defaults) = try presetDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let engine = ScrollEngine(targets: ReplayTarget(), uptime: { 1 }, postEvent: { _ in })
        let coordinator = AppDelegate(engine: engine, defaults: defaults)
        var reduceMotion = false
        let settings = SettingsWindowController(coordinator: coordinator, reduceMotion: { reduceMotion })
        coordinator.settings = settings
        let window = try #require(settings.window)
        let root = try #require(window.contentView)
        window.setFrameOrigin(NSPoint(x: -10000, y: -10000)); window.orderBack(nil)
        defer { window.close(); engine.stop() }

        func saveFromPicker(name: String) throws -> PresetLibraryController {
            settings.showPresetLibrary()
            let picker = try #require(settings.presetPresentation as? PresetLibraryController)
            try #require(buttons(in: picker.view).first { $0.title == "Save" }).performClick(nil)
            let editor = try #require(settings.presetPresentation as? PresetNameController)
            editor.nameField.stringValue = name
            editor.validateName()
            #expect(editor.submitButton.isEnabled)
            editor.submitButton.performClick(nil)
            return try #require(settings.presetPresentation as? PresetLibraryController)
        }

        let first = try saveFromPicker(name: "First")
        #expect(coordinator.presetStore.presets.map(\.name) == ["First"])
        let firstRow = try #require(first.rows.last)
        #expect(firstRow.checked && window.firstResponder === firstRow)
        #expect(firstRow.layer?.animation(forKey: "smoothwheel.opacity")?.duration == 0.18)
        let saveTranslation = firstRow.layer?.animation(forKey: "smoothwheel.position") as? CABasicAnimation
        #expect(saveTranslation == nil)
        #expect(buttons(in: first.view).contains { $0.title == "Manage presets" && !$0.isHidden })
        let initialBytes = defaults.data(forKey: SavedPresetStore.key)
        try #require(buttons(in: first.view).first { $0.title == "Save" }).performClick(nil)
        let duplicate = try #require(settings.presetPresentation as? PresetNameController)
        duplicate.nameField.stringValue = "First"
        duplicate.validateName()
        #expect(!duplicate.submitButton.isEnabled)
        duplicate.submitButton.performClick(nil)
        #expect(settings.presetPresentation === duplicate)
        duplicate.cancelOperation(nil)
        #expect(settings.presetPresentation === first)
        #expect(initialBytes == defaults.data(forKey: SavedPresetStore.key))

        let failedWrite = PresetNameController(renaming: false, name: "Failed", validate: { _ in },
                                               save: { _ in throw CocoaError(.fileWriteNoPermission) })
        _ = failedWrite.view
        var failedWriteDismissals = 0
        failedWrite.onClose = { _ in failedWriteDismissals += 1 }
        failedWrite.submit()
        #expect(failedWriteDismissals == 0 && !failedWrite.message.isHidden)
        #expect(initialBytes == defaults.data(forKey: SavedPresetStore.key))

        reduceMotion = true
        let second = try saveFromPicker(name: "Second")
        #expect(second.rows.filter(\.checked).map(\.title) == ["Second"])
        #expect(second.rows.last?.layer?.animationKeys()?.isEmpty != false)
        #expect(coordinator.presetStore.presets.count == 2)

        // Match the two-row recording, where the list shrinks after deleting its last row.
        let secondRecord = try #require(coordinator.presetStore.presets.last)
        settings.showPresetManager(selecting: secondRecord.id)
        let shortManager = try #require(settings.presetManager)
        root.layoutSubtreeIfNeeded()
        let staying = try #require(shortManager.rows.first)
        let leaving = try #require(shortManager.rows.last)
        let shortScroll = try #require(leaving.enclosingScrollView)
        let originalDeparture = root.convert(leaving.bounds, from: leaving)
        let originalSurvivor = root.convert(staying.bounds, from: staying)
        reduceMotion = false
        shortManager.delete.performClick(nil)
        let shortConfirmation = try #require(settings.presetPresentation as? PresetDeleteController)
        shortConfirmation.delete.performClick(nil)
        let fadingClip = try #require(leaving.superview as? SettingsSurface)
        #expect(!fadingClip.isInteractive && fadingClip.window === window)
        #expect(fadingClip.layer?.animation(forKey: "smoothwheel.opacity")?.duration == 0.12)
        let heightDelta = root.convert(leaving.bounds, from: leaving).minY - originalDeparture.minY
        let survivorDelta = root.convert(staying.bounds, from: staying).minY - originalSurvivor.minY
        #expect(abs(heightDelta) <= 0.5)
        #expect(abs(survivorDelta) <= 0.5)
        #expect(shortManager.rows.first === staying && shortManager.rows.count == 1)
        try presetEvidence("preset-row-motion", ["deleteDepartureDeltaPt": heightDelta,
            "deleteSurvivorDeltaPt": survivorDelta, "scrollViewFlipped": shortScroll.isFlipped,
            "departureClipFlipped": fadingClip.isFlipped,
            "saveTranslationPt": (saveTranslation?.fromValue as? NSNumber)?.doubleValue ?? 0])
        reduceMotion = true
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        #expect(fadingClip.window == nil)
        _ = try coordinator.savePreset(name: "Second")
        reduceMotion = false
        for i in 3..<SavedPresetStore.capacity { _ = try coordinator.savePreset(name: "Preset \(i)") }
        let full = try saveFromPicker(name: "Last")
        let last = try #require(full.rows.last)
        let scroll = try #require(last.enclosingScrollView)
        let document = try #require(scroll.documentView)
        #expect(coordinator.presetStore.presets.count == SavedPresetStore.capacity)
        #expect(full.rows.filter(\.checked).map(\.title) == ["Last"])
        #expect(document.visibleRect.contains(document.convert(last.bounds, from: last)))
        #expect(window.firstResponder === last)

        // A removal updates the live manager and preserves other row objects.
        let deleted = try #require(coordinator.presetStore.presets.dropFirst(14).first)
        settings.showPresetManager(selecting: deleted.id)
        let manager = try #require(settings.presetManager)
        let survivor = manager.rows[16]
        let managerScroll = try #require(survivor.enclosingScrollView)
        let managerDocument = try #require(managerScroll.documentView)
        let newTop = managerDocument.convert(survivor.bounds, from: survivor).minY
        managerScroll.contentView.scroll(to: NSPoint(x: 0, y: newTop))
        managerScroll.reflectScrolledClipView(managerScroll.contentView)
        let before = managerDocument.convert(survivor.bounds, from: survivor).minY - managerDocument.visibleRect.minY
        manager.delete.performClick(nil)
        let confirmation = try #require(settings.presetPresentation as? PresetDeleteController)
        confirmation.delete.performClick(nil)
        #expect(settings.presetManager === manager)
        #expect(manager.rows.contains { $0 === survivor })
        let after = managerDocument.convert(survivor.bounds, from: survivor).minY - managerDocument.visibleRect.minY
        #expect(abs(before - after) <= 1)
        #expect(!coordinator.presetStore.presets.contains { $0.id == deleted.id })

        let originalFrame = window.frame
        reduceMotion = true
        settings.select(0)
        let scrolling = try #require(root.accessibilityChildren()?.last as? SettingsSurface)
        reduceMotion = false
        settings.select(1)
        let exclusions = try #require(root.accessibilityChildren()?.last as? SettingsSurface)
        #expect(!scrolling.isInteractive && scrolling.window === window)
        settings.select(0)
        #expect(root.accessibilityChildren()?.last as? SettingsSurface === scrolling)
        #expect(scrolling.isInteractive && !exclusions.isInteractive)
        settings.select(2)
        #expect(window.frame == originalFrame)
        settings.select(1)
        engine.excluded = Set((0..<20).map { String(format: "test.fixture.%02d", $0) })
        settings.reloadExclusions()
        let retained = try #require(buttons(in: root).first { $0.identifier?.rawValue == "test.fixture.09" })
        let exclusionScroll = try #require(retained.enclosingScrollView)
        let exclusionDocument = try #require(exclusionScroll.documentView)
        retained.scrollToVisible(retained.bounds)
        let exclusionBefore = exclusionDocument.convert(retained.bounds, from: retained).minY - exclusionDocument.visibleRect.minY
        engine.excluded.remove("test.fixture.00")
        settings.reloadExclusions()
        #expect(buttons(in: root).contains { $0 === retained })
        let exclusionAfter = exclusionDocument.convert(retained.bounds, from: retained).minY - exclusionDocument.visibleRect.minY
        #expect(abs(exclusionBefore - exclusionAfter) <= 1)
        try presetEvidence("motion-lists", ["firstSaveVisibleRows": 1, "longListCount": SavedPresetStore.capacity,
            "savedRowDurationMs": 180, "windowHeightChangePt": 0, "managerScrollAnchorDeltaPt": after - before,
            "exclusionsScrollAnchorDeltaPt": exclusionAfter - exclusionBefore,
            "duplicateAndFailedWriteInsertions": 0, "reducedMotionSaveAnimationStarts": 0])
    }

    @MainActor private func buttons(in view: NSView) -> [NSButton] {
        (view as? NSButton).map { [$0] } ?? view.subviews.flatMap { buttons(in: $0) }
    }

    @MainActor private func departingSurfaces(in view: NSView) -> [SettingsSurface] {
        let current = (view as? SettingsSurface).flatMap {
            !$0.isInteractive && $0.layer?.animation(forKey: "smoothwheel.opacity") != nil ? [$0] : nil
        } ?? []
        return current + view.subviews.flatMap { departingSurfaces(in: $0) }
    }
}
