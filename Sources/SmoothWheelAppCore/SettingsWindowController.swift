import AppKit
import ScrollCore
import ApplicationServices
import UniformTypeIdentifiers

final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private unowned let coordinator: AppDelegate
    private let content = SettingsContentView()
    private let motion: SettingsMotion
    private let settingsScene = SettingsSurface()
    private let settingsBody = SettingsSurface()
    private var managerScene: SettingsSurface?
    private var pages: [SettingsSurface] = []
    private var selectedPage: Int?
    private let navigation = PresetControl(labels: ["Scrolling", "App exclusions", "Playground"], raisedSelection: true)
    private let permissionTitle = NSTextField(labelWithString: "Accessibility setup")
    private let permissionDetail = NSTextField(wrappingLabelWithString: "Allow SmoothWheel to control scrolling.")
    private var permissionButton: DesignButton!
    private var activeSwitch: DesignSwitch!
    private var reverse: DesignSwitch!
    private let speed = NSSlider()
    private let smooth = NSSlider()
    private let speedValue = NSTextField(labelWithString: "")
    private let smoothValue = NSTextField(labelWithString: "")
    private let presetButton = PresetFocusButton("Balanced")
    private(set) var presetPresentation: NSViewController?
    private(set) var presetManager: PresetManagerController?
    private var presetOverlay: PresetOverlay?
    private var presetPanel: SettingsSurface?
    private var exclusionList = NSStackView()
    private var exclusionScroll = NSScrollView()
    private var exclusionRows: [String: NSView] = [:]
    private var exclusionPlaceholder: [NSView] = []
    private let aura = NSImageView()

    private let permissionGranted: () -> Bool
    private let resourceURL: (String) -> URL?
    private let allowsDecorativeBackground: () -> Bool
    init(coordinator: AppDelegate, permissionGranted: @escaping () -> Bool = { AXIsProcessTrusted() },
         resourceURL: @escaping (String) -> URL? = { Bundle.main.url(forResource: $0, withExtension: "png") },
         allowsDecorativeBackground: @escaping () -> Bool = {
             !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency && !NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
         }, reduceMotion: @escaping () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }) {
        motion = SettingsMotion(reduceMotion: reduceMotion)
        self.permissionGranted = permissionGranted
        self.resourceURL = resourceURL
        self.allowsDecorativeBackground = allowsDecorativeBackground
        self.coordinator = coordinator
        let window = SettingsWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 660),
            styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "SmoothWheel"; window.titleVisibility = .hidden
        // Reserve the real AppKit titlebar so native window controls remain visible
        // above the custom settings content.
        window.titlebarAppearsTransparent = false; window.isReleasedWhenClosed = false
        window.backgroundColor = DesignTokens.paper
        window.isMovableByWindowBackground = true
        // Explicit preview flags affect only this process, never system appearance or saved preferences.
        if CommandLine.arguments.contains("--preview-light") { window.appearance = NSAppearance(named: .aqua) }
        if CommandLine.arguments.contains("--preview-dark") { window.appearance = NSAppearance(named: .darkAqua) }
        window.center()
        super.init(window: window)
        window.delegate = self
        content.onAppearanceChange = { [weak self] in self?.finishMotion() }
        build()
        window.setContentSize(NSSize(width: 560, height: 660))
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(displayOptionsChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
    }
    required init?(coder: NSCoder) { fatalError("Use init(coordinator:)") }

    func windowWillClose(_ notification: Notification) {
        finishMotion()
        dismissPresetPresentation(animated: false)
    }

    @objc private func displayOptionsChanged() {
        finishMotion()
        refresh()
    }

    private func finishMotion() {
        motion.finish()
        activeSwitch?.finishTransition()
        reverse?.finishTransition()
    }

    private func text(_ value: String, size: CGFloat = DesignTokens.Font.body, weight: NSFont.Weight = .regular, secondary: Bool = false) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: value)
        field.font = .systemFont(ofSize: size, weight: weight)
        field.textColor = secondary ? DesignTokens.textMuted : DesignTokens.text
        return field
    }
    private func stack(_ views: [NSView], spacing: CGFloat = DesignTokens.Space.md, horizontal: Bool = false) -> NSStackView {
        let result = NSStackView(views: views); result.orientation = horizontal ? .horizontal : .vertical
        result.alignment = horizontal ? .centerY : .leading; result.spacing = spacing
        result.distribution = .fill
        return result
    }
    private func pin(_ view: NSView, to parent: NSView, inset: CGFloat = 0) {
        view.translatesAutoresizingMaskIntoConstraints = false; parent.addSubview(view)
        NSLayoutConstraint.activate([view.leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: inset),
            view.trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -inset),
            view.topAnchor.constraint(equalTo: parent.topAnchor, constant: inset), view.bottomAnchor.constraint(equalTo: parent.bottomAnchor, constant: -inset)])
    }
    private func fullWidth(_ child: NSView, in parent: NSView) { child.widthAnchor.constraint(equalTo: parent.widthAnchor).isActive = true }
    private func card(_ body: NSView, inset: CGFloat = 18) -> NSView {
        let box = DesignSurface(); pin(body, to: box, inset: inset); return box
    }
    private func separator() -> NSView {
        let line = DesignSurface(); line.fill = DesignTokens.line; line.outlined = false; line.radius = 0
        line.heightAnchor.constraint(equalToConstant: 1).isActive = true; return line
    }
    private func build() {
        guard let windowContent = window?.contentView else { return }
        windowContent.setAccessibilityElement(true)
        windowContent.setAccessibilityRole(.group)
        windowContent.setAccessibilityLabel("SmoothWheel settings")
        let paper = DesignSurface(); paper.fill = DesignTokens.paper; paper.radius = 0; paper.outlined = false
        pin(paper, to: windowContent)
        pin(settingsScene, to: windowContent)
        pin(settingsBody, to: settingsScene)
        let root = settingsBody
        if let url = resourceURL("heading-aura") { aura.image = NSImage(contentsOf: url) }
        aura.setContentCompressionResistancePriority(.init(1), for: .horizontal)
        aura.setContentCompressionResistancePriority(.init(1), for: .vertical)
        aura.setContentHuggingPriority(.init(1), for: .horizontal)
        aura.setContentHuggingPriority(.init(1), for: .vertical)
        aura.imageScaling = .scaleAxesIndependently; aura.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(aura)
        NSLayoutConstraint.activate([aura.leadingAnchor.constraint(equalTo: root.leadingAnchor), aura.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            aura.topAnchor.constraint(equalTo: root.topAnchor, constant: 112), aura.heightAnchor.constraint(equalToConstant: 122)])
        let mark = NSImageView()
        if let url = resourceURL("brand-mark") { mark.image = NSImage(contentsOf: url) }
        mark.imageScaling = .scaleProportionallyUpOrDown
        mark.widthAnchor.constraint(equalToConstant: 44).isActive = true; mark.heightAnchor.constraint(equalToConstant: 28).isActive = true
        let brand = stack([mark, text("SmoothWheel", size: 25, weight: .bold)], spacing: 8, horizontal: true)
        brand.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(brand)
        NSLayoutConstraint.activate([brand.centerXAnchor.constraint(equalTo: root.centerXAnchor), brand.topAnchor.constraint(equalTo: root.topAnchor, constant: 27)])
        navigation.target = self; navigation.action = #selector(navigate)
        navigation.setAccessibilityElement(true)
        navigation.setAccessibilityRole(.group)
        navigation.setAccessibilityLabel("Settings sections")
        navigation.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(navigation)
        NSLayoutConstraint.activate([navigation.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            navigation.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24), navigation.topAnchor.constraint(equalTo: root.topAnchor, constant: 76),
            navigation.heightAnchor.constraint(equalToConstant: 42)])
        content.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(content)
        NSLayoutConstraint.activate([content.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18), content.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -18),
            content.topAnchor.constraint(equalTo: root.topAnchor, constant: 148), content.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -10)])
        pages = [scrollingPage(), exclusionsPage(), playgroundPage()]
        for page in pages {
            pin(page, to: content)
            page.isHidden = true
            page.isInteractive = false
        }
        select(0)
    }
    private func page(_ views: [NSView], spacing: CGFloat = DesignTokens.Space.md) -> SettingsSurface {
        let body = stack(views, spacing: spacing)
        for view in views { fullWidth(view, in: body) }
        let wrapper = SettingsSurface(); body.translatesAutoresizingMaskIntoConstraints = false; wrapper.addSubview(body)
        wrapper.setAccessibilityElement(true)
        wrapper.setAccessibilityRole(.group)
        NSLayoutConstraint.activate([body.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor), body.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
            body.topAnchor.constraint(equalTo: wrapper.topAnchor)])
        return wrapper
    }
    private func sliderRow(_ label: String, slider: NSSlider, value: NSTextField) -> NSView {
        let title = text(label, size: 16, weight: .medium)
        title.widthAnchor.constraint(equalToConstant: 122).isActive = true
        value.font = .monospacedDigitSystemFont(ofSize: 15, weight: .medium); value.textColor = DesignTokens.text
        value.alignment = .right; value.widthAnchor.constraint(equalToConstant: 48).isActive = true
        slider.heightAnchor.constraint(equalToConstant: DesignTokens.Control.sliderHeight).isActive = true
        return stack([title, slider, value], spacing: 10, horizontal: true)
    }
    private func permissionRow() -> NSView {
        permissionTitle.font = .systemFont(ofSize: 14, weight: .semibold); permissionTitle.textColor = DesignTokens.text
        permissionDetail.font = .systemFont(ofSize: 12); permissionDetail.textColor = DesignTokens.textMuted
        let symbol = NSImageView(image: NSImage(systemSymbolName: "figure.arms.open", accessibilityDescription: nil)!)
        symbol.symbolConfiguration = .init(pointSize: 25, weight: .regular); symbol.contentTintColor = DesignTokens.text
        let disc = DesignSurface(); disc.fill = DesignTokens.accentWash; disc.radius = 23; disc.outlined = false
        pin(symbol, to: disc, inset: 10)
        disc.widthAnchor.constraint(equalToConstant: 46).isActive = true; disc.heightAnchor.constraint(equalToConstant: 46).isActive = true
        permissionButton = DesignButton("Open Settings", target: coordinator, action: #selector(AppDelegate.openPermissions))
        permissionButton.widthAnchor.constraint(equalToConstant: 124).isActive = true
        let labels = stack([permissionTitle, permissionDetail], spacing: 3)
        labels.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return card(stack([disc, labels, NSView(), permissionButton], spacing: 12, horizontal: true), inset: 12)
    }
    private func scrollingPage() -> SettingsSurface {
        activeSwitch = DesignSwitch(label: "Enable smooth scrolling", target: coordinator, action: #selector(AppDelegate.toggle))
        reverse = DesignSwitch(label: "Reverse mouse scroll direction", target: self, action: #selector(changeSettings))
        let enable = stack([text("Enable smoothing", size: 20, weight: .medium), NSView(), activeSwitch], horizontal: true)
        let enableCard = card(enable)
        enableCard.heightAnchor.constraint(equalToConstant: 66).isActive = true
        for slider in [speed, smooth] { slider.cell = DesignSliderCell(); slider.target = self; slider.action = #selector(changeSettings); slider.isContinuous = true }
        speed.minValue = 0.3; speed.maxValue = 3; speed.doubleValue = coordinator.engine.speed; speed.setAccessibilityLabel("Scroll speed")
        smooth.minValue = 0; smooth.maxValue = 1; smooth.doubleValue = coordinator.engine.smoothing; smooth.setAccessibilityLabel("Smoothing amount")
        presetButton.target = self; presetButton.action = #selector(showPresetLibrary)
        presetButton.setAccessibilityLabel("Choose a scrolling preset")
        presetButton.widthAnchor.constraint(lessThanOrEqualToConstant: 220).isActive = true
        presetButton.setContentHuggingPriority(.required, for: .horizontal)
        presetButton.heightAnchor.constraint(equalToConstant: 40).isActive = true
        let presetRow = stack([text("Preset", size: 16, weight: .medium), NSView(), presetButton], horizontal: true)
        let reverseRow = stack([text("Reverse direction", size: 16, weight: .medium), NSView(), reverse], horizontal: true)
        let controls = stack([presetRow, sliderRow("Scroll speed", slider: speed, value: speedValue),
            sliderRow("Smoothing", slider: smooth, value: smoothValue), separator(), reverseRow], spacing: 19)
        for view in controls.arrangedSubviews { fullWidth(view, in: controls) }
        let permission = permissionRow()
        let heading = text("Find your flow.", size: DesignTokens.Font.title, weight: .bold)
        let hint = text("Hold Option to bypass smoothing.", size: 11, secondary: true)
        return page([heading, enableCard, card(controls), permission, hint])
    }
    private func exclusionsPage() -> SettingsSurface {
        exclusionList.orientation = .vertical; exclusionList.alignment = .leading; exclusionList.spacing = 14
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        exclusionScroll = scroll
        scroll.drawsBackground = false; scroll.heightAnchor.constraint(equalToConstant: 280).isActive = true
        let document = TopAlignedDocumentView(); document.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = document; exclusionList.translatesAutoresizingMaskIntoConstraints = false; document.addSubview(exclusionList)
        NSLayoutConstraint.activate([document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            exclusionList.topAnchor.constraint(equalTo: document.topAnchor), exclusionList.bottomAnchor.constraint(equalTo: document.bottomAnchor),
            exclusionList.leadingAnchor.constraint(equalTo: document.leadingAnchor), exclusionList.trailingAnchor.constraint(equalTo: document.trailingAnchor)])
        let add = DesignButton("Add an application…", target: self, action: #selector(addExclusion)); add.primary = true
        return page([text("Make exceptions.", size: 32, weight: .bold), text("Keep games, remote desktops, or any app you prefer unchanged.", secondary: true),
            card(scroll), add])
    }
    private func playgroundPage() -> SettingsSurface {
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        scroll.drawsBackground = false; scroll.heightAnchor.constraint(equalToConstant: 340).isActive = true
        let copy = NSMutableAttributedString()
        let prompts = ["One small turn.", "A little more momentum.", "Change direction.", "Compare the original feel."]
        let descriptions = ["Try one notch. A small movement should stay controlled.", "Turn the wheel several times. Find a steady rhythm.", "Scroll down, then up. The old direction should stop promptly.", "Hold Option while scrolling to bypass SmoothWheel."]
        for index in 0..<18 {
            let title = NSMutableParagraphStyle(); title.paragraphSpacing = 12
            let body = NSMutableParagraphStyle(); body.lineSpacing = 5; body.paragraphSpacing = 36
            copy.append(NSAttributedString(string: String(format: "%02d", index + 1) + "   " + prompts[index % 4] + "\n", attributes: [
                .font: NSFont.systemFont(ofSize: 21, weight: .semibold), .foregroundColor: DesignTokens.text, .paragraphStyle: title]))
            copy.append(NSAttributedString(string: descriptions[index % 4] + "\n", attributes: [
                .font: NSFont.systemFont(ofSize: 15), .foregroundColor: DesignTokens.textMuted, .paragraphStyle: body]))
        }
        let document = NSTextView(frame: NSRect(x: 0, y: 0, width: 480, height: 3000))
        document.textStorage?.setAttributedString(copy); document.isEditable = false; document.isSelectable = true
        document.drawsBackground = false; document.textContainerInset = NSSize(width: 12, height: 12)
        document.isVerticallyResizable = true; document.isHorizontallyResizable = false
        document.autoresizingMask = [.width]; document.textContainer?.widthTracksTextView = true
        scroll.documentView = document
        return page([text("Get into the flow.", size: 32, weight: .bold), text("Enable smoothing, then use this space to find your feel.", secondary: true),
            card(scroll), text("Option = original scrolling. Reverse direction to cancel the old movement.", size: 12, secondary: true)])
    }
    @objc private func navigate() {
        guard !(presetPresentation?.view is DesignAlertPanel) else {
            navigation.selectedIndex = 0
            return
        }
        select(navigation.selectedIndex)
    }
    func select(_ index: Int) {
        guard pages.indices.contains(index) else { return }
        let previous = selectedPage.map { pages[$0] }
        let next = pages[index]
        let manager = managerScene
        let changing = manager != nil || previous !== next
        dismissPresetPresentation(animated: !changing)
        let sceneOpacity = manager == nil ? nil : restoreSettingsScene()
        navigation.selectedIndex = index
        selectedPage = index
        if changing {
            let opacity = motion.activate(next)
            var crossfade = false
            if let previous, previous !== next {
                releaseFocus(in: previous)
                if manager == nil {
                    crossfade = motion.retire(previous) { previous.isHidden = true }
                } else {
                    previous.isInteractive = false
                    previous.isHidden = true
                }
            }
            if let manager {
                releaseFocus(in: manager)
                motion.retire(manager) { manager.removeFromSuperview() }
            } else if crossfade || opacity != nil {
                motion.fadeIn(next, from: opacity)
            }
            if let sceneOpacity { motion.fadeIn(settingsScene, from: sceneOpacity) }
        }
        if index == 1 { reloadExclusions(animated: false) }
        updateAccessibility()
    }
    func refresh() {
        let trusted = permissionGranted()
        let animateSwitches = motion.allowsMotion(in: activeSwitch) && !activeSwitch.isHiddenOrHasHiddenAncestor
        activeSwitch.setConfirmedState(coordinator.engine.enabled ? .on : .off, animated: animateSwitches)
        reverse.setConfirmedState(coordinator.engine.reversed ? .on : .off, animated: animateSwitches)
        permissionTitle.stringValue = trusted ? "Accessibility is ready" : "Accessibility setup"
        permissionDetail.stringValue = trusted ? "SmoothWheel can control scrolling." : "Allow SmoothWheel to control scrolling."
        speedValue.stringValue = String(format: "%.1f×", coordinator.engine.speed)
        smoothValue.stringValue = String(format: "%.0f%%", coordinator.engine.smoothing * 100)
        presetButton.title = coordinator.presetTitle
        presetButton.invalidateIntrinsicContentSize()
        presetButton.toolTip = coordinator.presetTitle
        presetButton.setAccessibilityValue(coordinator.presetTitle)
        let dark = window?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        aura.isHidden = dark || !allowsDecorativeBackground()
    }
    func synchronizeControls() {
        speed.doubleValue = coordinator.engine.speed; smooth.doubleValue = coordinator.engine.smoothing
        refresh()
    }
    @objc private func changeSettings() {
        coordinator.engine.speed = speed.doubleValue; coordinator.engine.smoothing = smooth.doubleValue
        coordinator.engine.reversed = reverse.state == .on; coordinator.saveSettings()
    }
    @objc func showPresetLibrary() {
        let previous = managerScene
        if previous != nil { dismissPresetPresentation(animated: false) }
        let opacity = previous == nil ? nil : restoreSettingsScene()
        let library = makePresetLibrary()
        presentPreset(library, animate: previous == nil)
        library.focusSelection()
        if let previous { motion.retire(previous) { previous.removeFromSuperview() } }
        if let opacity { motion.fadeIn(settingsScene, from: opacity) }
    }

    private func makePresetLibrary() -> PresetLibraryController {
        let library = PresetLibraryController(coordinator: coordinator)
        library.onClose = { [weak self] in self?.dismissPresetPresentation() }
        library.onSave = { [weak self] in self?.showPresetName() }
        library.onManage = { [weak self] in self?.showPresetManager() }
        library.onReset = { [weak self] in self?.confirmPresetReset() }
        library.onError = { [weak self] error in self?.showPresetError(error) }
        return library
    }
    func showPresetManager(selecting id: UUID? = nil) {
        guard let root = window?.contentView else { return }
        let previous = managerScene ?? settingsScene
        let overlay = releasePresetPresentation()
        releaseFocus(in: previous)
        let store = coordinator.presetStore
        let manager = PresetManagerController(presets: store.presets, activeID: store.activeID, selectedID: id)
        manager.onBack = { [weak self] in self?.showPresetLibrary() }
        manager.onRename = { [weak self] id in self?.showPresetName(renaming: id) }
        manager.onDelete = { [weak self] id in self?.confirmPresetDeletion(id) }
        let scene = SettingsSurface()
        pin(scene, to: root)
        manager.view.nextResponder = manager
        pin(manager.view, to: scene, inset: 18)
        managerScene = scene
        presetManager = manager
        updateAccessibility()
        manager.focusSelection()
        let fading = motion.retire(previous) { [settingsScene] in
            overlay?.removeFromSuperview()
            if previous === settingsScene { previous.isHidden = true }
            else { previous.removeFromSuperview() }
        }
        if fading { motion.fadeIn(scene) }
    }

    private func restoreSettingsScene() -> Float? {
        managerScene = nil
        presetManager = nil
        let opacity = motion.activate(settingsScene)
        for case let overlay as PresetOverlay in settingsScene.subviews { overlay.removeFromSuperview() }
        refresh()
        return opacity
    }

    private func releaseFocus(in surface: NSView) {
        if let first = window?.firstResponder as? NSView, first.isDescendant(of: surface) {
            window?.makeFirstResponder(nil)
        }
    }

    func showPresetName(renaming id: UUID? = nil) {
        let library = presetPresentation as? PresetLibraryController
        let store = coordinator.presetStore
        let name = store.presets.first { $0.id == id }?.name ?? ""
        let captured = coordinator.configuration
        var created: SavedScrollPreset?
        let editor = PresetNameController(renaming: id != nil, name: name, validate: { try store.validateName($0, excluding: id) }, save: { value in
            if let id { try store.rename(id, to: value) }
            else { created = try store.save(name: value, configuration: captured) }
        })
        editor.onClose = { [weak self, weak editor] saved in
            guard let self, let editor, self.presetPresentation === editor else { return }
            if saved {
                self.synchronizeControls()
                if let manager = self.presetManager, let id, let renamed = store.presets.first(where: { $0.id == id }) {
                    self.dismissPresetPresentation()
                    manager.updateName(renamed)
                } else if library != nil, let created {
                    let updated = self.makePresetLibrary()
                    self.presentPreset(updated)
                    if let row = updated.revealSavedPreset(created.id) {
                        self.motion.fadeIn(row, duration: DesignTokens.Motion.normal)
                    }
                } else {
                    self.dismissPresetPresentation()
                }
            } else if let library {
                self.presentPreset(library)
                library.focusSave()
            } else {
                self.dismissPresetPresentation(restoring: self.presetManager?.rename)
            }
        }
        presentPreset(editor)
        window?.makeFirstResponder(editor.nameField)
    }
    func dismissPresetPresentation(restoring focus: NSView? = nil, animated: Bool = true) {
        guard let overlay = releasePresetPresentation() else { return }
        presetButton.clearPointerHover()
        presetManager?.setPanelPresented(false)
        updateAccessibility()
        if let focus {
            window?.makeFirstResponder(focus)
        } else if let presetManager {
            presetManager.focusSelection()
        } else {
            window?.makeFirstResponder(presetButton)
        }
        motion.retire(overlay, animated: animated) { overlay.removeFromSuperview() }
    }

    private func releasePresetPresentation() -> PresetOverlay? {
        guard let overlay = presetOverlay else { return nil }
        releaseFocus(in: overlay)
        overlay.isInteractive = false
        overlay.onClose = nil
        if overlay.superview === settingsScene { settingsBody.isInteractive = true }
        presetOverlay = nil
        presetPanel = nil
        presetPresentation = nil
        return overlay
    }

    private func presentPreset(_ controller: NSViewController, animate: Bool = true) {
        let scene = managerScene ?? settingsScene
        // Freshly mounted scenes may not have their initial geometry yet.
        if scene.bounds.isEmpty { scene.superview?.layoutSubtreeIfNeeded() }
        presetButton.clearPointerHover()
        let previous = presetPanel
        let previousCard = presetPresentation?.view as? PresetCard
        let previousFrame = presetPresentation?.view.frame
        if let previous { releaseFocus(in: previous) }
        let retiringOverlay = motion.departingView() as? PresetOverlay
        let reuseOverlay = retiringOverlay?.superview === scene ? retiringOverlay : nil
        let overlay = presetOverlay ?? reuseOverlay ?? PresetOverlay(frame: scene.bounds)
        let overlayOpacity = reuseOverlay.map { motion.activate($0) } ?? nil
        if reuseOverlay != nil { overlay.subviews.forEach { $0.removeFromSuperview() } }
        let panel = controller.view
        (panel as? PresetCard)?.contentView.isHidden = false
        let wrapper = (panel.superview as? SettingsSurface) ?? SettingsSurface(frame: scene.bounds)
        let panelOpacity = motion.activate(wrapper)
        wrapper.autoresizingMask = [.width, .height]
        overlay.dimOpacity = controller is PresetDeleteController ? 0.12 : 0.06
        overlay.autoresizingMask = [.width, .height]
        overlay.onClose = { [weak controller] in controller?.cancelOperation(nil) }
        overlay.panel = panel
        panel.nextResponder = controller
        panel.frame.origin = NSPoint(x: (scene.bounds.width - panel.frame.width) / 2,
                                     y: (scene.bounds.height - panel.frame.height) / 2 - 32)
        panel.wantsLayer = true
        panel.layer?.shadowColor = NSColor.black.cgColor; panel.layer?.shadowOpacity = 0.12
        panel.layer?.shadowRadius = 16; panel.layer?.shadowOffset = CGSize(width: 0, height: -4)
        if panel.superview !== wrapper { wrapper.addSubview(panel) }
        if wrapper.superview !== overlay { overlay.addSubview(wrapper) }
        if overlay.superview !== scene { scene.addSubview(overlay) }
        presetOverlay = overlay
        presetPanel = wrapper
        presetPresentation = controller
        if scene === settingsScene { settingsBody.isInteractive = false }
        presetManager?.setPanelPresented(true)
        updateAccessibility()
        if let previous, previous !== wrapper, let previousFrame {
            // Only the outgoing card's background participates in a panel replacement.
            previousCard?.contentView.isHidden = true
            motion.swapPanels(previous, with: wrapper, in: overlay,
                              incomingCoversPrevious: panel.frame.contains(previousFrame),
                              incomingOpacity: panelOpacity, animated: animate)
        } else if previous == nil, animate {
            motion.fadeIn(overlay, from: overlayOpacity)
        }
    }

    private func updateAccessibility() {
        guard let root = window?.contentView else { return }
        if let panel = presetPresentation?.view {
            root.setAccessibilityChildren([panel])
        } else if let manager = presetManager {
            root.setAccessibilityChildren([manager.view])
        } else {
            root.setAccessibilityChildren([navigation] + (selectedPage.map { [pages[$0]] } ?? []))
        }
    }
    private func confirmPresetDeletion(_ id: UUID) {
        guard let window, window.attachedSheet == nil, presetPresentation == nil,
              presetManager != nil,
              let preset = coordinator.presetStore.presets.first(where: { $0.id == id }) else { return }
        let confirmation = PresetDeleteController(name: preset.name)
        confirmation.onCancel = { [weak self, weak confirmation] in
            guard let self, let confirmation, self.presetPresentation === confirmation else { return }
            self.dismissPresetPresentation(restoring: self.presetManager?.delete)
        }
        confirmation.onDelete = { [weak self, weak confirmation] in
            guard let self, let confirmation, self.presetPresentation === confirmation else { return }
            do {
                try self.coordinator.presetStore.delete(id)
                self.synchronizeControls()
                if let manager = self.presetManager, manager.rows.count > 1 {
                    self.dismissPresetPresentation(restoring: manager.delete)
                    if !manager.removePreset(id, motion: self.motion) { self.showPresetManager() }
                } else {
                    self.showPresetManager()
                }
            } catch {
                self.showPresetError(error)
            }
        }
        presentPreset(confirmation)
        window.makeFirstResponder(confirmation.cancel)
    }
    private func confirmPresetReset() {
        guard let window else { return }
        dismissPresetPresentation()
        let alert = NSAlert(); alert.messageText = "Reset saved presets?"
        alert.informativeText = "This removes the unreadable saved collection. Your current scrolling settings and exclusions stay unchanged."
        alert.addButton(withTitle: "Reset saved presets"); alert.addButton(withTitle: "Cancel")
        alert.buttons[0].hasDestructiveAction = true
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            if response == .alertFirstButtonReturn {
                do { try self.coordinator.presetStore.resetCollection(); self.synchronizeControls() }
                catch { self.showPresetError(error); return }
            }
            self.showPresetLibrary()
        }
    }
    func showPresetError(_ error: Error) {
        guard let window else { return }
        dismissPresetPresentation()
        let alert = NSAlert(); alert.messageText = "Couldn’t change presets"
        alert.informativeText = error.localizedDescription; alert.addButton(withTitle: "OK")
        alert.beginSheetModal(for: window)
    }
    @objc private func addExclusion() {
        let panel = NSOpenPanel(); panel.title = "Choose an app to exclude"; panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications"); panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        guard let window else { return }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let url = panel.url,
                  let id = Bundle(url: url)?.bundleIdentifier else { return }
            self.coordinator.engine.excluded.insert(id)
            self.coordinator.saveSettings()
            self.reloadExclusions()
        }
    }
    func reloadExclusions(animated: Bool = true) {
        let ids = coordinator.engine.excluded.sorted()
        let shouldAnimate = animated && motion.allowsMotion(in: exclusionList)
        let removed = Set(exclusionRows.keys).subtracting(ids)
        let added = ids.filter { exclusionRows[$0] == nil }
        guard !removed.isEmpty || !added.isEmpty || (ids.isEmpty && exclusionPlaceholder.isEmpty) else { return }
        let survivors = ids.compactMap { exclusionRows[$0] }
        let hasVisibleList = exclusionList.window?.isVisible == true && !exclusionList.isHiddenOrHasHiddenAncestor
        let anchor = hasVisibleList ? SettingsListAnchor(in: exclusionScroll, rows: survivors) : nil
        let oldViewport = exclusionList.convert(exclusionScroll.contentView.bounds, from: exclusionScroll.contentView)
        let oldPositions = survivors.map { $0.frame.minY }
        let departingID = shouldAnimate ? removed.sorted().first { id in
            exclusionRows[id].map { oldViewport.intersects($0.frame) } ?? false
        } : nil
        for id in removed {
            if let row = exclusionRows.removeValue(forKey: id) {
                exclusionList.removeArrangedSubview(row)
                if id == departingID { motion.retireRow(row, in: exclusionScroll) }
                else { row.removeFromSuperview() }
            }
        }
        if !ids.isEmpty {
            for view in exclusionPlaceholder {
                exclusionList.removeArrangedSubview(view)
                view.removeFromSuperview()
            }
            exclusionPlaceholder.removeAll()
        } else if exclusionPlaceholder.isEmpty {
            exclusionPlaceholder = [text("No exceptions yet.", weight: .semibold),
                text("Smoothing is available in every app unless you add it here.", size: 13, secondary: true)]
            for view in exclusionPlaceholder { exclusionList.addArrangedSubview(view) }
        }
        for (index, id) in ids.enumerated() where exclusionRows[id] == nil {
            let name = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)?.deletingPathExtension().lastPathComponent ?? id
            let remove = DesignButton("Remove", target: self, action: #selector(removeExclusion(_:)))
            remove.identifier = NSUserInterfaceItemIdentifier(id); remove.setAccessibilityLabel("Remove \(name) from exclusions")
            let labels = stack([text(name, weight: .semibold), text(id, size: 11, secondary: true)], spacing: 4)
            let line = stack([labels, NSView(), remove], spacing: 10, horizontal: true)
            exclusionList.insertArrangedSubview(line, at: index)
            exclusionRows[id] = line
            fullWidth(line, in: exclusionList)
        }
        guard hasVisibleList, let root = window?.contentView else { return }
        root.layoutSubtreeIfNeeded()
        anchor?.restore(in: exclusionScroll)
        guard shouldAnimate else { return }
        let viewport = exclusionList.convert(exclusionScroll.contentView.bounds, from: exclusionScroll.contentView)
        for (row, oldY) in zip(survivors, oldPositions) where viewport.intersects(row.frame) {
            motion.settle(row, verticalOffset: oldY - oldViewport.minY - (row.frame.minY - viewport.minY))
        }
        for id in added {
            if let row = exclusionRows[id], viewport.intersects(row.frame) {
                motion.fadeIn(row)
            }
        }
    }
    @objc private func removeExclusion(_ sender: NSButton) {
        guard sender.acceptsSettingsInput, let id = sender.identifier?.rawValue,
              let row = exclusionRows[id], sender.isDescendant(of: row) else { return }
        coordinator.engine.excluded.remove(id); coordinator.saveSettings(); reloadExclusions()
    }
}
