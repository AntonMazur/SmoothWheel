import AppKit
import ScrollCore
import ApplicationServices
import UniformTypeIdentifiers

final class SettingsWindowController: NSWindowController {
    private unowned let coordinator: AppDelegate
    private let content = NSView()
    private var pages: [NSView] = []
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
    private let presets = PresetControl(labels: ScrollPreset.allCases.map(\.rawValue))
    private var exclusionList = NSStackView()
    private let aura = NSImageView()

    private let permissionGranted: () -> Bool
    private let resourceURL: (String) -> URL?
    private let allowsDecorativeBackground: () -> Bool
    init(coordinator: AppDelegate, permissionGranted: @escaping () -> Bool = { AXIsProcessTrusted() },
         resourceURL: @escaping (String) -> URL? = { Bundle.main.url(forResource: $0, withExtension: "png") },
         allowsDecorativeBackground: @escaping () -> Bool = {
             !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency && !NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
         }) {
        self.permissionGranted = permissionGranted
        self.resourceURL = resourceURL
        self.allowsDecorativeBackground = allowsDecorativeBackground
        self.coordinator = coordinator
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 660),
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
        build()
        window.setContentSize(NSSize(width: 560, height: 660))
    }
    required init?(coder: NSCoder) { fatalError("Use init(coordinator:)") }

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
        guard let root = window?.contentView else { return }
        let paper = DesignSurface(); paper.fill = DesignTokens.paper; paper.radius = 0; paper.outlined = false
        pin(paper, to: root)
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
        navigation.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(navigation)
        NSLayoutConstraint.activate([navigation.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            navigation.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24), navigation.topAnchor.constraint(equalTo: root.topAnchor, constant: 76),
            navigation.heightAnchor.constraint(equalToConstant: 42)])
        content.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(content)
        NSLayoutConstraint.activate([content.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18), content.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -18),
            content.topAnchor.constraint(equalTo: root.topAnchor, constant: 148), content.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -10)])
        pages = [scrollingPage(), exclusionsPage(), playgroundPage()]
        for page in pages { pin(page, to: content); page.isHidden = true }
        select(0)
    }
    private func page(_ views: [NSView], spacing: CGFloat = DesignTokens.Space.md) -> NSView {
        let body = stack(views, spacing: spacing)
        for view in views { fullWidth(view, in: body) }
        let wrapper = NSView(); body.translatesAutoresizingMaskIntoConstraints = false; wrapper.addSubview(body)
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
    private func scrollingPage() -> NSView {
        activeSwitch = DesignSwitch(label: "Enable smooth scrolling", target: coordinator, action: #selector(AppDelegate.toggle))
        reverse = DesignSwitch(label: "Reverse mouse scroll direction", target: self, action: #selector(changeSettings))
        let enable = stack([text("Enable smoothing", size: 20, weight: .medium), NSView(), activeSwitch], horizontal: true)
        let enableCard = card(enable)
        enableCard.heightAnchor.constraint(equalToConstant: 66).isActive = true
        for slider in [speed, smooth] { slider.cell = DesignSliderCell(); slider.target = self; slider.action = #selector(changeSettings); slider.isContinuous = true }
        speed.minValue = 0.3; speed.maxValue = 3; speed.doubleValue = coordinator.engine.speed; speed.setAccessibilityLabel("Scroll speed")
        smooth.minValue = 0; smooth.maxValue = 1; smooth.doubleValue = coordinator.engine.smoothing; smooth.setAccessibilityLabel("Smoothing amount")
        presets.target = self; presets.action = #selector(applyPreset); presets.heightAnchor.constraint(equalToConstant: 40).isActive = true
        let reverseRow = stack([text("Reverse direction", size: 16, weight: .medium), NSView(), reverse], horizontal: true)
        let controls = stack([presets, sliderRow("Scroll speed", slider: speed, value: speedValue),
            sliderRow("Smoothing", slider: smooth, value: smoothValue), separator(), reverseRow], spacing: 19)
        for view in controls.arrangedSubviews { fullWidth(view, in: controls) }
        let permission = permissionRow()
        let heading = text("Find your flow.", size: DesignTokens.Font.title, weight: .bold)
        let hint = text("Hold Option to bypass smoothing.", size: 11, secondary: true)
        return page([heading, enableCard, card(controls), permission, hint])
    }
    private func exclusionsPage() -> NSView {
        exclusionList.orientation = .vertical; exclusionList.alignment = .leading; exclusionList.spacing = 14
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
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
    private func playgroundPage() -> NSView {
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
    @objc private func navigate() { select(navigation.selectedIndex) }
    func select(_ index: Int) {
        guard pages.indices.contains(index) else { return }
        navigation.selectedIndex = index
        if let window {
            let top = window.frame.maxY
            window.setContentSize(NSSize(width: 560, height: index == 1 ? 620 : 660))
            var frame = window.frame
            frame.origin.y = top - frame.height
            window.setFrame(frame, display: true)
        }
        for (i, page) in pages.enumerated() { page.isHidden = i != index }
        if index == 1 { reloadExclusions() }
    }
    func refresh() {
        let trusted = permissionGranted()
        activeSwitch.state = coordinator.engine.enabled ? .on : .off
        reverse.state = coordinator.engine.reversed ? .on : .off
        permissionTitle.stringValue = trusted ? "Accessibility is ready" : "Accessibility setup"
        permissionDetail.stringValue = trusted ? "SmoothWheel can control scrolling." : "Allow SmoothWheel to control scrolling."
        speedValue.stringValue = String(format: "%.1f×", coordinator.engine.speed)
        smoothValue.stringValue = String(format: "%.0f%%", coordinator.engine.smoothing * 100)
        let selectedPreset = ScrollPreset.matching(speed: coordinator.engine.speed, smoothing: coordinator.engine.smoothing)
        presets.selectedIndex = selectedPreset.flatMap { ScrollPreset.allCases.firstIndex(of: $0) } ?? -1
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
    @objc private func applyPreset() {
        let values = ScrollPreset.allCases
        guard values.indices.contains(presets.selectedIndex) else { return }
        let value = values[presets.selectedIndex]
        speed.doubleValue = value.speed
        smooth.doubleValue = value.smoothing
        changeSettings()
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
    func reloadExclusions() {
        for view in exclusionList.arrangedSubviews { exclusionList.removeArrangedSubview(view); view.removeFromSuperview() }
        if coordinator.engine.excluded.isEmpty {
            exclusionList.addArrangedSubview(text("No exceptions yet.", weight: .semibold))
            exclusionList.addArrangedSubview(text("Smoothing is available in every app unless you add it here.", size: 13, secondary: true))
        }
        for id in coordinator.engine.excluded.sorted() {
            let name = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)?.deletingPathExtension().lastPathComponent ?? id
            let remove = DesignButton("Remove", target: self, action: #selector(removeExclusion(_:)))
            remove.identifier = NSUserInterfaceItemIdentifier(id); remove.setAccessibilityLabel("Remove \(name) from exclusions")
            let labels = stack([text(name, weight: .semibold), text(id, size: 11, secondary: true)], spacing: 4)
            let line = stack([labels, NSView(), remove], spacing: 10, horizontal: true)
            exclusionList.addArrangedSubview(line); fullWidth(line, in: exclusionList)
        }
    }
    @objc private func removeExclusion(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        coordinator.engine.excluded.remove(id); coordinator.saveSettings(); reloadExclusions()
    }
}
