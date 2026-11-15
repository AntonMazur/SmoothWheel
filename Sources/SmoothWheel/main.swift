import AppKit
import ScrollCore
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let engine = ScrollEngine()
    let defaults = UserDefaults.standard
    var item: NSStatusItem!
    var settings: SettingsWindowController!
    var toggleItem: NSMenuItem!
    var excludeItem: NSMenuItem!
    var excludedApp: NSRunningApplication?
    var healthTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let iconURL = Bundle.main.url(forResource: "SmoothWheelIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = icon
        }
        defaults.register(defaults: ["speed": ScrollPreset.balanced.speed, "smoothing": ScrollPreset.balanced.smoothing, "reversed": false])
        engine.speed = min(3, max(0.3, defaults.double(forKey: "speed")))
        engine.smoothing = min(1, max(0, defaults.double(forKey: "smoothing")))
        engine.reversed = defaults.bool(forKey: "reversed")
        engine.excluded = Set(defaults.stringArray(forKey: "excluded") ?? [])
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
        settings = SettingsWindowController(coordinator: self)
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
        if engine.enabled && (!AXIsProcessTrusted() || !engine.running) { engine.enabled = false; engine.stop() }
        toggleItem.title = engine.enabled ? "Pause Smoothing" : "Enable Smoothing"
        item.button?.toolTip = engine.enabled ? "SmoothWheel — Active" : "SmoothWheel — Paused"
        if settings?.window?.isVisible == true { settings.refresh() }
    }
    @objc func toggle() {
        if engine.enabled { engine.enabled = false; engine.stop() }
        else if AXIsProcessTrusted(), engine.start() { engine.enabled = true }
        else {
            let alert = NSAlert()
            alert.messageText = "One permission. Smoother scrolling."
            alert.informativeText = "Allow SmoothWheel in System Settings → Privacy & Security → Accessibility, then enable smoothing here. If it is already allowed, quit and reopen the app."
            alert.addButton(withTitle: "Open Settings"); alert.addButton(withTitle: "Not Now")
            if let window = settings?.window {
                alert.beginSheetModal(for: window) { [weak self] response in
                    if response == .alertFirstButtonReturn { self?.openPermissions() }
                }
            }
        }
        refresh()
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
        refresh()
    }
    func menuWillOpen(_ menu: NSMenu) {
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
        engine.speed = ScrollPreset.balanced.speed
        engine.smoothing = ScrollPreset.balanced.smoothing
        engine.reversed = false
        saveSettings(); settings.synchronizeControls()
    }
    @objc func showAbout() {
        let alert = NSAlert()
        alert.messageText = "SmoothWheel 0.3.11"
        alert.informativeText = "A familiar mouse. A smoother Mac.\n\nNative Swift and AppKit. MIT licensed. No accounts or analytics. Locally signed and not notarized. Physical hardware and app compatibility testing is ongoing."
        alert.addButton(withTitle: "Done")
        if let window = settings?.window { alert.beginSheetModal(for: window) }
    }
    @objc func quitApp() { engine.stop(); NSApp.terminate(nil) }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) {
        healthTimer?.invalidate()
        engine.stop()
    }
}
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
