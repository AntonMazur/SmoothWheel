import AppKit

/// Track keyboard navigation separately from edits in the shared AppKit field editor.
final class SettingsWindow: NSWindow {
    private(set) var showsPresetKeyboardFocus = false

    private var isEditingTextField: Bool {
        (firstResponder as? NSTextView)?.isFieldEditor == true
    }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .keyDown:
            // Tab moves out of the field; Escape restores focus to the invoking control.
            let leavesEditor = event.keyCode == 48 || event.keyCode == 53
            setPresetKeyboardFocus(!isEditingTextField || leavesEditor)
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            setPresetKeyboardFocus(false)
        default:
            break
        }
        super.sendEvent(event)
    }

    private func setPresetKeyboardFocus(_ visible: Bool) {
        guard showsPresetKeyboardFocus != visible else { return }
        showsPresetKeyboardFocus = visible
        (firstResponder as? PresetFocusButton)?.needsDisplay = true
    }

    override func makeFirstResponder(_ responder: NSResponder?) -> Bool {
        if let view = responder as? NSView, !view.acceptsSettingsInput { return false }
        let previous = firstResponder as? PresetFocusButton
        let changed = super.makeFirstResponder(responder)
        if isEditingTextField { showsPresetKeyboardFocus = false }
        previous?.needsDisplay = true
        (firstResponder as? PresetFocusButton)?.needsDisplay = true
        return changed
    }
}

class PresetFocusButton: DesignButton {
    static func setKeyLoop(_ buttons: [PresetFocusButton]) {
        for (index, button) in buttons.enumerated() {
            button.cyclesPresetFocus = true
            button.nextKeyView = buttons[(index + 1) % buttons.count]
        }
    }

    private var cyclesPresetFocus = false

    override init(_ title: String, target: AnyObject? = nil, action: Selector? = nil) {
        super.init(title, target: target, action: action)
        focusRingType = .none
    }

    required init?(coder: NSCoder) { fatalError("Use init(_:target:action:)") }

    var showsKeyboardFocus: Bool {
        guard let window = window as? SettingsWindow else { return false }
        return isEnabled && window.attachedSheet == nil && window.showsPresetKeyboardFocus && window.firstResponder === self
    }

    func drawKeyboardFocus() {
        guard showsKeyboardFocus else { return }
        keyboardFocusColor.setFill()
        NSBezierPath(roundedRect: keyboardFocusMarker, xRadius: 1, yRadius: 1).fill()
    }

    var keyboardFocusColor: NSColor { DesignTokens.focus }

    var keyboardFocusMarker: NSRect {
        let y = circularIconBounds.map { $0.minY + DesignTokens.Space.xs } ?? 3
        return NSRect(x: leadingInset ?? bounds.midX - 9, y: y, width: 18, height: 2)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawKeyboardFocus()
    }

    override func keyDown(with event: NSEvent) {
        guard isEnabled else { return }
        // These preset panels have an explicit, local tab order.
        if cyclesPresetFocus && event.keyCode == 48,
           let next = event.modifierFlags.contains(.shift) ? previousKeyView : nextKeyView {
            next.scrollToVisible(next.bounds)
            window?.makeFirstResponder(next)
        } else if cyclesPresetFocus && (event.keyCode == 36 || event.keyCode == 76) {
            performClick(nil)
        } else {
            super.keyDown(with: event)
        }
    }
}
