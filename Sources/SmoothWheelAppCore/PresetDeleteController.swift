import AppKit

final class PresetDeleteController: NSViewController {
    let question: String
    let cancel = PresetFocusButton("Cancel")
    let delete = PresetFocusButton("Delete")
    var onCancel: (() -> Void)?
    var onDelete: (() -> Void)?

    init(name: String) {
        question = "Delete “\(name)”?"
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("Use init(name:)") }

    override func loadView() {
        let root = DesignAlertPanel(title: question, symbol: "trash", destructive: true)
        root.setAccessibilityLabel("Confirm preset deletion")
        cancel.target = self
        cancel.action = #selector(cancelDeletion)
        cancel.keyEquivalent = "\u{1b}"
        delete.target = self
        delete.action = #selector(confirmDeletion)
        delete.destructive = true
        delete.hasDestructiveAction = true
        root.addActions(cancel: cancel, confirm: delete)
        root.placeActions(cancel: cancel, confirm: delete, below: root.headingBottom)

        PresetFocusButton.setKeyLoop([cancel, delete])
        view = root
    }

    @objc private func cancelDeletion() { onCancel?() }
    @objc private func confirmDeletion() { onDelete?() }
    override func cancelOperation(_ sender: Any?) { cancelDeletion() }
}
