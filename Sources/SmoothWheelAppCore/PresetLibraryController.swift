import AppKit
import ScrollCore

final class PresetCanvas: NSView {
    override var isFlipped: Bool { true }
}

/// Preset names share a leading edge and a trailing column for the selection checkmark.
final class PresetRowButton: PresetFocusButton {
    static let rowHeight: CGFloat = 28
    private(set) var checked: Bool
    private let nameLabel: NSTextField
    private let checkmark = NSImageView()
    private let inUse: Bool
    private let markWidth = DesignTokens.Space.md
    var onArrow: ((Int) -> Void)?
    var onCancel: (() -> Void)?
    init(_ name: String, checked: Bool, inUse: Bool = false, target: AnyObject, action: Selector) {
        self.checked = checked
        self.inUse = inUse
        nameLabel = NSTextField(labelWithString: name)
        super.init(name, target: target, action: action)
        nameLabel.font = .systemFont(ofSize: DesignTokens.Font.body)
        nameLabel.textColor = DesignTokens.text
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.setAccessibilityElement(false)
        addSubview(nameLabel)
        checkmark.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)
        checkmark.symbolConfiguration = .init(pointSize: 13, weight: .medium)
        checkmark.contentTintColor = DesignTokens.text
        checkmark.setAccessibilityElement(false)
        addSubview(checkmark)
        setAccessibilityRole(.radioButton)
        updateName(name)
        setChecked(checked)
    }

    required init?(coder: NSCoder) { fatalError("Use init(name:checked:inUse:target:action:)") }

    func updateName(_ name: String) {
        title = name
        nameLabel.stringValue = name
        setAccessibilityLabel(inUse ? "\(name), in use" : name)
        toolTip = name
    }

    func setChecked(_ checked: Bool) {
        self.checked = checked
        state = checked ? .on : .off
        setAccessibilityValue(checked ? 1 : 0)
        checkmark.isHidden = !checked
    }

    override func layout() {
        super.layout()
        nameLabel.frame = nameFrame
        checkmark.frame = NSRect(x: bounds.maxX - 12 - markWidth, y: bounds.midY - markWidth / 2,
                                 width: markWidth, height: markWidth)
    }
    override func draw(_ dirtyRect: NSRect) {
        drawKeyboardFocus()
    }
    var nameFrame: NSRect {
        let height = nameLabel.intrinsicContentSize.height
        let trailing = 24 + markWidth + DesignTokens.Space.sm
        return NSRect(x: 12, y: (bounds.height - height) / 2, width: max(0, bounds.width - trailing), height: height)
    }
    override var keyboardFocusColor: NSColor { DesignTokens.textMuted }
    override var keyboardFocusMarker: NSRect {
        let y = isFlipped ? bounds.maxY - 5 : 3
        return NSRect(x: nameFrame.minX, y: y, width: DesignTokens.Space.md, height: 2)
    }
    override func hitTest(_ point: NSPoint) -> NSView? { super.hitTest(point) == nil ? nil : self }
    override func keyDown(with event: NSEvent) {
        guard isEnabled else { return }
        if event.keyCode == 125 { onArrow?(1) }
        else if event.keyCode == 126 { onArrow?(-1) }
        else if event.keyCode == 36 || event.keyCode == 76 { performClick(nil) }
        else if event.keyCode == 53 { onCancel?() }
        else { super.keyDown(with: event) }
    }

}

enum PresetChoice: Equatable {
    case builtIn(ScrollPreset)
    case saved(UUID)
}

final class PresetLibraryController: NSViewController {
    private let coordinator: AppDelegate
    var onClose: (() -> Void)?
    var onSave: (() -> Void)?
    var onManage: (() -> Void)?
    var onReset: (() -> Void)?
    var onError: ((Error) -> Void)?
    private(set) var rows: [PresetRowButton] = []
    private var choices: [PresetChoice] = []
    private let document = PresetCanvas()
    private let scroll = NSScrollView()
    private let save = PresetFocusButton("Save")
    private let manage = PresetFocusButton("Manage presets")
    private let close = PresetFocusButton(circularIcon: "xmark", label: "Close presets",
                                          discDiameter: DesignTokens.Space.xl)
    var contentView: NSView { (view as! PresetCard).contentView }

    init(coordinator: AppDelegate) { self.coordinator = coordinator; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("Use init(coordinator:)") }
    override func loadView() {
        let root = PresetCard(frame: NSRect(x: 0, y: 0, width: 340, height: 396))
        root.setAccessibilityLabel("Presets")
        let headerMidY: CGFloat = 34
        let title = Self.label("Presets", size: 20, weight: .bold)
        title.maximumNumberOfLines = 1
        let titleHeight = ceil(title.intrinsicContentSize.height)
        title.frame = NSRect(x: DesignTokens.Space.lg, y: headerMidY - titleHeight / 2,
                             width: 220, height: titleHeight)
        root.contentView.addSubview(title)
        close.keyEquivalent = "\u{1b}"
        close.target = self
        close.action = #selector(closeLibrary)
        let size = close.intrinsicContentSize
        close.frame = NSRect(x: root.bounds.width - DesignTokens.Space.md - size.width,
                             y: headerMidY - size.height / 2, width: size.width, height: size.height)
        root.contentView.addSubview(close)
        scroll.drawsBackground = false; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        scroll.documentView = document; root.contentView.addSubview(scroll)
        save.target = self; save.action = #selector(saveCurrent)
        root.contentView.addSubview(save)
        manage.target = self; manage.action = #selector(openManager); root.contentView.addSubview(manage)
        view = root
        populate()
    }
    private func populate() {
        var y: CGFloat = 0
        var recoveryButton: PresetFocusButton?
        let showsEmptyMessage = coordinator.presetStore.presets.isEmpty && coordinator.presetStore.loadIssue == nil
        func heading(_ title: String) {
            let label = Self.label(title, size: 12, weight: .medium, secondary: true)
            label.frame = NSRect(x: 12, y: y, width: 220, height: 16); document.addSubview(label)
            y += 22
        }
        func row(_ name: String, choice: PresetChoice, checked: Bool) {
            let row = PresetRowButton(name, checked: checked, target: self, action: #selector(choose(_:)))
            row.tag = choices.count; choices.append(choice); rows.append(row)
            row.frame = NSRect(x: 0, y: y, width: 316, height: PresetRowButton.rowHeight)
            row.needsLayout = true
            row.onArrow = { [weak self, weak row] direction in
                guard let self, let row else { return }; self.focusRow(row.tag + direction)
            }
            row.onCancel = { [weak self] in self?.onClose?() }
            document.addSubview(row); y += PresetRowButton.rowHeight
        }
        heading("Built-in")
        for preset in ScrollPreset.allCases {
            row(preset.rawValue, choice: .builtIn(preset),
                checked: coordinator.presetStore.activeID == nil && ScrollPreset.matching(speed: coordinator.engine.speed, smoothing: coordinator.engine.smoothing) == preset)
        }
        y += 16
        heading("Saved")
        for preset in coordinator.presetStore.presets {
            row(preset.name, choice: .saved(preset.id), checked: coordinator.presetStore.activeID == preset.id)
        }
        if let issue = coordinator.presetStore.loadIssue {
            let message = Self.label(issue.localizedDescription, size: 12, secondary: true)
            message.frame = NSRect(x: 12, y: y, width: 288, height: 66); document.addSubview(message); y += 74
            let reset = PresetFocusButton("Reset saved presets…", target: self, action: #selector(resetPresets))
            reset.frame = NSRect(x: 12, y: y, width: 216, height: 36); document.addSubview(reset); y += 36
            recoveryButton = reset
        } else if showsEmptyMessage {
            let empty = Self.label("No saved presets yet.", size: 13, secondary: true)
            let lineHeight = ceil(empty.intrinsicContentSize.height)
            empty.frame = NSRect(x: 12, y: y, width: 288, height: lineHeight)
            document.addSubview(empty)
            y += lineHeight
        }
        document.frame = NSRect(x: 0, y: 0, width: 316, height: y)
        let height = min(y, 256)
        scroll.frame = NSRect(x: 12, y: 56, width: 316, height: height)
        scroll.hasVerticalScroller = y > height
        scroll.tile()
        document.frame.size.width = scroll.contentSize.width
        for row in rows {
            row.frame.size.width = document.bounds.width
            row.autoresizingMask = [.width]
        }
        document.autoresizingMask = [.width]
        // Match the visible title-to-section gap. Preset rows already pad their text.
        let saveSpacing = (showsEmptyMessage ? DesignTokens.Space.md : DesignTokens.Space.sm) + 2
        save.frame = NSRect(x: 24, y: scroll.frame.maxY + saveSpacing, width: 292, height: 34)
        save.isEnabled = coordinator.presetStore.loadIssue == nil && coordinator.presetStore.presets.count < SavedPresetStore.capacity
        save.toolTip = save.isEnabled ? "Save a named copy of the current scrolling feel" : (coordinator.presetStore.loadIssue?.localizedDescription ?? SavedPresetError.capacity.localizedDescription)
        manage.frame = NSRect(x: 24, y: save.frame.maxY + 8, width: 292, height: 34)
        manage.isHidden = coordinator.presetStore.presets.isEmpty
        manage.isEnabled = !manage.isHidden
        view.frame.size.height = (manage.isHidden ? save.frame.maxY : manage.frame.maxY) + 20
        var keyViews: [PresetFocusButton] = rows
        if let recoveryButton { keyViews.append(recoveryButton) }
        if save.isEnabled { keyViews.append(save) }
        if manage.isEnabled { keyViews.append(manage) }
        keyViews.append(close)
        PresetFocusButton.setKeyLoop(keyViews)
    }
    func focusRow(_ index: Int) {
        guard !rows.isEmpty else { return }
        let row = rows[(index + rows.count) % rows.count]
        row.scrollToVisible(row.bounds); view.window?.makeFirstResponder(row)
    }
    func focusSelection() {
        focusRow(rows.firstIndex(where: \.checked) ?? 0)
    }
    func focusSave() {
        view.window?.makeFirstResponder(save)
    }
    func revealSavedPreset(_ id: UUID) -> PresetRowButton? {
        guard let index = choices.firstIndex(of: .saved(id)) else { return nil }
        focusRow(index)
        return rows[index]
    }
    @objc private func choose(_ sender: PresetRowButton) {
        guard sender.acceptsSettingsInput else { return }
        let choice = choices[sender.tag]
        do {
            switch choice {
            case .builtIn(let preset): try coordinator.applyBuiltInPreset(preset)
            case .saved(let id): try coordinator.applySavedPreset(id)
            }
            onClose?()
        } catch { onError?(error) }
    }
    @objc private func openManager() { if manage.isEnabled, view.acceptsSettingsInput { onManage?() } }
    @objc private func resetPresets() { if view.acceptsSettingsInput { onReset?() } }
    @objc private func saveCurrent() { if view.acceptsSettingsInput { onSave?() } }
    @objc private func closeLibrary() { if view.acceptsSettingsInput { onClose?() } }
    override func cancelOperation(_ sender: Any?) { closeLibrary() }
    static func label(_ string: String, size: CGFloat, weight: NSFont.Weight = .regular, secondary: Bool = false) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: string)
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = secondary ? DesignTokens.textMuted : DesignTokens.text
        return label
    }
}
