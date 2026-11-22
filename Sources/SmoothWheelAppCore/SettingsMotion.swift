import AppKit
import QuartzCore

final class SettingsContentView: NSView {
    var onAppearanceChange: (() -> Void)?
    override func viewDidChangeEffectiveAppearance() { onAppearanceChange?() }
}

/// A mounted outgoing surface can draw, but cannot participate in input or accessibility.
class SettingsSurface: NSView {
    var isInteractive = true
    var acceptsBackgroundHits: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard isInteractive, let hit = super.hitTest(point) else { return nil }
        return hit === self && !acceptsBackgroundHits ? nil : hit
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        isInteractive && super.performKeyEquivalent(with: event)
    }

    override func isAccessibilityElement() -> Bool { isInteractive && super.isAccessibilityElement() }
    override func accessibilityChildren() -> [Any]? { isInteractive ? super.accessibilityChildren() : [] }
}

extension NSView {
    var acceptsSettingsInput: Bool {
        if let surface = self as? SettingsSurface, !surface.isInteractive { return false }
        return superview?.acceptsSettingsInput ?? true
    }
}

/// AppKit presentation effects. Views always hold their final geometry and input state.
final class SettingsMotion {
    enum Surface: Hashable { case presentation, list }
    private final class Exit {
        let view: SettingsSurface
        let remove: () -> Void
        init(view: SettingsSurface, remove: @escaping () -> Void) {
            self.view = view
            self.remove = remove
        }
    }

    private static let opacityKey = "smoothwheel.opacity"
    private static let positionKey = "smoothwheel.position"
    private let reduceMotion: () -> Bool
    private var outgoing: [Surface: Exit] = [:]
    private let animated = NSHashTable<NSView>.weakObjects()

    init(reduceMotion: @escaping () -> Bool) { self.reduceMotion = reduceMotion }

    func allowsMotion(in view: NSView?) -> Bool {
        !reduceMotion() && view?.window?.isVisible == true && view?.isHiddenOrHasHiddenAncestor == false
    }

    func departingView(in slot: Surface = .presentation) -> SettingsSurface? { outgoing[slot]?.view }

    func activate(_ view: SettingsSurface, in slot: Surface = .presentation) -> Float? {
        let opacity: Float?
        if outgoing[slot]?.view === view {
            opacity = view.layer.map(visibleOpacity)
            outgoing.removeValue(forKey: slot)
            resetOpacity(view)
        } else {
            discard(slot)
            opacity = nil
        }
        view.isHidden = false
        view.isInteractive = true
        return opacity
    }

    func discard(_ surface: Surface) {
        guard let exit = outgoing.removeValue(forKey: surface) else { return }
        exit.remove()
        resetOpacity(exit.view)
    }

    @discardableResult
    func retire(_ view: SettingsSurface, in slot: Surface = .presentation, animated: Bool = true,
                remove: @escaping () -> Void) -> Bool {
        discard(slot)
        view.isInteractive = false
        guard animated, allowsMotion(in: view) else {
            remove()
            resetOpacity(view)
            return false
        }
        view.wantsLayer = true
        guard let layer = view.layer,
              case let from = visibleOpacity(layer), from > 0 else {
            remove()
            resetOpacity(view)
            return false
        }
        animateExit(view, in: slot, on: layer, from: from, to: 0, remove: remove)
        return true
    }

    func swapPanels(_ previous: SettingsSurface, with incoming: SettingsSurface, in host: NSView,
                    incomingCoversPrevious: Bool, incomingOpacity: Float?, animated: Bool) {
        host.addSubview(incoming, positioned: .above, relativeTo: previous)
        if !incomingCoversPrevious {
            // Keep the smaller form visible while the old panel's exposed edges fade.
            retire(previous, animated: animated) { previous.removeFromSuperview() }
            return
        }

        // An opaque lower panel blocks the settings through every overlapping frame.
        discard(.presentation)
        previous.isInteractive = false
        resetOpacity(previous)
        let from = incomingOpacity ?? 0
        guard animated, from < 1, allowsMotion(in: incoming) else {
            previous.removeFromSuperview()
            return
        }
        incoming.wantsLayer = true
        guard let layer = incoming.layer else {
            previous.removeFromSuperview()
            return
        }
        self.animated.add(incoming)
        animateExit(previous, in: .presentation, on: layer, from: from, to: 1) {
            previous.removeFromSuperview()
        }
    }

    private func animateExit(_ view: SettingsSurface, in slot: Surface, on layer: CALayer,
                             from: Float, to: Float, remove: @escaping () -> Void) {
        let exit = Exit(view: view, remove: remove)
        outgoing[slot] = exit
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock { [weak self, weak exit] in
            guard let self, let exit, self.outgoing[slot] === exit else { return }
            self.discard(slot)
        }
        layer.opacity = to
        layer.add(animation("opacity", from: from, to: to, duration: DesignTokens.Motion.fast),
                  forKey: Self.opacityKey)
        CATransaction.commit()
    }

    func retireRow(_ row: NSView, in scroll: NSScrollView) {
        let viewport = scroll.convert(scroll.contentView.bounds, from: scroll.contentView)
        let frame = scroll.convert(row.bounds, from: row)
        guard allowsMotion(in: scroll), viewport.intersects(frame) else {
            row.removeFromSuperview()
            return
        }

        let clip = SettingsSurface(frame: viewport)
        clip.wantsLayer = true
        clip.layer?.masksToBounds = true
        scroll.addSubview(clip)
        let departureFrame = clip.convert(row.bounds, from: row)
        row.removeFromSuperview()
        row.translatesAutoresizingMaskIntoConstraints = true
        row.frame = departureFrame
        clip.addSubview(row)
        retire(clip, in: .list) { clip.removeFromSuperview() }
    }

    func fadeIn(_ view: NSView, from opacity: Float? = nil,
                duration: TimeInterval = DesignTokens.Motion.fast) {
        guard allowsMotion(in: view) else { return }
        view.wantsLayer = true
        guard let layer = view.layer else { return }
        animated.add(view)
        let restarting = layer.animation(forKey: Self.opacityKey) != nil
        let from = opacity ?? (restarting ? visibleOpacity(layer) : 0)
        layer.add(animation("opacity", from: from, to: 1, duration: duration),
                  forKey: Self.opacityKey)
    }

    /// Offset is expressed in the superview's coordinate system.
    func settle(_ view: NSView, verticalOffset: CGFloat) {
        guard verticalOffset != 0, allowsMotion(in: view) else { return }
        view.wantsLayer = true
        guard let layer = view.layer else { return }
        let flipped = view.superview?.isFlipped == true
        let layerFlipped = layer.superlayer?.isGeometryFlipped == true
        let from = flipped == layerFlipped ? verticalOffset : -verticalOffset
        animated.add(view)
        layer.add(animation("transform.translation.y", from: from, to: 0, duration: DesignTokens.Motion.normal),
                  forKey: Self.positionKey)
    }

    func finish() {
        for surface in Array(outgoing.keys) { discard(surface) }
        for view in animated.allObjects {
            view.layer?.removeAnimation(forKey: Self.opacityKey)
            view.layer?.removeAnimation(forKey: Self.positionKey)
        }
        animated.removeAllObjects()
    }

    private func resetOpacity(_ view: NSView) {
        guard let layer = view.layer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.opacity = 1
        layer.removeAnimation(forKey: Self.opacityKey)
        CATransaction.commit()
    }

    private func visibleOpacity(_ layer: CALayer) -> Float {
        if let opacity = layer.presentation()?.opacity { return opacity }
        let fade = layer.animation(forKey: Self.opacityKey) as? CABasicAnimation
        return (fade?.fromValue as? NSNumber)?.floatValue ?? layer.opacity
    }

    private func animation(_ keyPath: String, from: Any, to: Any, duration: TimeInterval) -> CABasicAnimation {
        let effect = CABasicAnimation(keyPath: keyPath)
        effect.fromValue = from
        effect.toValue = to
        effect.duration = duration
        effect.fillMode = .backwards
        effect.timingFunction = CAMediaTimingFunction(name: .easeOut)
        return effect
    }
}

/// Keep the first surviving visible row at its previous position after a list edit.
struct SettingsListAnchor {
    let row: NSView
    let offset: CGFloat

    init?(in scroll: NSScrollView, rows: [NSView]) {
        guard let document = scroll.documentView else { return nil }
        let origin = document.visibleRect
        guard let row = rows.first(where: { origin.intersects(document.convert($0.bounds, from: $0)) }) else { return nil }
        self.row = row
        self.offset = document.convert(row.bounds, from: row).minY - origin.minY
    }

    func restore(in scroll: NSScrollView) {
        guard let document = scroll.documentView, row.isDescendant(of: document) else { return }
        let clip = scroll.contentView
        var bounds = clip.bounds
        bounds.origin.y += document.convert(row.bounds, from: row).minY - offset - document.visibleRect.minY
        clip.scroll(to: clip.constrainBoundsRect(bounds).origin)
        scroll.reflectScrolledClipView(clip)
    }
}
