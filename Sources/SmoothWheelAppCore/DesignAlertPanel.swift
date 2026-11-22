import AppKit

/// Preset panels share an opaque surface whose content can be retired independently.
class PresetCard: NSView {
    let contentView = PresetCanvas()
    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        let surface = DesignSurface(frame: bounds)
        surface.fill = DesignTokens.surfaceRaised
        surface.autoresizingMask = [.width, .height]
        addSubview(surface)
        contentView.frame = bounds
        addSubview(contentView)
    }

    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        contentView.frame = bounds
    }
}

/// Shared Soft Form alert surface, heading and paired actions.
final class DesignAlertPanel: PresetCard {
    static let panelWidth: CGFloat = 320
    static let inset = DesignTokens.Space.lg
    static let contentWidth = panelWidth - 2 * inset
    let title: NSTextField
    let symbolTile = DesignSurface()

    init(title text: String, symbol name: String, destructive: Bool = false) {
        title = NSTextField(wrappingLabelWithString: text)
        super.init(frame: NSRect(x: 0, y: 0, width: Self.panelWidth, height: 0))
        setAccessibilityLabel(text)

        let inset = Self.inset
        let tileSize = DesignTokens.Space.xl
        symbolTile.frame = NSRect(x: destructive ? (Self.panelWidth - tileSize) / 2 : inset,
                                  y: inset, width: tileSize, height: tileSize)
        symbolTile.fill = destructive ? DesignTokens.accentWash : DesignTokens.mint
        symbolTile.radius = DesignTokens.Radius.small
        symbolTile.outlined = false
        if let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) {
            let icon = NSImageView(image: image)
            icon.frame = symbolTile.bounds
            icon.imageScaling = .scaleNone
            icon.symbolConfiguration = .init(pointSize: DesignTokens.Font.body, weight: .medium)
            icon.contentTintColor = destructive ? DesignTokens.accentText : DesignTokens.text
            icon.setAccessibilityElement(false)
            symbolTile.addSubview(icon)
        }
        contentView.addSubview(symbolTile)

        title.font = .systemFont(ofSize: 20, weight: .semibold)
        title.textColor = DesignTokens.text
        title.alignment = destructive ? .center : .left
        let titleX = destructive ? inset : symbolTile.frame.maxX + DesignTokens.Space.sm
        let titleWidth = Self.panelWidth - inset - titleX
        let titleHeight = max(24, Self.textHeight(title, width: titleWidth))
        let titleY = destructive ? symbolTile.frame.maxY + DesignTokens.Radius.control
            : symbolTile.frame.midY - titleHeight / 2
        title.frame = NSRect(x: titleX, y: titleY, width: titleWidth, height: titleHeight)
        contentView.addSubview(title)
    }

    required init?(coder: NSCoder) { fatalError("Use init(title:symbol:destructive:)") }

    var headingBottom: CGFloat { max(title.frame.maxY, symbolTile.frame.maxY) }

    static func textHeight(_ field: NSTextField, width: CGFloat) -> CGFloat {
        ceil(field.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: width, height: .greatestFiniteMagnitude)).height ?? 0)
    }

    func addActions(cancel: DesignButton, confirm: DesignButton) {
        cancel.usesAlertShape = true
        confirm.usesAlertShape = true
        confirm.font = .systemFont(ofSize: 14, weight: .semibold)
        contentView.addSubview(cancel)
        contentView.addSubview(confirm)
    }

    func placeActions(cancel: DesignButton, confirm: DesignButton, below contentBottom: CGFloat) {
        let gap = DesignTokens.Space.sm
        let width = (Self.contentWidth - gap) / 2
        let y = contentBottom + DesignTokens.Space.md
        let height = DesignTokens.Control.height
        cancel.frame = NSRect(x: Self.inset, y: y, width: width, height: height)
        confirm.frame = NSRect(x: cancel.frame.maxX + gap, y: y, width: width, height: height)
        let panelHeight = y + height + Self.inset
        // Keep the mounted panel centered around the same point as validation wraps or clears.
        let originY = superview == nil ? frame.minY : frame.midY - panelHeight / 2
        frame = NSRect(x: frame.minX, y: originY, width: Self.panelWidth, height: panelHeight)
    }
}

/// Keeps AppKit's field editor and gives the text and caret the same inset.
private final class DesignAlertFieldCell: NSTextFieldCell {
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        let textHeight = min(rect.height, ceil(font?.boundingRectForFont.height ?? rect.height))
        return super.drawingRect(forBounds: rect.insetBy(dx: DesignTokens.Radius.control,
                                                         dy: (rect.height - textHeight) / 2))
    }

    override func edit(withFrame rect: NSRect, in view: NSView, editor: NSText, delegate: Any?, event: NSEvent?) {
        super.edit(withFrame: drawingRect(forBounds: rect), in: view, editor: editor, delegate: delegate, event: event)
    }

    override func select(withFrame rect: NSRect, in view: NSView, editor: NSText, delegate: Any?, start: Int, length: Int) {
        super.select(withFrame: drawingRect(forBounds: rect), in: view, editor: editor, delegate: delegate,
                     start: start, length: length)
    }
}

final class DesignAlertTextField: NSTextField {
    init() {
        super.init(frame: .zero)
        cell = DesignAlertFieldCell(textCell: "")
        isEditable = true
        isSelectable = true
        isBordered = false
        drawsBackground = false
        usesSingleLineMode = true
        focusRingType = .none
        font = .systemFont(ofSize: DesignTokens.Font.body)
        textColor = DesignTokens.text
    }

    required init?(coder: NSCoder) { fatalError("Use init()") }

    override func draw(_ dirtyRect: NSRect) {
        let focused = currentEditor() != nil
        let highContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        let inset: CGFloat = focused ? 1 : 0.5
        let radius = DesignTokens.Radius.control
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: inset, dy: inset), xRadius: radius, yRadius: radius)
        DesignTokens.surface.setFill()
        path.fill()
        let stroke = focused ? DesignTokens.focus : highContrast ? DesignTokens.textMuted : DesignTokens.line
        stroke.setStroke()
        path.lineWidth = focused ? 2 : 1
        path.stroke()
        super.draw(dirtyRect)
    }

    override func becomeFirstResponder() -> Bool {
        let focused = super.becomeFirstResponder()
        needsDisplay = true
        return focused
    }

    override func textDidEndEditing(_ notification: Notification) {
        super.textDidEndEditing(notification)
        needsDisplay = true
    }

    override func viewDidChangeEffectiveAppearance() { needsDisplay = true }
}
