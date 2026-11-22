import AppKit

final class PresetNameController: NSViewController, NSTextFieldDelegate {
    let nameField = DesignAlertTextField()
    let message = NSTextField(wrappingLabelWithString: "")
    let cancelButton = PresetFocusButton("Cancel")
    let submitButton: PresetFocusButton
    private let heading: String
    private let symbol: String
    private let initialName: String
    private let validate: (String) throws -> Void
    private let save: (String) throws -> Void
    var onClose: ((_ saved: Bool) -> Void)?

    init(renaming: Bool, name: String = "", validate: @escaping (String) throws -> Void, save: @escaping (String) throws -> Void) {
        heading = renaming ? "Rename preset" : "Save preset"
        symbol = renaming ? "pencil" : "bookmark"
        initialName = name; self.validate = validate; self.save = save
        submitButton = PresetFocusButton(renaming ? "Rename" : "Save")
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("Use init(renaming:name:validate:save:)") }
    override func loadView() {
        let root = DesignAlertPanel(title: heading, symbol: symbol)
        let inset = DesignAlertPanel.inset
        let width = DesignAlertPanel.contentWidth
        let caption = NSTextField(labelWithString: "Preset name")
        caption.font = .systemFont(ofSize: DesignTokens.Font.caption, weight: .medium)
        caption.textColor = DesignTokens.textMuted
        caption.frame = NSRect(x: inset, y: root.headingBottom + DesignTokens.Space.md, width: width, height: 14)
        root.contentView.addSubview(caption)
        nameField.stringValue = initialName
        nameField.frame = NSRect(x: inset, y: caption.frame.maxY + DesignTokens.Space.xs,
                                 width: width, height: DesignTokens.Control.height)
        nameField.setAccessibilityLabel(caption.stringValue)
        nameField.delegate = self
        root.contentView.addSubview(nameField)
        message.font = .systemFont(ofSize: DesignTokens.Font.caption)
        message.textColor = DesignTokens.accentText
        root.contentView.addSubview(message)
        cancelButton.target = self
        cancelButton.action = #selector(closeEditor)
        cancelButton.keyEquivalent = "\u{1b}"
        submitButton.primary = true
        submitButton.target = self
        submitButton.action = #selector(submit)
        submitButton.keyEquivalent = "\r"
        root.addActions(cancel: cancelButton, confirm: submitButton)
        nameField.nextKeyView = cancelButton
        cancelButton.nextKeyView = submitButton
        submitButton.nextKeyView = nameField
        view = root; validateName(showEmpty: false)
    }
    func controlTextDidChange(_ notification: Notification) { validateName(showEmpty: true) }
    func validateName(showEmpty: Bool = true) {
        do {
            try validate(nameField.stringValue)
            updateValidation(message: "", valid: true)
        }
        catch {
            updateValidation(message: !showEmpty && nameField.stringValue.isEmpty ? "" : error.localizedDescription,
                             valid: false)
        }
    }

    private func updateValidation(message text: String, valid: Bool) {
        submitButton.isEnabled = valid
        message.stringValue = text
        message.isHidden = text.isEmpty
        let panel = view as! DesignAlertPanel
        var contentBottom = nameField.frame.maxY
        if !text.isEmpty {
            let width = DesignAlertPanel.contentWidth
            message.frame = NSRect(x: DesignAlertPanel.inset, y: contentBottom + DesignTokens.Space.sm,
                                   width: width, height: DesignAlertPanel.textHeight(message, width: width))
            contentBottom = message.frame.maxY
        }
        panel.placeActions(cancel: cancelButton, confirm: submitButton, below: contentBottom)
    }

    @objc func submit() {
        guard view.acceptsSettingsInput else { return }
        do {
            try validate(nameField.stringValue)
            try save(nameField.stringValue)
            onClose?(true)
        } catch { updateValidation(message: error.localizedDescription, valid: false) }
    }
    @objc private func closeEditor() { onClose?(false) }
    override func cancelOperation(_ sender: Any?) { closeEditor() }
}

/// Blocks interaction behind the presentation and dismisses on an outside click.
final class PresetOverlay: SettingsSurface {
    override var acceptsBackgroundHits: Bool { true }
    weak var panel: NSView?
    var onClose: (() -> Void)?
    var dimOpacity: CGFloat = 0.06 { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(dimOpacity).setFill(); bounds.fill()
    }
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let panel, panel.bounds.contains(panel.convert(point, from: self)) { return }
        onClose?()
    }
    override func cancelOperation(_ sender: Any?) { onClose?() }
}
