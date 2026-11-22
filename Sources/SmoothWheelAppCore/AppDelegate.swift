import AppKit
import ScrollCore
import ApplicationServices

public final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    public override convenience init() { self.init(engine: ScrollEngine(), defaults: .standard) }
    init(engine: ScrollEngine, defaults: UserDefaults,
         hasAccessibilityPermission: @escaping () -> Bool = { AXIsProcessTrusted() },
         startEngine: @escaping (ScrollEngine) -> Bool = { $0.start() }) {
        self.engine = engine; self.defaults = defaults
        self.hasAccessibilityPermission = hasAccessibilityPermission
        self.startEngine = startEngine
        presetStore = SavedPresetStore(defaults: defaults)
        super.init()
    }
    let engine: ScrollEngine
    let defaults: UserDefaults
    private let hasAccessibilityPermission: () -> Bool
    private let startEngine: (ScrollEngine) -> Bool
    let presetStore: SavedPresetStore
    var configuration: ScrollConfiguration {
        ScrollConfiguration(speed: engine.speed, smoothing: engine.smoothing, reversed: engine.reversed)
    }
    var presetTitle: String {
        if let active = presetStore.activePreset {
            return active.name + (active.configuration == configuration ? "" : " — Modified")
        }
        return ScrollPreset.matching(speed: engine.speed, smoothing: engine.smoothing)?.rawValue ?? "Custom"
    }
    var item: NSStatusItem!
    var settings: SettingsWindowController!
    var toggleItem: NSMenuItem!
    var excludeItem: NSMenuItem!
    var excludedApp: NSRunningApplication?
    var healthTimer: Timer?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        if let iconURL = Bundle.main.url(forResource: "SmoothWheelIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = icon
        }
        loadSettings()
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "computermouse", accessibilityDescription: "SmoothWheel")
        let menu = NSMenu(); menu.delegate = self
        let preferences = NSMenuItem(title: "SmoothWheel Settings…", action: #selector(showSettings), keyEquivalent: ",")
        preferences.target = self; menu.addItem(preferences)
        toggleItem = NSMenuItem(title: "Enable Smoothing", action: #selector(toggle), keyEquivalent: "")
        toggleItem.target = self; menu.addItem(toggleItem)
        excludeItem = NSMenuItem(title: "Exclude Current App", action: #selector(excludeCurrent), keyEquivalent: "")
        excludeItem.target = self; menu.addItem(excludeItem)
        menu.addItem(.separator())
        let reset = NSMenuItem(title: "Reset Scrolling Settings", action: #selector(resetScrolling), keyEquivalent: "")
        reset.target = self; menu.addItem(reset)
        let about = NSMenuItem(title: "About SmoothWheel", action: #selector(showAbout), keyEquivalent: "")
        about.target = self; menu.addItem(about)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit SmoothWheel", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self; menu.addItem(quit); item.menu = menu
        settings = SettingsWindowController(coordinator: self, permissionGranted: hasAccessibilityPermission)
        healthTimer = Timer.scheduledTimer(timeInterval: 2, target: self, selector: #selector(refresh), userInfo: nil, repeats: true)
        healthTimer?.tolerance = 0.4
        refresh(); showSettings()
    }
    @objc func showSettings() {
        NSApp.activate(ignoringOtherApps: true)
        settings.refresh()
        settings.showWindow(nil); settings.window?.makeKeyAndOrderFront(nil)
    }
    @objc func refresh() {
        if engine.enabled && (!hasAccessibilityPermission() || !engine.running) { engine.enabled = false; engine.stop() }
        updateInterface()
    }
    private func updateInterface() {
        toggleItem?.title = engine.enabled ? "Pause Smoothing" : "Enable Smoothing"
        item?.button?.toolTip = engine.enabled ? "SmoothWheel — Active" : "SmoothWheel — Paused"
        if settings?.window?.isVisible == true { settings.refresh() }
    }
    @objc func toggle() {
        if engine.enabled { engine.enabled = false; engine.stop() }
        else if hasAccessibilityPermission(), startEngine(engine) { engine.enabled = true }
        else {
            let alert = NSAlert()
            alert.messageText = "One permission. Smoother scrolling."
            alert.informativeText = "Allow SmoothWheel in System Settings → Privacy & Security → Accessibility, then enable smoothing here. If it is already allowed, quit and reopen the app."
            alert.addButton(withTitle: "Open Settings"); alert.addButton(withTitle: "Not Now")
            if let window = settings?.window, window.attachedSheet == nil {
                alert.beginSheetModal(for: window) { [weak self] response in
                    if response == .alertFirstButtonReturn { self?.openPermissions() }
                }
            }
        }
        refresh()
    }
    func loadSettings() {
        defaults.register(defaults: ["speed": ScrollPreset.balanced.speed, "smoothing": ScrollPreset.balanced.smoothing, "reversed": false])
        engine.speed = min(3, max(0.3, defaults.double(forKey: "speed")))
        engine.smoothing = min(1, max(0, defaults.double(forKey: "smoothing")))
        engine.reversed = defaults.bool(forKey: "reversed")
        engine.excluded = Set(defaults.stringArray(forKey: "excluded") ?? [])
    }
    @discardableResult func savePreset(name: String) throws -> SavedScrollPreset {
        let saved = try presetStore.save(name: name, configuration: configuration)
        settings?.synchronizeControls()
        return saved
    }
    func applySavedPreset(_ id: UUID) throws {
        guard let preset = presetStore.presets.first(where: { $0.id == id }) else { throw SavedPresetError.notFound }
        try presetStore.select(id)
        applyConfiguration(preset.configuration)
    }
    func applyBuiltInPreset(_ preset: ScrollPreset) throws {
        if presetStore.loadIssue == nil { try presetStore.select(nil) }
        applyConfiguration(ScrollConfiguration(speed: preset.speed, smoothing: preset.smoothing, reversed: engine.reversed))
    }
    private func applyConfiguration(_ value: ScrollConfiguration) {
        if configuration != value {
            engine.speed = value.speed; engine.smoothing = value.smoothing; engine.reversed = value.reversed
            saveSettings()
        } else {
            // Reapplying a preset retains the existing interruption contract,
            // even when its values already match, without redundant writes.
            engine.cancel()
        }
        settings?.synchronizeControls()
    }
    @objc func openPermissions() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
    func saveSettings() {
        engine.cancel()
        defaults.set(engine.speed, forKey: "speed"); defaults.set(engine.smoothing, forKey: "smoothing")
        defaults.set(engine.reversed, forKey: "reversed")
        defaults.set(Array(engine.excluded).sorted(), forKey: "excluded")
        updateInterface()
    }
    public func menuWillOpen(_ menu: NSMenu) {
        excludedApp = NSWorkspace.shared.frontmostApplication
        let id = excludedApp?.bundleIdentifier ?? ""
        excludeItem.isEnabled = !id.isEmpty && id != Bundle.main.bundleIdentifier
        excludeItem.title = "Exclude \(excludedApp?.localizedName ?? "Current App")"
        excludeItem.state = engine.excluded.contains(id) ? .on : .off
    }
    @objc func excludeCurrent() {
        guard let id = excludedApp?.bundleIdentifier else { return }
        if engine.excluded.contains(id) { engine.excluded.remove(id) } else { engine.excluded.insert(id) }
        saveSettings(); settings.reloadExclusions()
    }
    @objc func resetScrolling() {
        do {
            if presetStore.loadIssue == nil { try presetStore.select(nil) }
            applyConfiguration(ScrollConfiguration(speed: ScrollPreset.balanced.speed, smoothing: ScrollPreset.balanced.smoothing, reversed: false))
        } catch { settings?.showPresetError(error) }
    }
    @objc func showAbout() {
        let alert = NSAlert()
        alert.messageText = "SmoothWheel 0.3.17"
        alert.informativeText = "A familiar mouse. A smoother Mac.\n\nNative Swift and AppKit. MIT licensed. No accounts or analytics. Locally signed and not notarized. Physical hardware and app compatibility testing is ongoing."
        alert.addButton(withTitle: "Done")
        if let window = settings?.window { alert.beginSheetModal(for: window) }
    }
    @objc func quitApp() { engine.stop(); NSApp.terminate(nil) }
    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }
    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    public func applicationWillTerminate(_ notification: Notification) {
        healthTimer?.invalidate()
        engine.stop()
    }
}
