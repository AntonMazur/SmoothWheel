import Foundation

/// Bounded local preferences, owned by the settings coordinator on its main loop.
/// Commit encoded data before publishing state; never overwrite unreadable data.
final class SavedPresetStore {
    static let key = "savedScrollPresets"
    static let capacity = 50
    private struct Collection: Codable {
        var schemaVersion = 1
        var presets: [SavedScrollPreset] = []
        var activeID: UUID?
    }
    private let defaults: UserDefaults
    private var collection = Collection()
    private(set) var loadIssue: SavedPresetError?
    var presets: [SavedScrollPreset] { collection.presets }
    var activeID: UUID? { collection.activeID }
    var activePreset: SavedScrollPreset? { presets.first { $0.id == activeID } }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        guard defaults.object(forKey: Self.key) != nil else { return }
        do {
            guard let data = defaults.data(forKey: Self.key) else { throw SavedPresetError.unreadable }
            let loaded = try JSONDecoder().decode(Collection.self, from: data)
            guard loaded.schemaVersion == 1 else { throw SavedPresetError.unsupportedVersion }
            guard loaded.presets.count <= Self.capacity,
                  Set(loaded.presets.map(\.id)).count == loaded.presets.count,
                  loaded.activeID == nil || loaded.presets.contains(where: { $0.id == loaded.activeID }) else {
                throw SavedPresetError.unreadable
            }
            for preset in loaded.presets {
                try preset.configuration.validate()
                let name = try SavedScrollPreset.validatedName(preset.name, among: loaded.presets, excluding: preset.id)
                guard name == preset.name else { throw SavedPresetError.unreadable }
            }
            collection = loaded
        } catch {
            loadIssue = (error as? SavedPresetError) == .unsupportedVersion ? .unsupportedVersion : .unreadable
        }
    }

    func validateName(_ name: String, excluding id: UUID? = nil) throws {
        try requireReadable()
        _ = try SavedScrollPreset.validatedName(name, among: presets, excluding: id)
        if id == nil && presets.count >= Self.capacity { throw SavedPresetError.capacity }
    }

    @discardableResult func save(name: String, configuration: ScrollConfiguration) throws -> SavedScrollPreset {
        try validateName(name)
        try configuration.validate()
        let preset = SavedScrollPreset(id: UUID(), name: name.trimmingCharacters(in: .whitespacesAndNewlines), configuration: configuration)
        var next = collection
        next.presets.append(preset); next.activeID = preset.id
        try commit(next)
        return preset
    }

    func select(_ id: UUID?) throws {
        try requireReadable()
        guard id == nil || presets.contains(where: { $0.id == id }) else { throw SavedPresetError.notFound }
        guard collection.activeID != id else { return }
        var next = collection; next.activeID = id
        try commit(next)
    }

    func rename(_ id: UUID, to name: String) throws {
        try validateName(name, excluding: id)
        guard let index = presets.firstIndex(where: { $0.id == id }) else { throw SavedPresetError.notFound }
        var next = collection
        next.presets[index].name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        try commit(next)
    }

    func delete(_ id: UUID) throws {
        try requireReadable()
        guard presets.contains(where: { $0.id == id }) else { throw SavedPresetError.notFound }
        var next = collection; next.presets.removeAll { $0.id == id }
        if next.activeID == id { next.activeID = nil }
        try commit(next)
    }

    /// Call only after the user confirms resetting the unreadable collection.
    func resetCollection() throws {
        try commit(Collection()); loadIssue = nil
    }

    private func requireReadable() throws {
        if let loadIssue { throw loadIssue }
    }
    private func commit(_ next: Collection) throws {
        let data = try JSONEncoder().encode(next)
        defaults.set(data, forKey: Self.key)
        collection = next
    }
}
