import AppKit
import QuartzCore

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

class DesignButton: NSButton {
    var primary = false { didSet { needsDisplay = true } }
    var selected = false { didSet { needsDisplay = true } }
    var borderless = false
    var raisedSelection = false
    var leadingInset: CGFloat?
    var destructive = false
    var usesAlertShape = false { didSet { needsDisplay = true } }
    private var circularDiscDiameter: CGFloat?
    private var hovered = false
    private var canTrackPointerHover: Bool {
        guard let window else { return false }
        return isEnabled && acceptsSettingsInput && !isHiddenOrHasHiddenAncestor && window.attachedSheet == nil
    }
    var showsPointerHover: Bool { hovered && canTrackPointerHover }
    override var isEnabled: Bool {
        didSet {
            if !isEnabled { hovered = false }
            needsDisplay = true
        }
    }
    override var intrinsicContentSize: NSSize {
        if circularDiscDiameter != nil {
            return NSSize(width: DesignTokens.Control.height, height: DesignTokens.Control.height)
        }
        return NSSize(width: max(80, (title as NSString).size(withAttributes: [.font: font ?? NSFont.systemFont(ofSize: 14)]).width + 30 + (image == nil ? 0 : 22)), height: 38)
    }
    init(_ title: String, target: AnyObject? = nil, action: Selector? = nil) {
        super.init(frame: .zero)
        self.title = title; self.target = target; self.action = action
        font = .systemFont(ofSize: 14, weight: .medium)
        isBordered = false; setButtonType(.momentaryPushIn); focusRingType = .exterior
    }
    required init?(coder: NSCoder) { fatalError("Use init(_:target:action:)") }

    convenience init(circularIcon name: String, label: String,
                     discDiameter: CGFloat = DesignTokens.Control.height - DesignTokens.Space.sm) {
        self.init("")
        circularDiscDiameter = discDiameter
        image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .medium))
        toolTip = label
        setAccessibilityLabel(label)
    }

    var circularIconBounds: NSRect? {
        guard let diameter = circularDiscDiameter else { return nil }
        return NSRect(x: bounds.midX - diameter / 2, y: bounds.midY - diameter / 2,
                      width: diameter, height: diameter)
    }

    func clearPointerHover() {
        guard hovered else { return }
        hovered = false
        needsDisplay = true
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow !== window { clearPointerHover() }
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidHide() {
        super.viewDidHide()
        clearPointerHover()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.activeInActiveApp, .mouseEnteredAndExited, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with event: NSEvent) {
        hovered = canTrackPointerHover
        needsDisplay = true
    }
    override func mouseExited(with event: NSEvent) { clearPointerHover() }
    override func draw(_ dirtyRect: NSRect) {
        if let disc = circularIconBounds {
            drawCircularIcon(in: disc, increasedContrast: NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast)
            return
        }
        let solid = primary || (selected && !raisedSelection)
        let actionRow = borderless && leadingInset != nil
        let hover = showsPointerHover
        let radius = usesAlertShape ? DesignTokens.Radius.control : actionRow ? DesignTokens.Radius.small : bounds.height / 2
        let insetY: CGFloat = actionRow ? 3 : 1
        let inset: CGFloat = usesAlertShape ? 0.5 : 1
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: inset, dy: usesAlertShape ? inset : insetY), xRadius: radius, yRadius: radius)
        if !borderless || selected || (hover && (actionRow || raisedSelection)) {
            let color: NSColor
            if usesAlertShape && !isEnabled {
                color = DesignTokens.surfaceRaised
            } else if actionRow {
                color = DesignTokens.track
            } else if solid {
                color = hover || (usesAlertShape && isHighlighted) ? DesignTokens.primaryHover : DesignTokens.primary
            } else if usesAlertShape && destructive {
                color = DesignTokens.accentWash
            } else if usesAlertShape {
                color = hover || isHighlighted ? DesignTokens.track : DesignTokens.surface
            } else {
                color = hover ? DesignTokens.track : DesignTokens.surfaceRaised
            }
            let opacity: CGFloat = usesAlertShape ? 1 : isEnabled ? (isHighlighted ? 0.78 : 1) : 0.4
            color.withAlphaComponent(actionRow ? opacity * 0.52 : opacity).setFill()
            path.fill()
            if usesAlertShape {
                let highContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
                if destructive && (hover || isHighlighted || highContrast) {
                    DesignTokens.accentText.setStroke(); path.lineWidth = isHighlighted ? 2 : 1; path.stroke()
                } else if !isEnabled || (!solid && !destructive) {
                    (highContrast ? DesignTokens.textMuted : DesignTokens.line).setStroke()
                    path.lineWidth = 1; path.stroke()
                }
            } else if !solid && (!borderless || selected) {
                DesignTokens.line.setStroke(); path.lineWidth = 1; path.stroke()
            }
        }
        let color = solid ? DesignTokens.onPrimary : destructive ? DesignTokens.accentText : DesignTokens.text
        let style = NSMutableParagraphStyle(); style.alignment = leadingInset == nil ? .center : .left; style.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [.font: font ?? NSFont.systemFont(ofSize: 14, weight: .medium),
            .foregroundColor: isEnabled ? color : DesignTokens.textMuted, .paragraphStyle: style]
        let size = (title as NSString).size(withAttributes: attributes)
        if let image {
            let symbolWidth: CGFloat = 14, gap: CGFloat = 8
            let symbol = image.withSymbolConfiguration(.init(paletteColors: [color])) ?? image
            if title.isEmpty {
                symbol.draw(in: NSRect(x: bounds.midX - symbolWidth / 2, y: bounds.midY - symbolWidth / 2,
                                       width: symbolWidth, height: symbolWidth))
                return
            }
            let textWidth = min(size.width + 1, bounds.width - symbolWidth - gap - (leadingInset ?? 24))
            let origin = leadingInset ?? (bounds.width - textWidth - symbolWidth - gap) / 2
            let trailing = imagePosition == .imageRight
            symbol.draw(in: NSRect(x: trailing ? origin + textWidth + gap : origin,
                                   y: (bounds.height - symbolWidth) / 2, width: symbolWidth, height: symbolWidth))
            (title as NSString).draw(in: NSRect(x: trailing ? origin : origin + symbolWidth + gap,
                                              y: (bounds.height - size.height) / 2,
                                              width: textWidth, height: size.height + 1), withAttributes: attributes)
        } else {
            let inset = leadingInset ?? 5
            (title as NSString).draw(in: NSRect(x: inset, y: (bounds.height - size.height) / 2, width: bounds.width - 2 * inset, height: size.height + 1), withAttributes: attributes)
        }
    }
    func drawCircularIcon(in disc: NSRect, increasedContrast: Bool) {
        let pressed = isEnabled && isHighlighted
        let fill = showsPointerHover || pressed ? DesignTokens.track : DesignTokens.line
        let ink = !isEnabled || pressed ? DesignTokens.textMuted : DesignTokens.text
        let path = NSBezierPath(ovalIn: disc)
        fill.setFill()
        path.fill()

        if increasedContrast {
            DesignTokens.textMuted.setStroke()
            NSBezierPath(ovalIn: disc.insetBy(dx: 0.5, dy: 0.5)).stroke()
        }
        guard let image else { return }
        let symbol = image.withSymbolConfiguration(.init(paletteColors: [ink])) ?? image
        symbol.draw(in: NSRect(x: disc.midX - symbol.size.width / 2, y: disc.midY - symbol.size.height / 2,
                               width: symbol.size.width, height: symbol.size.height))
    }
    override var focusRingMaskBounds: NSRect { circularIconBounds ?? bounds }
    override func drawFocusRingMask() {
        if let disc = circularIconBounds {
            NSBezierPath(ovalIn: disc).fill()
            return
        }
        let radius = usesAlertShape ? DesignTokens.Radius.control : bounds.height / 2
        NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: radius, yRadius: radius).fill()
    }
    override func viewDidChangeEffectiveAppearance() { needsDisplay = true }
}

/// NSButton retains native Space/Tab activation, target/action and checkbox accessibility.
final class DesignSwitch: NSButton {
    private var confirmed: NSControl.StateValue?
    private var transition: SwitchTransition?
    var isAnimating: Bool { transition != nil }
    var visualProgress: CGFloat { transition?.progress ?? (confirmed == .on ? 1 : 0) }
    override var intrinsicContentSize: NSSize { NSSize(width: DesignTokens.Control.switchWidth, height: DesignTokens.Control.switchHeight) }
    init(label: String, target: AnyObject?, action: Selector?) {
        super.init(frame: .zero)
        setButtonType(.switch); title = ""; isBordered = false; focusRingType = .exterior
        self.target = target; self.action = action; setAccessibilityLabel(label)
    }
    required init?(coder: NSCoder) { fatalError("Use init(label:target:action:)") }

    func setConfirmedState(_ value: NSControl.StateValue, animated: Bool) {
        if state != value { state = value }
        let previous = confirmed
        let previousProgress = visualProgress
        confirmed = value
        guard animated, previous != nil else { finishTransition(); return }
        guard value != previous else { return }
        stopTransition()
        let target: CGFloat = value == .on ? 1 : 0
        needsDisplay = true
        guard previousProgress != target else { return }
        wantsLayer = true
        guard let layer else { return }
        let area = bounds.insetBy(dx: 1, dy: 1)
        let visual = SwitchTransition(area: area, from: previousProgress, target: target)
        transition = visual
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock { [weak self, weak visual] in
            guard let self, let visual, transition === visual else { return }
            finishTransition()
        }
        layer.addSublayer(visual.track)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            visual.start(fromColor: fill(at: previousProgress).cgColor, toColor: fill(at: target).cgColor)
        }
        CATransaction.commit()
    }

    func finishTransition() {
        stopTransition()
        needsDisplay = true
    }

    private func stopTransition() {
        let old = transition
        transition = nil
        old?.track.removeFromSuperlayer()
        old?.track.removeAllAnimations()
        old?.knob.removeAllAnimations()
    }

    private func fill(at progress: CGFloat) -> NSColor {
        let track = DesignTokens.track
        return progress == 0 ? track : progress == 1 ? DesignTokens.accent
            : track.blended(withFraction: progress, of: DesignTokens.accent) ?? track
    }

    override func draw(_ dirtyRect: NSRect) {
        let area = bounds.insetBy(dx: 1, dy: 1)
        let progress: CGFloat = confirmed == .on ? 1 : 0
        fill(at: progress).setFill()
        NSBezierPath(roundedRect: area, xRadius: area.height / 2, yRadius: area.height / 2).fill()
        let diameter = area.height - 5
        let x = area.minX + 2.5 + (area.width - diameter - 5) * progress
        NSColor.white.setFill()
        NSBezierPath(ovalIn: NSRect(x: x, y: area.midY - diameter / 2, width: diameter, height: diameter)).fill()
    }
    override var focusRingMaskBounds: NSRect { bounds }
    override func drawFocusRingMask() { NSBezierPath(roundedRect: bounds, xRadius: 15, yRadius: 15).fill() }
    override func viewDidChangeEffectiveAppearance() { finishTransition(); needsDisplay = true }
    override func viewDidHide() { super.viewDidHide(); finishTransition() }
}

private final class SwitchTransition {
    let track = CALayer()
    let knob = CALayer()
    private let from: CGFloat
    private let target: CGFloat
    private let offX: CGFloat
    private let travel: CGFloat

    init(area: NSRect, from: CGFloat, target: CGFloat) {
        self.from = from
        self.target = target
        let diameter = area.height - 5
        offX = 2.5 + diameter / 2
        travel = area.width - diameter - 5
        track.frame = area
        track.cornerRadius = area.height / 2
        knob.bounds = CGRect(x: 0, y: 0, width: diameter, height: diameter)
        knob.position = CGPoint(x: offX + travel * target, y: area.height / 2)
        knob.cornerRadius = diameter / 2
        knob.backgroundColor = NSColor.white.cgColor
        track.addSublayer(knob)
    }

    var progress: CGFloat {
        guard let position = knob.presentation()?.position, travel > 0 else { return from }
        return min(1, max(0, (position.x - offX) / travel))
    }

    func start(fromColor: CGColor, toColor: CGColor) {
        track.backgroundColor = toColor
        addAnimation(to: track, keyPath: "backgroundColor", from: fromColor, to: toColor)
        addAnimation(to: knob, keyPath: "position.x", from: offX + travel * from, to: offX + travel * target)
    }

    private func addAnimation(to layer: CALayer, keyPath: String, from: Any, to: Any) {
        let effect = CABasicAnimation(keyPath: keyPath)
        effect.duration = DesignTokens.Motion.normal
        effect.timingFunction = CAMediaTimingFunction(name: .easeOut)
        effect.fromValue = from
        effect.toValue = to
        layer.add(effect, forKey: keyPath)
    }
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
