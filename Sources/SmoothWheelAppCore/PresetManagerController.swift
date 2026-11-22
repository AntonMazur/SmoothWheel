import AppKit

/// The highlighted record is a management selection, independent of what is in use.
final class PresetManagerController: NSViewController {
    private var presets: [SavedScrollPreset]
    private let activeID: UUID?
    private let list = DesignSurface()
    private let scroll = NSScrollView()
    private let document = PresetCanvas()
    private let actions = PresetCanvas()
    private(set) var selectedID: UUID?
    private(set) var rows: [PresetRowButton] = []
    let back = PresetFocusButton(circularIcon: "chevron.backward", label: "Back to Presets")
    let rename = PresetFocusButton("Rename")
    let delete = PresetFocusButton("Delete")
    private(set) var actionTitle: NSTextField?
    var onBack: (() -> Void)?
    var onRename: ((UUID) -> Void)?
    var onDelete: ((UUID) -> Void)?

    init(presets: [SavedScrollPreset], activeID: UUID?, selectedID: UUID?) {
        self.presets = presets
        self.activeID = activeID
        self.selectedID = [selectedID, activeID].compactMap { $0 }
            .first(where: { id in presets.contains { $0.id == id } }) ?? presets.first?.id
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("Use init(presets:activeID:selectedID:)") }

    override func loadView() {
        let width: CGFloat = 524
        let root = PresetCanvas(frame: NSRect(x: 0, y: 0, width: width, height: 502))
        root.setAccessibilityElement(true)
        root.setAccessibilityRole(.group)
        root.setAccessibilityLabel("Manage presets")
        back.target = self
        back.action = #selector(goBack)
        back.frame.size = back.intrinsicContentSize
        root.addSubview(back)

        let heading = PresetLibraryController.label("Manage presets", size: DesignTokens.Font.title, weight: .bold)
        heading.frame = NSRect(x: 8, y: 48, width: width - 16, height: 52)
        root.addSubview(heading)
        view = root

        if presets.isEmpty {
            let card = DesignSurface(frame: NSRect(x: 0, y: 116, width: width, height: 60))
            let empty = PresetLibraryController.label("No saved presets", size: DesignTokens.Font.body, secondary: true)
            empty.frame = NSRect(x: 20, y: 20, width: width - 40, height: 20)
            card.addSubview(empty)
            root.addSubview(card)
            PresetFocusButton.setKeyLoop([back])
            return
        }

        let rowHeight = PresetRowButton.rowHeight
        let documentHeight = CGFloat(presets.count) * rowHeight
        let listHeight = min(documentHeight, 196)
        list.frame = NSRect(x: 0, y: 116, width: width, height: listHeight + 20)
        list.fill = DesignTokens.surfaceRaised
        scroll.frame = list.bounds.insetBy(dx: 10, dy: 10)
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = documentHeight > listHeight
        scroll.autohidesScrollers = true
        document.frame = NSRect(x: 0, y: 0, width: scroll.contentSize.width, height: documentHeight)
        scroll.documentView = document
        for (index, preset) in presets.enumerated() {
            let row = PresetRowButton(preset.name, checked: preset.id == selectedID, inUse: preset.id == activeID,
                                      target: self, action: #selector(selectRecord(_:)))
            row.tag = index
            row.frame = NSRect(x: 0, y: CGFloat(index) * rowHeight, width: document.bounds.width, height: rowHeight)
            row.autoresizingMask = [.width]
            row.onArrow = { [weak self, weak row] direction in
                guard let row else { return }
                self?.focusRow(row.tag + direction)
            }
            row.onCancel = { [weak self] in self?.onBack?() }
            document.addSubview(row)
            rows.append(row)
        }
        list.addSubview(scroll)
        root.addSubview(list)

        actions.frame = NSRect(x: 0, y: list.frame.maxY + 16, width: width, height: 130)
        let surface = DesignSurface(frame: actions.bounds)
        surface.fill = DesignTokens.surfaceRaised
        actions.addSubview(surface)
        let title = PresetLibraryController.label(presets.first { $0.id == selectedID }?.name ?? "",
                                                  size: 20, weight: .semibold)
        title.lineBreakMode = .byTruncatingTail
        title.maximumNumberOfLines = 1
        title.frame = NSRect(x: 20, y: 16, width: width - 40, height: 26)
        actions.addSubview(title)
        actionTitle = title
        configureAction(rename, y: 46, width: width, action: #selector(renameRecord))
        configureAction(delete, y: 84, width: width, action: #selector(deleteRecord))
        delete.destructive = true
        actions.addSubview(rename)
        let divider = DesignSurface(frame: NSRect(x: 20, y: 82, width: width - 40, height: 2))
        divider.fill = DesignTokens.line
        divider.outlined = false
        divider.radius = 0
        actions.addSubview(divider)
        actions.addSubview(delete)
        root.addSubview(actions)

        PresetFocusButton.setKeyLoop([back] + rows + [rename, delete])
    }

    private func configureAction(_ button: PresetFocusButton, y: CGFloat, width: CGFloat, action: Selector) {
        button.borderless = true
        button.leadingInset = 12
        button.font = .systemFont(ofSize: DesignTokens.Font.body, weight: .medium)
        button.target = self
        button.action = action
        button.frame = NSRect(x: 10, y: y, width: width - 20, height: 36)
    }

    func setPanelPresented(_ presented: Bool) {
        for control in [back, rename, delete] + rows {
            control.isEnabled = !presented
        }
    }

    func updateName(_ preset: SavedScrollPreset) {
        guard let index = presets.firstIndex(where: { $0.id == preset.id }) else { return }
        presets[index] = preset
        rows[index].updateName(preset.name)
        if selectedID == preset.id { actionTitle?.stringValue = preset.name }
    }

    /// The empty layout is installed by the caller when the last record is removed.
    func removePreset(_ id: UUID, motion: SettingsMotion) -> Bool {
        guard presets.count > 1, let index = presets.firstIndex(where: { $0.id == id }) else { return false }
        let departing = rows.remove(at: index)
        let anchor = SettingsListAnchor(in: scroll, rows: rows)
        let oldViewport = document.visibleRect
        let oldPositions = rows.map { $0.frame.minY }
        let oldActionsY = actions.frame.minY
        motion.retireRow(departing, in: scroll)
        presets.remove(at: index)

        let documentHeight = CGFloat(rows.count) * PresetRowButton.rowHeight
        list.frame.size.height = min(documentHeight, 196) + 20
        scroll.frame = list.bounds.insetBy(dx: 10, dy: 10)
        scroll.hasVerticalScroller = documentHeight > scroll.frame.height
        document.frame.size = NSSize(width: scroll.contentSize.width, height: documentHeight)
        actions.frame.origin.y = list.frame.maxY + 16
        for (position, row) in rows.enumerated() {
            row.tag = position
            row.frame = NSRect(x: 0, y: CGFloat(position) * PresetRowButton.rowHeight,
                               width: document.bounds.width, height: PresetRowButton.rowHeight)
        }
        let fallback = presets.firstIndex(where: { $0.id == activeID }) ?? 0
        selectRecord(rows[fallback])
        PresetFocusButton.setKeyLoop([back] + rows + [rename, delete])
        anchor?.restore(in: scroll)
        view.window?.makeFirstResponder(anchor?.row ?? rows[fallback])
        let newViewport = document.visibleRect
        for (row, oldPosition) in zip(rows, oldPositions) where newViewport.intersects(row.frame) {
            motion.settle(row, verticalOffset: (oldPosition - oldViewport.minY) - (row.frame.minY - newViewport.minY))
        }
        motion.settle(actions, verticalOffset: oldActionsY - actions.frame.minY)
        return true
    }

    func focusSelection() {
        if let index = presets.firstIndex(where: { $0.id == selectedID }) {
            focusRow(index)
        } else {
            view.window?.makeFirstResponder(back)
        }
    }

    private func focusRow(_ index: Int) {
        let row = rows[(index + rows.count) % rows.count]
        row.scrollToVisible(row.bounds)
        view.window?.makeFirstResponder(row)
    }

    @objc private func selectRecord(_ row: PresetRowButton) {
        guard row.isEnabled, row.acceptsSettingsInput, rows.indices.contains(row.tag), rows[row.tag] === row else { return }
        let preset = presets[row.tag]
        selectedID = preset.id
        for choice in rows { choice.setChecked(choice === row) }
        actionTitle?.stringValue = preset.name
    }

    @objc private func goBack() { if back.isEnabled, view.acceptsSettingsInput { onBack?() } }
    @objc private func renameRecord() { if rename.isEnabled, view.acceptsSettingsInput, let selectedID { onRename?(selectedID) } }
    @objc private func deleteRecord() { if delete.isEnabled, view.acceptsSettingsInput, let selectedID { onDelete?(selectedID) } }
    override func cancelOperation(_ sender: Any?) { goBack() }
}
