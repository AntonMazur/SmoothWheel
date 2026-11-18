import AppKit

/// Native surfaces use semantic tokens, including dark and high-contrast appearances.
final class DesignSurface: NSView {
    var fill: NSColor = DesignTokens.surface
    var radius: CGFloat = DesignTokens.Radius.panel
    var outlined = true
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
        fill.setFill(); path.fill()
        if outlined {
            (NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? DesignTokens.textMuted : DesignTokens.line).setStroke()
            path.lineWidth = 1; path.stroke()
        }
    }
    override func viewDidChangeEffectiveAppearance() { needsDisplay = true }
}

final class DesignButton: NSButton {
    var primary = false { didSet { needsDisplay = true } }
    var selected = false { didSet { needsDisplay = true } }
    var borderless = false
    var raisedSelection = false
    private var hovered = false
    override var intrinsicContentSize: NSSize {
        NSSize(width: max(80, (title as NSString).size(withAttributes: [.font: font ?? NSFont.systemFont(ofSize: 14)]).width + 30), height: 38)
    }
    init(_ title: String, target: AnyObject? = nil, action: Selector? = nil) {
        super.init(frame: .zero)
        self.title = title; self.target = target; self.action = action
        font = .systemFont(ofSize: 14, weight: .medium)
        isBordered = false; setButtonType(.momentaryPushIn); focusRingType = .exterior
    }
    required init?(coder: NSCoder) { fatalError("Use init(_:target:action:)") }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.activeInActiveApp, .mouseEnteredAndExited, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        let solid = primary || (selected && !raisedSelection)
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: bounds.height / 2, yRadius: bounds.height / 2)
        if !borderless || selected {
            let color = solid ? (hovered ? DesignTokens.primaryHover : DesignTokens.primary) : (hovered ? DesignTokens.accentWash : DesignTokens.surfaceRaised)
            color.withAlphaComponent(isEnabled ? (isHighlighted ? 0.78 : 1) : 0.4).setFill(); path.fill()
            if !solid { DesignTokens.line.setStroke(); path.lineWidth = 1; path.stroke() }
        }
        let color = solid ? DesignTokens.onPrimary : DesignTokens.text
        let style = NSMutableParagraphStyle(); style.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [.font: font ?? NSFont.systemFont(ofSize: 14, weight: .medium),
            .foregroundColor: isEnabled ? color : DesignTokens.textMuted, .paragraphStyle: style]
        let size = (title as NSString).size(withAttributes: attributes)
        (title as NSString).draw(in: NSRect(x: 5, y: (bounds.height - size.height) / 2, width: bounds.width - 10, height: size.height + 1), withAttributes: attributes)
    }
    override var focusRingMaskBounds: NSRect { bounds }
    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: bounds.height / 2, yRadius: bounds.height / 2).fill()
    }
    override func viewDidChangeEffectiveAppearance() { needsDisplay = true }
}

/// NSButton retains native Space/Tab activation, target/action and checkbox accessibility.
final class DesignSwitch: NSButton {
    override var state: NSControl.StateValue { didSet { needsDisplay = true } }
    override var intrinsicContentSize: NSSize { NSSize(width: DesignTokens.Control.switchWidth, height: DesignTokens.Control.switchHeight) }
    init(label: String, target: AnyObject?, action: Selector?) {
        super.init(frame: .zero)
        setButtonType(.switch); title = ""; isBordered = false; focusRingType = .exterior
        self.target = target; self.action = action; setAccessibilityLabel(label)
    }
    required init?(coder: NSCoder) { fatalError("Use init(label:target:action:)") }
    override func draw(_ dirtyRect: NSRect) {
        let area = bounds.insetBy(dx: 1, dy: 1)
        (state == .on ? DesignTokens.accent : DesignTokens.track).setFill()
        NSBezierPath(roundedRect: area, xRadius: area.height / 2, yRadius: area.height / 2).fill()
        let diameter = area.height - 5
        let x = state == .on ? area.maxX - diameter - 2.5 : area.minX + 2.5
        NSColor.white.setFill()
        NSBezierPath(ovalIn: NSRect(x: x, y: area.midY - diameter / 2, width: diameter, height: diameter)).fill()
    }
    override var focusRingMaskBounds: NSRect { bounds }
    override func drawFocusRingMask() { NSBezierPath(roundedRect: bounds, xRadius: 15, yRadius: 15).fill() }
    override func viewDidChangeEffectiveAppearance() { needsDisplay = true }
}

final class DesignSliderCell: NSSliderCell {
    override func drawBar(inside rect: NSRect, flipped: Bool) {
        let bar = NSRect(x: rect.minX, y: rect.midY - 3, width: rect.width, height: 6)
        DesignTokens.track.setFill(); NSBezierPath(roundedRect: bar, xRadius: 3, yRadius: 3).fill()
        let fraction = CGFloat((doubleValue - minValue) / max(0.001, maxValue - minValue))
        let filled = NSRect(x: bar.minX, y: bar.minY, width: bar.width * fraction, height: 6)
        DesignTokens.text.setFill(); NSBezierPath(roundedRect: filled, xRadius: 3, yRadius: 3).fill()
    }
    override func drawKnob(_ knobRect: NSRect) {
        let knob = NSRect(x: knobRect.midX - 10, y: knobRect.midY - 10, width: 20, height: 20)
        DesignTokens.accent.setFill(); NSBezierPath(ovalIn: knob).fill()
    }
}

final class PresetControl: NSControl {
    private var buttons: [DesignButton] = []
    var labels: [String]
    var selectedIndex = -1 { didSet { updateSelection() } }
    init(labels: [String], raisedSelection: Bool = false) {
        self.labels = labels
        super.init(frame: .zero)
        let background = DesignSurface(); background.fill = DesignTokens.track.withAlphaComponent(0.4); background.radius = 21; background.outlined = false
        background.translatesAutoresizingMaskIntoConstraints = false; addSubview(background)
        NSLayoutConstraint.activate([background.leadingAnchor.constraint(equalTo: leadingAnchor), background.trailingAnchor.constraint(equalTo: trailingAnchor),
            background.topAnchor.constraint(equalTo: topAnchor), background.bottomAnchor.constraint(equalTo: bottomAnchor)])
        let stack = NSStackView(); stack.orientation = .horizontal; stack.distribution = .fillEqually; stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false; addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 3), stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -3),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 3), stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3)])
        for (index, label) in labels.enumerated() {
            let button = DesignButton(label, target: self, action: #selector(choose(_:)))
            button.font = .systemFont(ofSize: 15, weight: .medium)
            button.tag = index; button.borderless = true; button.raisedSelection = raisedSelection
            button.setAccessibilityRole(.radioButton); button.setAccessibilityLabel(label)
            button.setAccessibilityElement(true); button.setAccessibilityChildren([])
            stack.addArrangedSubview(button); buttons.append(button)
        }
        setAccessibilityRole(.group)
        setAccessibilityLabel(labels.joined(separator: ", "))
        setAccessibilityElement(true)
        setAccessibilityChildren(buttons)
    }
    required init?(coder: NSCoder) { fatalError("Use init(labels:)") }
    private func updateSelection() {
        for (index, button) in buttons.enumerated() {
            button.selected = index == selectedIndex
            button.setAccessibilityValue(index == selectedIndex ? 1 : 0)
        }
    }
    @objc private func choose(_ sender: DesignButton) {
        selectedIndex = sender.tag
        if let action { sendAction(action, to: target) }
    }
}

/// Keep short and long exclusion lists anchored at the top of their scroll view.
final class TopAlignedDocumentView: NSView {
    override var isFlipped: Bool { true }
}
