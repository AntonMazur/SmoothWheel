import AppKit

/// Input callbacks read cached identities only. Workspace KVO includes background
/// services omitted by the ordinary application launch/termination notifications.
public final class ScrollRecipientRegistry {
    private var owners: [pid_t: String]
    private var observation: NSKeyValueObservation?

    public init(owners: [pid_t: String]) { self.owners = owners }

    public convenience init() {
        self.init(owners: [:])
        observation = NSWorkspace.shared.observe(\.runningApplications, options: [.initial, .new]) { [weak self] _, _ in
            if Thread.isMainThread { self?.refresh() }
            else { DispatchQueue.main.async { [weak self] in self?.refresh() } }
        }
    }

    public func owner(for processID: Int64) -> String? {
        precondition(Thread.isMainThread)
        guard processID > 0, let pid = pid_t(exactly: processID) else { return nil }
        return owners[pid]
    }

    private func refresh() {
        precondition(Thread.isMainThread)
        owners = Dictionary(NSWorkspace.shared.runningApplications.compactMap { app in
            app.bundleIdentifier.map { (app.processIdentifier, $0) }
        }, uniquingKeysWith: { _, latest in latest })
    }

    deinit { observation?.invalidate() }
}
