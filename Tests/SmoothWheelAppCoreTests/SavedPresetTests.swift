import AppKit
import ScrollCore
import Testing
@testable import SmoothWheelAppCore

@MainActor func presetEvidence(_ criterion: String, _ result: [String: Any]) throws {
    try FileManager.default.createDirectory(at: artifactsRoot, withIntermediateDirectories: true)
    let url = artifactsRoot.appendingPathComponent("saved-presets-results.json")
    var report: [String: Any] = [:]
    if let data = try? Data(contentsOf: url), let previous = try JSONSerialization.jsonObject(with: data) as? [String: Any] { report = previous }
    report[criterion] = result
    try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: url)
}

@MainActor func presetDefaults() throws -> (String, UserDefaults) {
    let suite = "local.smoothwheel.presets.tests.\(UUID().uuidString)"
    return (suite, try #require(UserDefaults(suiteName: suite)))
}

@Suite(.serialized) struct SavedPresetTests {
    @Test @MainActor func fiftyPresetsSurviveFiveReloadsExactly() throws {
        let (suite, defaults) = try presetDefaults(); defer { defaults.removePersistentDomain(forName: suite) }
        let store = SavedPresetStore(defaults: defaults)
        #expect(store.activePreset == nil); #expect(store.loadIssue == nil)
        var expected: [SavedScrollPreset] = []
        for index in 0..<50 {
            let value = ScrollConfiguration(speed: index % 2 == 0 ? 0.3 : 3,
                                             smoothing: index % 2 == 0 ? 0 : 1, reversed: index % 3 == 0)
            expected.append(try store.save(name: "Preset \(index)", configuration: value))
        }
        var matches = 0
        for _ in 0..<5 {
            let loaded = SavedPresetStore(defaults: try #require(UserDefaults(suiteName: suite)))
            #expect(loaded.presets == expected); #expect(loaded.activePreset == expected.last)
            matches += zip(loaded.presets, expected).filter { $0 == $1 }.count
        }
        #expect(matches == 250)
        #expect(throws: SavedPresetError.capacity) { try store.save(name: "Overflow", configuration: expected[0].configuration) }
        try presetEvidence("AC-1", ["expectedMatches": 250, "actualMatches": matches, "records": 50, "reloads": 5])
    }

    @Test @MainActor func validationRejectsInvalidWritesAndPreservesData() throws {
        let (suite, defaults) = try presetDefaults(); defer { defaults.removePersistentDomain(forName: suite) }
        let store = SavedPresetStore(defaults: defaults)
        let config = ScrollConfiguration(speed: 1.4, smoothing: 0.65, reversed: true)
        let saved = try store.save(name: "  Reading \n", configuration: config)
        #expect(saved.name == "Reading")
        let before = defaults.data(forKey: SavedPresetStore.key)
        let names: [(String, SavedPresetError)] = [("", .emptyName), (" \n ", .emptyName), (String(repeating: "a", count: 41), .longName),
                                                   ("Reading", .duplicateName), ("reading", .duplicateName), (" BALANCED ", .reservedName)]
        for (name, error) in names {
            #expect(throws: error) { try store.save(name: name, configuration: config) }
            #expect(defaults.data(forKey: SavedPresetStore.key) == before)
        }
        for invalid in [ScrollConfiguration(speed: .nan, smoothing: 0.5, reversed: false),
                        ScrollConfiguration(speed: .infinity, smoothing: 0.5, reversed: false),
                        ScrollConfiguration(speed: 0.2, smoothing: 0.5, reversed: false),
                        ScrollConfiguration(speed: 3.1, smoothing: 0.5, reversed: false),
                        ScrollConfiguration(speed: 1, smoothing: -.infinity, reversed: false),
                        ScrollConfiguration(speed: 1, smoothing: -0.1, reversed: false),
                        ScrollConfiguration(speed: 1, smoothing: 1.1, reversed: false)] {
            #expect(throws: SavedPresetError.invalidValues) { try store.save(name: "Invalid", configuration: invalid) }
            #expect(defaults.data(forKey: SavedPresetStore.key) == before)
        }
        _ = try store.save(name: String(repeating: "a", count: 40), configuration: config)
        let missing = UUID()
        #expect(throws: SavedPresetError.notFound) { try store.select(missing) }
        #expect(throws: SavedPresetError.notFound) { try store.rename(missing, to: "Missing") }
        #expect(throws: SavedPresetError.notFound) { try store.delete(missing) }
        for error in [SavedPresetError.emptyName, .longName, .reservedName, .duplicateName, .capacity, .invalidValues, .notFound, .unreadable, .unsupportedVersion] {
            #expect(!(error.errorDescription ?? "").isEmpty)
        }
        try presetEvidence("AC-5-input", ["rejectedNameCases": names.count, "rejectedNumericCases": 7, "invalidWrites": 0, "maximumAcceptedNameCharacters": 40])
    }

    @Test @MainActor func unreadableAndFutureCollectionsAreNotOverwritten() throws {
        let (suite, defaults) = try presetDefaults(); defer { defaults.removePersistentDomain(forName: suite) }
        let store = SavedPresetStore(defaults: defaults)
        let config = ScrollConfiguration(speed: 1, smoothing: 0.45, reversed: false)
        _ = try store.save(name: "Reading", configuration: config)
        let valid = try #require(defaults.data(forKey: SavedPresetStore.key))
        let object = try #require(JSONSerialization.jsonObject(with: valid) as? [String: Any])
        var future = object; future["schemaVersion"] = 2
        var duplicate = object
        let records = try #require(object["presets"] as? [[String: Any]])
        duplicate["presets"] = [records[0], records[0]]
        var dangling = object; dangling["activeID"] = UUID().uuidString
        var invalidName = object; var named = records[0]; named["name"] = " Reading "; invalidName["presets"] = [named]
        var invalidValue = object; var valued = records[0]
        valued["configuration"] = ["speed": 9, "smoothing": 0.5, "reversed": false]; invalidValue["presets"] = [valued]
        let cases: [(Data, SavedPresetError)] = [(Data("broken".utf8), .unreadable),
            (try JSONSerialization.data(withJSONObject: future), .unsupportedVersion),
            (try JSONSerialization.data(withJSONObject: duplicate), .unreadable),
            (try JSONSerialization.data(withJSONObject: dangling), .unreadable),
            (try JSONSerialization.data(withJSONObject: invalidName), .unreadable),
            (try JSONSerialization.data(withJSONObject: invalidValue), .unreadable)]
        for (raw, issue) in cases {
            defaults.set(raw, forKey: SavedPresetStore.key)
            let loaded = SavedPresetStore(defaults: defaults)
            #expect(loaded.loadIssue == issue); #expect(loaded.presets.isEmpty)
            #expect(throws: issue) { try loaded.save(name: "New", configuration: config) }
            #expect(throws: issue) { try loaded.select(nil) }
            #expect(throws: issue) { try loaded.delete(UUID()) }
            #expect(defaults.data(forKey: SavedPresetStore.key) == raw)
            try loaded.resetCollection()
            #expect(loaded.loadIssue == nil); #expect(SavedPresetStore(defaults: defaults).loadIssue == nil)
        }
        defaults.set("wrong value type", forKey: SavedPresetStore.key)
        #expect(SavedPresetStore(defaults: defaults).loadIssue == .unreadable)
        #expect(defaults.string(forKey: SavedPresetStore.key) == "wrong value type")
        try presetEvidence("AC-5-storage", ["malformedOrFutureCases": cases.count + 1, "overwrittenBeforeExplicitReset": 0])
    }

    @Test @MainActor func editsAreNondestructiveAndApplyCancelsOldMotion() throws {
        _ = NSApplication.shared
        let (suite, defaults) = try presetDefaults(); defer { defaults.removePersistentDomain(forName: suite) }
        let target = ReplayTarget(); target.set("other.window")
        var now = 1.0, posts = 0
        let engine = ScrollEngine(targets: target, uptime: { now }, postEvent: { _ in posts += 1 })
        defer { engine.stop() }
        let coordinator = AppDelegate(engine: engine, defaults: defaults)
        engine.speed = 1.4; engine.smoothing = 0.65; engine.reversed = true; engine.enabled = true
        engine.excluded = ["excluded.app"]
        let preset = try coordinator.savePreset(name: "Reading")
        #expect(coordinator.presetTitle == "Reading")
        engine.speed = 1.8; engine.reversed = false
        #expect(coordinator.presetTitle == "Reading — Modified")
        #expect(coordinator.presetStore.activePreset == preset)
        try coordinator.presetStore.rename(preset.id, to: "Evening")
        #expect(coordinator.presetStore.activeID == preset.id)
        #expect(coordinator.presetTitle == "Evening — Modified")
        engine.speed = 0.8; engine.smoothing = 0.2; engine.reversed = true
        let wheel = try #require(CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2, wheel1: -3, wheel2: 0, wheel3: 0))
        wheel.location = CGPoint(x: 200, y: 200)
        #expect(engine.handle(type: .scrollWheel, event: wheel) == nil); #expect(engine.isAnimating)
        try coordinator.applySavedPreset(preset.id)
        #expect(coordinator.configuration == preset.configuration)
        #expect(coordinator.presetTitle == "Evening")
        #expect(engine.enabled); #expect(engine.excluded == ["excluded.app"])
        #expect(!engine.isAnimating); now += 0.01; engine.tick(); #expect(posts == 0)
        #expect(engine.handle(type: .scrollWheel, event: wheel) == nil); #expect(engine.isAnimating)
        let unchangedData = defaults.data(forKey: SavedPresetStore.key)
        try coordinator.applySavedPreset(preset.id)
        #expect(!engine.isAnimating); now += 0.01; engine.tick(); #expect(posts == 0)
        #expect(defaults.data(forKey: SavedPresetStore.key) == unchangedData)
        let applied = coordinator.configuration
        try coordinator.presetStore.delete(preset.id)
        #expect(coordinator.configuration == applied); #expect(coordinator.presetStore.presets.isEmpty)
        #expect(coordinator.presetStore.activeID == nil)
        #expect(throws: SavedPresetError.notFound) { try coordinator.applySavedPreset(preset.id) }
        try presetEvidence("AC-2", ["restoredFields": 3, "enabledChanges": 0, "exclusionChanges": 0, "staleOutputPackets": posts, "sameValueReapplicationCancelsMotion": true])
        try presetEvidence("AC-3", ["implicitSavedValueChanges": 0, "modifiedLabelCleared": true])
        try presetEvidence("AC-4", ["renamedIDPreserved": true, "deletedRecords": 1, "activeConfigurationChangesOnDelete": 0])
    }

    @Test @MainActor func legacySettingsBuiltInsAndResetRemainCompatible() throws {
        let (suite, defaults) = try presetDefaults(); defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(2.0, forKey: "speed"); defaults.set(0.63, forKey: "smoothing")
        defaults.set(true, forKey: "reversed"); defaults.set(["excluded.app"], forKey: "excluded")
        let coordinator = AppDelegate(engine: ScrollEngine(targets: ReplayTarget(), uptime: { 1 }, postEvent: { _ in }), defaults: defaults)
        defer { coordinator.engine.stop() }
        coordinator.loadSettings()
        #expect(coordinator.configuration == ScrollConfiguration(speed: 2, smoothing: 0.63, reversed: true))
        #expect(!coordinator.engine.enabled); #expect(coordinator.engine.excluded == ["excluded.app"])
        let saved = try coordinator.savePreset(name: "Reading")
        let loaded = AppDelegate(engine: ScrollEngine(targets: ReplayTarget(), uptime: { 1 }, postEvent: { _ in }), defaults: defaults)
        defer { loaded.engine.stop() }; loaded.loadSettings()
        #expect(loaded.presetTitle == "Reading"); #expect(loaded.presetStore.activeID == saved.id)
        for preset in ScrollPreset.allCases {
            try coordinator.applyBuiltInPreset(preset)
            #expect(coordinator.engine.speed == preset.speed); #expect(coordinator.engine.smoothing == preset.smoothing)
            #expect(coordinator.engine.reversed); #expect(coordinator.presetStore.activeID == nil)
        }
        try coordinator.applySavedPreset(saved.id)
        coordinator.resetScrolling()
        #expect(coordinator.configuration == ScrollConfiguration(speed: 1, smoothing: 0.45, reversed: false))
        #expect(coordinator.presetStore.presets == [saved]); #expect(coordinator.presetTitle == "Balanced")
        #expect(coordinator.engine.excluded == ["excluded.app"])
        try coordinator.presetStore.select(nil) // No-op selection must not rewrite preferences.
        try presetEvidence("AC-6", ["legacyFieldsPreserved": 4, "builtInPairsPreserved": 3, "reversePreservedByBuiltIns": true, "savedRecordsAfterReset": 1, "relaunchSelectionRestored": true])
    }

    @Test @MainActor func nameEditorValidatesAndCancelDoesNotWrite() throws {
        _ = NSApplication.shared
        let (suite, defaults) = try presetDefaults(); defer { defaults.removePersistentDomain(forName: suite) }
        let store = SavedPresetStore(defaults: defaults)
        let value = ScrollConfiguration(speed: 1, smoothing: 0.45, reversed: false)
        _ = try store.save(name: "Reading", configuration: value)
        let before = defaults.data(forKey: SavedPresetStore.key)
        var closes = 0
        let editor = PresetNameController(renaming: false, validate: { try store.validateName($0) }, save: { try store.save(name: $0, configuration: value) })
        editor.onClose = { _ in closes += 1 }; _ = editor.view
        let normalSize = NSSize(width: 320, height: 218)
        #expect(editor.view.bounds.size == normalSize)
        #expect(editor.nameField.frame.height == 44)
        #expect(editor.cancelButton.frame.height == 44 && editor.submitButton.frame.height == 44)
        #expect(!editor.submitButton.isEnabled); #expect(editor.message.stringValue.isEmpty)
        editor.nameField.stringValue = ""
        editor.validateName()
        let blankErrorHeight = editor.view.bounds.height
        #expect(blankErrorHeight > normalSize.height)
        #expect(editor.message.frame.minY > editor.nameField.frame.maxY)
        #expect(editor.cancelButton.frame.minY > editor.message.frame.maxY)
        editor.nameField.stringValue = String(repeating: "W", count: 40)
        editor.validateName()
        #expect(editor.submitButton.isEnabled)
        #expect(editor.view.bounds.size == normalSize)
        editor.nameField.stringValue = "Reading"; editor.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
        let duplicateErrorHeight = editor.view.bounds.height
        #expect(duplicateErrorHeight > normalSize.height)
        #expect(editor.view.bounds.contains(editor.message.frame))
        #expect(!editor.submitButton.isEnabled); editor.submit()
        #expect(defaults.data(forKey: SavedPresetStore.key) == before)
        editor.cancelOperation(nil); #expect(closes == 1)
        #expect(defaults.data(forKey: SavedPresetStore.key) == before)
        editor.nameField.stringValue = "Work"; editor.validateName()
        #expect(editor.submitButton.isEnabled); editor.submit()
        #expect(store.presets.count == 2); #expect(closes == 2)
        let id = try #require(store.activeID)
        let rename = PresetNameController(renaming: true, name: "Work", validate: { try store.validateName($0, excluding: id) }, save: { try store.rename(id, to: $0) })
        _ = rename.view; rename.nameField.stringValue = "Office"; rename.validateName(); rename.submit()
        #expect(store.activePreset?.name == "Office")
        try presetEvidence("AC-4-dialog", ["cancelledWrites": 0, "invalidSubmissionsWritten": 0, "successfulCreates": 1, "successfulRenames": 1])
        let longName = String(repeating: "W", count: 40)
        let confirmation = PresetDeleteController(name: longName)
        let panel = try #require(confirmation.view as? DesignAlertPanel)
        #expect(panel.title.stringValue == "Delete “\(longName)”?")
        #expect(panel.title.frame.height > 24)
        #expect(panel.bounds.contains(panel.title.frame))
        #expect(confirmation.delete.frame.minY > panel.title.frame.maxY)
        try presetEvidence("alert-layout", ["formWidthPt": normalSize.width, "formHeightPt": normalSize.height,
            "fieldHeightPt": editor.nameField.frame.height, "actionHeightPt": editor.submitButton.frame.height,
            "blankErrorHeightPt": blankErrorHeight, "duplicateErrorHeightPt": duplicateErrorHeight,
            "longestAcceptedNameCharacters": longName.count, "longQuestionHeightPt": panel.title.frame.height,
            "longQuestionPanelHeightPt": panel.bounds.height])
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["SMOOTHWHEEL_UI_SNAPSHOTS"] == "1"))
    @MainActor func nativeLibraryActionsAndKeyboardUseTheProductionCoordinator() throws {
        _ = NSApplication.shared
        let (suite, defaults) = try presetDefaults(); defer { defaults.removePersistentDomain(forName: suite) }
        let engine = ScrollEngine(targets: ReplayTarget(), uptime: { 1 }, postEvent: { _ in })
        defer { engine.stop() }
        engine.speed = 1.4; engine.smoothing = 0.65; engine.reversed = true
        let coordinator = AppDelegate(engine: engine, defaults: defaults)
        let controller = SettingsWindowController(coordinator: coordinator, permissionGranted: { true }, reduceMotion: { true })
        coordinator.settings = controller
        let window = try #require(controller.window); defer { window.close() }
        window.setFrameOrigin(NSPoint(x: -10000, y: -10000)); window.orderBack(nil)
        func buttons(_ view: NSView) -> [NSButton] { (view as? NSButton).map { [$0] } ?? view.subviews.flatMap(buttons) }
        func button(_ title: String, in view: NSView) throws -> NSButton { try #require(buttons(view).first { $0.title == title }) }
        func markedNames(_ rows: [PresetRowButton]) -> [String] {
            rows.filter { row in
                row.subviews.contains { ($0 as? NSImageView)?.image != nil && !$0.isHiddenOrHasHiddenAncestor }
            }.map(\.title)
        }
        func closeButton(in picker: PresetLibraryController) throws -> PresetFocusButton {
            let close = buttons(picker.view).first { $0.accessibilityLabel() == "Close presets" }
            return try #require(close as? PresetFocusButton)
        }
        func checkCircularControl(_ button: PresetFocusButton, diameter: CGFloat = 36) throws {
            #expect(button.frame.size == NSSize(width: 44, height: 44))
            let disc = try #require(button.circularIconBounds)
            let inset = (44 - diameter) / 2
            #expect(disc == NSRect(x: inset, y: inset, width: diameter, height: diameter))
            #expect(disc.contains(button.keyboardFocusMarker))
            let content = try #require(window.contentView)
            let parent = try #require(content.superview)
            for point in [NSPoint(x: 1, y: 22), NSPoint(x: 43, y: 22),
                          NSPoint(x: 22, y: 1), NSPoint(x: 22, y: 43)] {
                #expect(!disc.contains(point))
                #expect(content.hitTest(parent.convert(point, from: button)) === button)
            }
        }
        func key(_ code: UInt16, characters: String = "") throws -> NSEvent {
            try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                          windowNumber: window.windowNumber, context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code))
        }
        let pointer = try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: .init(x: -10, y: -10),
            modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
            eventNumber: 0, clickCount: 1, pressure: 1))
        let hover = try #require(NSEvent.enterExitEvent(with: .mouseEntered, location: .zero,
            modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil,
            eventNumber: 0, trackingNumber: 0, userData: nil))
        controller.showPresetLibrary()
        var library = try #require(controller.presetPresentation as? PresetLibraryController)
        let savePreset = try button("Save", in: library.view)
        let presetList = try #require(library.contentView.subviews.compactMap { $0 as? NSScrollView }.first)
        let emptyLabel = try #require(presetList.documentView?.subviews.compactMap { $0 as? NSTextField }
            .first { $0.stringValue == "No saved presets yet." })
        let sectionEnd = library.view.convert(emptyLabel.bounds, from: emptyLabel).maxY
        let emptySaveGap = savePreset.frame.minY - sectionEnd
        #expect(emptySaveGap == 18)
        let emptyManage = try button("Manage presets", in: library.view)
        #expect(savePreset.image == nil)
        #expect(emptyManage.isHiddenOrHasHiddenAncestor)
        #expect(library.view.bounds.height - savePreset.frame.maxY == 20)
        window.makeFirstResponder(savePreset)
        window.sendEvent(try key(48, characters: "\t"))
        #expect(try window.firstResponder === closeButton(in: library))
        let saveAction = try #require(savePreset as? PresetFocusButton)
        saveAction.mouseEntered(with: hover)
        #expect(saveAction.showsPointerHover)
        savePreset.performClick(nil)
        let cancelledSave = try #require(controller.presetPresentation as? PresetNameController)
        let beforeSaveCancellation = defaults.data(forKey: SavedPresetStore.key)
        let editorFrame = cancelledSave.view.frame
        let fieldEditor = try #require(cancelledSave.nameField.currentEditor() as? NSTextView)
        let fieldBounds = cancelledSave.nameField.convert(cancelledSave.nameField.bounds, to: nil)
        let editingBounds = fieldEditor.convert(fieldEditor.bounds, to: nil)
        #expect(fieldBounds.contains(editingBounds))
        #expect(abs(editingBounds.midY - fieldBounds.midY) <= 2)
        fieldEditor.insertText("Cancelled", replacementRange: fieldEditor.selectedRange())
        #expect(cancelledSave.submitButton.isEnabled)
        let layout = try #require(fieldEditor.layoutManager)
        let container = try #require(fieldEditor.textContainer)
        layout.ensureLayout(for: container)
        let line = layout.usedRect(for: container).offsetBy(dx: fieldEditor.textContainerOrigin.x,
                                                          dy: fieldEditor.textContainerOrigin.y)
        let visibleLine = fieldEditor.convert(line, to: nil)
        let editingLeftInset = visibleLine.minX - fieldBounds.minX
        let editingVerticalOffset = visibleLine.midY - fieldBounds.midY
        print("Preset field text layout: leading inset \(editingLeftInset) pt, vertical offset \(editingVerticalOffset) pt.")
        #expect(abs(editingLeftInset - 12) <= 2)
        #expect(abs(editingVerticalOffset) <= 2)
        cancelledSave.nameField.stringValue = ""
        cancelledSave.validateName()
        #expect(cancelledSave.view.frame.height > editorFrame.height)
        #expect(cancelledSave.view.frame.midY == editorFrame.midY)
        let overlay = try #require(cancelledSave.view.superview?.superview as? PresetOverlay)
        let settings = try #require(window.contentView)
        let backgroundControls = buttons(settings).filter {
            !$0.isHiddenOrHasHiddenAncestor && !$0.isDescendant(of: overlay)
        }.prefix(4)
        #expect(backgroundControls.count == 4)
        for control in backgroundControls {
            let point = settings.superview?.convert(NSPoint(x: control.bounds.midX, y: control.bounds.midY), from: control)
            let hit = try #require(point.flatMap { settings.hitTest($0) })
            #expect(hit === overlay || hit.isDescendant(of: overlay))
        }
        window.sendEvent(try key(53, characters: "\u{1b}"))
        #expect(controller.presetPresentation === library)
        #expect(window.firstResponder === savePreset)
        #expect(!saveAction.showsPointerHover)
        #expect(saveAction.showsKeyboardFocus)
        #expect(defaults.data(forKey: SavedPresetStore.key) == beforeSaveCancellation)
        saveAction.mouseEntered(with: hover)
        savePreset.performClick(nil)
        let mouseCancelledSave = try #require(controller.presetPresentation as? PresetNameController)
        window.sendEvent(pointer)
        mouseCancelledSave.cancelButton.performClick(nil)
        #expect(controller.presetPresentation === library)
        #expect(window.firstResponder === savePreset)
        #expect(!saveAction.showsPointerHover && !saveAction.showsKeyboardFocus && !saveAction.isHighlighted)
        #expect(defaults.data(forKey: SavedPresetStore.key) == beforeSaveCancellation)
        try button("Save", in: library.view).performClick(nil)
        let editor = try #require(controller.presetPresentation as? PresetNameController)
        window.sendEvent(try key(123))
        editor.nameField.stringValue = "Reading"; editor.validateName(); editor.submitButton.performClick(nil)
        let savedLibrary = try #require(controller.presetPresentation as? PresetLibraryController)
        #expect(savedLibrary.rows.map(\.title) == ["Precise", "Balanced", "Relaxed", "Reading"])
        #expect(markedNames(savedLibrary.rows) == ["Reading"])
        #expect(window.firstResponder === savedLibrary.rows.last)
        let saveRowHasFocusCue = try #require(savedLibrary.rows.last).showsKeyboardFocus
        #expect(!saveRowHasFocusCue)
        let saved = try #require(coordinator.presetStore.activePreset)
        #expect(saved.configuration == ScrollConfiguration(speed: 1.4, smoothing: 0.65, reversed: true))
        engine.speed = 2; controller.synchronizeControls()
        window.sendEvent(pointer)
        controller.showPresetLibrary()
        library = try #require(controller.presetPresentation as? PresetLibraryController)
        #expect(library.rows.map(\.title) == ["Precise", "Balanced", "Relaxed", "Reading"])
        #expect(markedNames(library.rows) == ["Reading"])
        #expect(library.rows[3].accessibilityValue() as? Int == 1)
        let heading = try #require(library.contentView.subviews.compactMap { $0 as? NSScrollView }.first?.documentView?.subviews.compactMap { $0 as? NSTextField }.first)
        #expect(library.view.convert(heading.bounds, from: heading).minX == library.view.convert(library.rows[0].nameFrame, from: library.rows[0]).minX)
        #expect(library.rows[3].focusRingType == .none)
        #expect(!library.rows[3].showsKeyboardFocus)
        window.sendEvent(try key(125))
        #expect(window.firstResponder === library.rows[0])
        #expect(library.rows[0].showsKeyboardFocus)
        library.rows[0].keyDown(with: try key(126))
        #expect(window.firstResponder === library.rows[3])
        window.sendEvent(try key(48, characters: "\t"))
        #expect((window.firstResponder as? NSButton)?.title == "Save")
        window.makeFirstResponder(library.rows[3])
        library.rows[3].keyDown(with: try key(36))
        #expect(controller.presetPresentation == nil); #expect(coordinator.configuration == saved.configuration)
        controller.showPresetLibrary()
        library = try #require(controller.presetPresentation as? PresetLibraryController)
        library.rows[3].keyDown(with: try key(53))
        #expect(controller.presetPresentation == nil)
        let selector = try #require(window.firstResponder as? PresetFocusButton)
        #expect(selector.accessibilityLabel() == "Choose a scrolling preset")
        #expect(selector.image == nil)
        #expect(selector.focusRingType == .none)
        #expect(selector.showsKeyboardFocus)
        window.sendEvent(pointer)
        #expect(!selector.showsKeyboardFocus)
        let work = try coordinator.presetStore.save(name: "Work", configuration: .init(speed: 1.8, smoothing: 0.55, reversed: false))
        try coordinator.applySavedPreset(work.id)
        let before = defaults.data(forKey: SavedPresetStore.key)
        let beforeConfiguration = coordinator.configuration

        selector.mouseEntered(with: hover)
        #expect(selector.showsPointerHover)
        selector.performClick(nil)
        library = try #require(controller.presetPresentation as? PresetLibraryController)
        #expect(!selector.showsPointerHover)
        #expect(library.rows.allSatisfy { $0.menu == nil })
        let close = try closeButton(in: library)
        try checkCircularControl(close, diameter: 32)
        let pickerTitle = try #require(library.contentView.subviews.compactMap { $0 as? NSTextField }.first)
        #expect(pickerTitle.font == .systemFont(ofSize: 20, weight: .bold))
        #expect(close.frame.midY == pickerTitle.frame.midY)
        #expect(library.view.bounds.maxX - close.frame.maxX == 16)
        #expect(close.toolTip == "Close presets")
        selector.mouseEntered(with: hover)
        close.performClick(nil)
        #expect(controller.presetPresentation == nil)
        #expect(window.firstResponder === selector)
        #expect(!selector.showsPointerHover && !selector.showsKeyboardFocus && !selector.isHighlighted)

        selector.performClick(nil)
        library = try #require(controller.presetPresentation as? PresetLibraryController)
        let keyboardClose = try closeButton(in: library)
        window.makeFirstResponder(try button("Manage presets", in: library.view))
        window.sendEvent(try key(48, characters: "\t"))
        #expect(window.firstResponder === keyboardClose)
        #expect(keyboardClose.showsKeyboardFocus)
        window.sendEvent(try key(36, characters: "\r"))
        #expect(controller.presetPresentation == nil)
        #expect(window.firstResponder === selector)
        #expect(selector.showsKeyboardFocus && !selector.showsPointerHover)
        selector.performClick(nil)
        window.sendEvent(try key(53, characters: "\u{1b}"))
        #expect(controller.presetPresentation == nil)
        #expect(window.firstResponder === selector)

        selector.performClick(nil)
        library = try #require(controller.presetPresentation as? PresetLibraryController)
        let manageButton = try button("Manage presets", in: library.view)
        #expect(!manageButton.isHiddenOrHasHiddenAncestor && manageButton.isEnabled)
        let populatedSave = try button("Save", in: library.view)
        let lastSavedRow = try #require(library.rows.last)
        let populatedSaveGap = populatedSave.frame.minY - library.view.convert(lastSavedRow.bounds, from: lastSavedRow).maxY
        #expect(populatedSaveGap == 10)
        manageButton.performClick(nil)
        var manager = try #require(controller.presetManager)
        #expect(controller.presetPresentation == nil)
        let content = try #require(window.contentView)
        content.layoutSubtreeIfNeeded()
        let backFrame = content.convert(manager.back.bounds, from: manager.back)
        #expect(backFrame.minX == 18)
        #expect(content.bounds.maxY - backFrame.maxY == 18)
        func findNavigation(in view: NSView) -> PresetControl? {
            if let navigation = view as? PresetControl { return navigation }
            return view.subviews.lazy.compactMap { findNavigation(in: $0) }.first
        }
        let navigation = try #require(findNavigation(in: content))
        #expect(navigation.isHiddenOrHasHiddenAncestor)
        #expect(manager.rows.map(\.title) == ["Reading", "Work"])
        #expect(manager.rows[1].accessibilityLabel() == "Work, in use")
        let visibleRowLabels = manager.rows.flatMap { row in
            row.subviews.compactMap { $0 as? NSTextField }
                .filter { !$0.isHiddenOrHasHiddenAncestor }
                .map(\.stringValue)
        }
        #expect(visibleRowLabels == ["Reading", "Work"])
        #expect(Set(manager.rows.map { $0.nameFrame.width }).count == 1)
        #expect(markedNames(manager.rows) == ["Work"])
        #expect(!manager.back.borderless)
        try checkCircularControl(manager.back)
        #expect(manager.back.title.isEmpty)
        #expect(manager.back.accessibilityLabel() == "Back to Presets")
        #expect(manager.back.toolTip == "Back to Presets")
        #expect(manager.back.image != nil)
        manager.rows[0].performClick(nil)
        #expect(markedNames(manager.rows) == ["Reading"])
        #expect(manager.selectedID == saved.id)
        #expect(coordinator.presetStore.activeID == work.id)
        #expect(coordinator.configuration == beforeConfiguration)
        #expect(defaults.data(forKey: SavedPresetStore.key) == before)
        let title = try #require(manager.actionTitle)
        let actions = try #require(title.superview)
        #expect(buttons(actions).map(\.title) == ["Rename", "Delete"])
        #expect(title.font == .systemFont(ofSize: 20, weight: .semibold))
        for button in [manager.rename, manager.delete] {
            #expect(button.font == .systemFont(ofSize: 15, weight: .medium))
            #expect(button.frame.minX + (button.leadingInset ?? 0) == title.frame.minX + 2)
        }
        manager.rename.mouseEntered(with: hover)
        #expect(manager.rename.showsPointerHover)
        manager.rename.performClick(nil)
        var renamer = try #require(controller.presetPresentation as? PresetNameController)
        let renameBackground = [manager.rows[1], manager.rename, manager.delete, manager.back]
        #expect(renameBackground.allSatisfy { !$0.isEnabled })
        let renameCheckmarks = markedNames(manager.rows)
        #expect(renameCheckmarks == ["Reading"])
        #expect(!manager.rename.showsPointerHover)
        for control in renameBackground {
            let action = try #require(control.action)
            NSApp.sendAction(action, to: control.target, from: control)
            control.mouseEntered(with: hover)
            #expect(!control.showsPointerHover)
        }
        #expect(controller.presetManager === manager)
        #expect(manager.selectedID == saved.id)
        #expect(controller.presetPresentation === renamer)
        renamer.nameField.stringValue = "Cancelled"
        window.sendEvent(pointer)
        renamer.cancelButton.performClick(nil)
        #expect(defaults.data(forKey: SavedPresetStore.key) == before)
        #expect(window.firstResponder === manager.rename)
        #expect(!manager.rename.showsPointerHover && !manager.rename.showsKeyboardFocus && !manager.rename.isHighlighted)

        manager = try #require(controller.presetManager)
        #expect(manager.selectedID == saved.id)
        #expect(manager.rows.allSatisfy { $0.isEnabled })
        #expect(markedNames(manager.rows) == ["Reading"])
        #expect(manager.rename.isEnabled)
        manager.rename.performClick(nil)
        renamer = try #require(controller.presetPresentation as? PresetNameController)
        #expect(renamer.nameField.stringValue == "Reading")
        window.sendEvent(try key(123))
        renamer.nameField.stringValue = "Evening"
        renamer.validateName()
        renamer.submitButton.performClick(nil)
        manager = try #require(controller.presetManager)
        #expect(manager.actionTitle?.stringValue == "Evening")
        #expect(markedNames(manager.rows) == ["Evening"])
        let renamedRow = try #require(manager.rows.first)
        let renameRowHasFocusCue = renamedRow.showsKeyboardFocus
        #expect(!renameRowHasFocusCue)
        #expect(window.firstResponder === renamedRow)
        window.sendEvent(try key(125))
        #expect(window.firstResponder === manager.rows[1])
        #expect(manager.rows[1].showsKeyboardFocus)
        window.sendEvent(try key(126))
        #expect(window.firstResponder === renamedRow && renamedRow.showsKeyboardFocus)
        #expect(renamedRow.keyboardFocusColor == DesignTokens.textMuted)
        #expect(renamedRow.keyboardFocusMarker.width > renamedRow.keyboardFocusMarker.height)
        let focusMarker = renamedRow.keyboardFocusMarker
        #expect(renamedRow.isFlipped ? focusMarker.minY >= renamedRow.nameFrame.midY
                                    : focusMarker.maxY <= renamedRow.nameFrame.midY)
        #expect(coordinator.presetStore.presets.first?.id == saved.id)
        #expect(coordinator.presetStore.presets.first?.configuration == saved.configuration)

        let afterRename = defaults.data(forKey: SavedPresetStore.key)
        manager.delete.mouseEntered(with: hover)
        #expect(manager.delete.showsPointerHover)
        manager.delete.performClick(nil)
        let confirmation = try #require(controller.presetPresentation as? PresetDeleteController)
        #expect(confirmation.question == "Delete “Evening”?")
        #expect(window.firstResponder === confirmation.cancel)
        #expect(window.attachedSheet == nil)
        let controls = [manager.back, manager.rename, manager.delete] + manager.rows
        #expect(controls.allSatisfy { !$0.isEnabled })
        let deleteCheckmarks = markedNames(manager.rows)
        #expect(deleteCheckmarks == ["Evening"])
        #expect(!manager.delete.showsPointerHover)
        for control in [manager.rows[1], manager.rename, manager.delete, manager.back] {
            if let action = control.action {
                NSApp.sendAction(action, to: control.target, from: control)
            }
            control.mouseEntered(with: hover)
            #expect(!control.showsPointerHover)
        }
        #expect(controller.presetManager === manager)
        #expect(controller.presetPresentation === confirmation)
        #expect(manager.selectedID == saved.id)
        window.sendEvent(try key(48, characters: "\t"))
        #expect(window.firstResponder === confirmation.delete)
        #expect(confirmation.delete.showsKeyboardFocus)
        window.sendEvent(try key(48, characters: "\t"))
        #expect(window.firstResponder === confirmation.cancel)
        #expect(confirmation.cancel.showsKeyboardFocus)
        window.sendEvent(try key(36, characters: "\r"))
        #expect(controller.presetPresentation == nil)
        #expect(defaults.data(forKey: SavedPresetStore.key) == afterRename)
        #expect(window.firstResponder === manager.delete)
        #expect(controller.presetManager?.selectedID == saved.id)
        #expect(manager.delete.showsKeyboardFocus)
        #expect(controls.allSatisfy { $0.isEnabled })
        #expect(controls.allSatisfy { !$0.showsPointerHover })

        manager.delete.performClick(nil)
        window.sendEvent(try key(53, characters: "\u{1b}"))
        #expect(controller.presetPresentation == nil)
        #expect(defaults.data(forKey: SavedPresetStore.key) == afterRename)
        #expect(window.firstResponder === manager.delete)
        manager.delete.performClick(nil)
        let buttonCancellation = try #require(controller.presetPresentation as? PresetDeleteController)
        window.sendEvent(pointer)
        buttonCancellation.cancel.performClick(nil)
        #expect(defaults.data(forKey: SavedPresetStore.key) == afterRename)
        #expect(window.firstResponder === manager.delete)
        #expect(!manager.delete.showsPointerHover && !manager.delete.showsKeyboardFocus && !manager.delete.isHighlighted)

        manager.delete.performClick(nil)
        let deleteConfirmation = try #require(controller.presetPresentation as? PresetDeleteController)
        #expect(deleteConfirmation.delete.destructive)
        deleteConfirmation.delete.performClick(nil)
        #expect(coordinator.presetStore.presets == [work])
        #expect(coordinator.configuration == beforeConfiguration)
        manager = try #require(controller.presetManager)
        #expect(manager.selectedID == work.id)
        manager.delete.performClick(nil)
        let lastConfirmation = try #require(controller.presetPresentation as? PresetDeleteController)
        lastConfirmation.delete.performClick(nil)
        manager = try #require(controller.presetManager)
        #expect(manager.rows.isEmpty)
        #expect(manager.actionTitle == nil)
        #expect(coordinator.configuration == beforeConfiguration)
        manager.back.performClick(nil)
        #expect(controller.presetManager == nil)
        #expect(!navigation.isHiddenOrHasHiddenAncestor)
        library = try #require(controller.presetPresentation as? PresetLibraryController)
        #expect(try button("Manage presets", in: library.view).isHiddenOrHasHiddenAncestor)
        #expect(window.firstResponder === library.rows[0])
        controller.showPresetManager()
        manager = try #require(controller.presetManager)
        #expect(window.firstResponder === manager.back)
        window.sendEvent(try key(48, characters: "\t"))
        #expect(manager.back.showsKeyboardFocus)
        window.sendEvent(try key(36, characters: "\r"))
        #expect(controller.presetManager == nil)
        library = try #require(controller.presetPresentation as? PresetLibraryController)
        #expect(window.firstResponder === library.rows[0])
        for page in [1, 2] {
            controller.select(0)
            selector.mouseEntered(with: hover)
            #expect(selector.showsPointerHover)
            controller.select(page)
            #expect(!selector.showsPointerHover)
            controller.select(0)
            #expect(!selector.showsPointerHover)
        }
        try presetEvidence("preset-navigation", ["hitTargetPt": 44, "backDiscDiameterPt": 36, "closeDiscDiameterPt": 32,
            "edgeHitsOutsideDisc": 8, "closeCenterOffsetFromTitlePt": close.frame.midY - pickerTitle.frame.midY,
            "closeTrailingInsetPt": 16, "backLeadingAndTopInsetPt": 18, "disabledBackNavigations": 0,
            "closePathsRestoringSelectorFocus": 3, "backPathsRestoringPickerFocus": 2])
        try presetEvidence("preset-manager-actions", ["actionLabels": ["Rename", "Delete"],
            "writesWhenSelecting": 0, "writesWhenCancelling": 0, "explicitClicksToAction": 3,
            "deletedRecordsPerConfirmation": 1, "configurationFieldsChangedByDelete": 0,
            "keyboardTabReachesSave": true, "pointerClearsKeyboardCue": true, "selectorIcons": 0])
        try presetEvidence("preset-delete-panel", ["backgroundActionsAttempted": 4,
            "backgroundActionsExecuted": 0, "disabledControls": controls.count, "hoverCleared": true,
            "originalSelectionRestored": true, "returnCancelsAtInitialFocus": true,
            "escapeAndCancelPreservedSavedBytes": true, "focusRestoredToDelete": true,
            "keyboardFocusVisibleOnBothActions": true])
        try presetEvidence("preset-rename-panel", ["backgroundActionsAttempted": renameBackground.count,
            "backgroundActionsExecuted": 0, "hoverCleared": true, "originalSelectionRestored": true,
            "savedBytesChangedOnCancel": false, "focusRestoredToRename": true])
        try presetEvidence("preset-save-panel", ["focusRestoredToSave": true, "savedBytesChangedOnCancel": false,
            "validationResizePreservesCenter": true, "nativeFieldEditorCentered": true,
            "backgroundHitTestsBlocked": backgroundControls.count, "escapeCancelsWithFieldFocused": true])
        try presetEvidence("preset-dismissal-appearance", ["mouseDismissalPathsChecked": 4,
            "lingeringHoverOrKeyboardCuesOrPressHighlights": 0, "keyboardDismissalsWithFocusCue": 3,
            "settingsTabRoundTripsWithoutStaleHover": 2])
        try presetEvidence("preset-row-markers", ["pickerCheckmarks": 1, "managerCheckmarks": 1,
            "checkmarksDuringRenameOverlay": renameCheckmarks.count, "checkmarksDuringDeleteOverlay": deleteCheckmarks.count,
            "managementSelectionChangesActivePreset": false,
            "saveRowHasFocusCueAfterEditing": saveRowHasFocusCue,
            "renameRowHasFocusCueAfterEditing": renameRowHasFocusCue,
            "arrowNavigationShowsFocusCue": true])
        try presetEvidence("preset-manager-labels", ["visibleRowLabels": visibleRowLabels,
            "visibleInUseLabels": visibleRowLabels.filter { $0 == "In use" }.count,
            "activePresetIdentifiedInAccessibilityLabel": true])
        try presetEvidence("preset-picker-preview-corrections", ["editingTextLeadingInsetPt": editingLeftInset,
            "editingTextVerticalOffsetPt": editingVerticalOffset, "emptyPickerManageControlsVisible": 0,
            "populatedPickerManageControlsVisible": 1, "saveIcons": 0, "saveLabel": savePreset.title,
            "emptyFooterBottomInsetPt": 20, "emptyFooterTabMovesToClose": true,
            "emptySaveGapPt": emptySaveGap, "populatedSaveGapPt": populatedSaveGap])

    }

    @Test @MainActor func longLibraryIsBoundedAndUnreadableLibraryRemainsRecoverable() throws {
        _ = NSApplication.shared
        let (suite, defaults) = try presetDefaults(); defer { defaults.removePersistentDomain(forName: suite) }
        let engine = ScrollEngine(targets: ReplayTarget(), uptime: { 1 }, postEvent: { _ in }); defer { engine.stop() }
        let coordinator = AppDelegate(engine: engine, defaults: defaults)
        for index in 0..<50 { _ = try coordinator.savePreset(name: "Preset \(index)") }
        let library = PresetLibraryController(coordinator: coordinator); _ = library.view
        #expect(library.view.frame.height <= 424); #expect(library.rows.count == 53)
        let footer = try #require(library.contentView.subviews.compactMap { $0 as? NSButton }.first { $0.title == "Save" })
        #expect(!footer.isEnabled)
        try coordinator.applyBuiltInPreset(.precise)
        var closed = false; library.onClose = { closed = true }
        library.rows.last?.performClick(nil)
        #expect(closed); #expect(coordinator.presetStore.activePreset?.name == "Preset 49")
        let manager = PresetManagerController(presets: coordinator.presetStore.presets,
                                              activeID: coordinator.presetStore.activeID, selectedID: nil)
        _ = manager.view
        #expect(manager.rows.count == 50)
        let scroll = try #require(manager.rows.last?.enclosingScrollView)
        let document = try #require(scroll.documentView)
        #expect(scroll.contentSize.height < document.bounds.height)
        #expect(manager.view.convert(manager.delete.bounds, from: manager.delete).maxY <= manager.view.bounds.maxY)
        manager.rows[0].performClick(nil)
        #expect(manager.actionTitle?.stringValue == "Preset 0")
        #expect(coordinator.presetStore.activePreset?.name == "Preset 49")
        defaults.set(Data("unreadable".utf8), forKey: SavedPresetStore.key)
        let damaged = AppDelegate(engine: engine, defaults: defaults)
        let recovery = PresetLibraryController(coordinator: damaged); _ = recovery.view
        #expect(recovery.rows.count == 3)
        let disabledSave = try #require(recovery.contentView.subviews.compactMap { $0 as? NSButton }.first { $0.title == "Save" })
        #expect(!disabledSave.isEnabled)
        recovery.rows[1].performClick(nil)
        #expect(engine.speed == ScrollPreset.balanced.speed)
        #expect(defaults.data(forKey: SavedPresetStore.key) == Data("unreadable".utf8))
        try presetEvidence("AC-7-bounded-list", ["savedRecords": 50, "choiceRows": 53,
            "panelHeightPt": library.view.frame.height, "lastRowApplied": true, "unreadableBuiltInsUsable": true])
    }
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["SMOOTHWHEEL_MEASURE"] == "1"))
@MainActor func savedPresetApplicationMeasurements() throws {
    let (suite, defaults) = try presetDefaults(); defer { defaults.removePersistentDomain(forName: suite) }
    let coordinator = AppDelegate(engine: ScrollEngine(targets: ReplayTarget(), uptime: { 1 }, postEvent: { _ in }), defaults: defaults)
    defer { coordinator.engine.stop() }
    for index in 0..<50 {
        coordinator.engine.speed = index % 2 == 0 ? 0.8 : 1.8
        _ = try coordinator.savePreset(name: "Preset \(index)")
    }
    let choices = Array(coordinator.presetStore.presets.prefix(2))
    var samples: [Double] = []
    for index in 0..<1100 {
        let preset = choices[index % 2]
        let start = ProcessInfo.processInfo.systemUptime
        try coordinator.applySavedPreset(preset.id)
        let milliseconds = (ProcessInfo.processInfo.systemUptime - start) * 1000
        #expect(coordinator.configuration == preset.configuration)
        if index >= 100 { samples.append(milliseconds) }
    }
    let sorted = samples.sorted(), p95 = samples.sorted()[949]
    #expect(p95 <= 10)
    let report: [String: Any] = ["samples": sorted.count, "warmups": 100, "storedRecords": 50,
                               "p50Ms": sorted[500], "p95Ms": p95, "maximumMs": sorted.last!, "budgetP95Ms": 10,
                               "method": "Release build, real coordinator and isolated UserDefaults, alternating two presets, UI rendering excluded"]
    let directory = repositoryRoot.appendingPathComponent("artifacts/performance")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: directory.appendingPathComponent("saved-presets.json"))
    print("Saved preset apply: p95 \(p95)ms, \(sorted.count) samples")
}
