import Foundation
import ScrollCore

struct ScrollConfiguration: Codable, Equatable {
    var speed: Double
    var smoothing: Double
    var reversed: Bool

    func validate() throws {
        guard speed.isFinite, smoothing.isFinite, (0.3...3).contains(speed), (0...1).contains(smoothing) else {
            throw SavedPresetError.invalidValues
        }
    }
}

struct SavedScrollPreset: Codable, Equatable, Identifiable {
    let id: UUID
    var name: String
    var configuration: ScrollConfiguration

    static func validatedName(_ proposed: String, among presets: [Self], excluding id: UUID? = nil) throws -> String {
        let name = proposed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw SavedPresetError.emptyName }
        guard name.count <= 40 else { throw SavedPresetError.longName }
        guard !ScrollPreset.allCases.contains(where: { $0.rawValue.caseInsensitiveCompare(name) == .orderedSame }) else {
            throw SavedPresetError.reservedName
        }
        guard !presets.contains(where: { $0.id != id && $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
            throw SavedPresetError.duplicateName
        }
        return name
    }
}

enum SavedPresetError: Error, LocalizedError, Equatable {
    case emptyName, longName, reservedName, duplicateName, capacity, invalidValues, notFound, unreadable, unsupportedVersion

    var errorDescription: String? {
        switch self {
        case .emptyName: return "Enter a preset name."
        case .longName: return "Use 40 characters or fewer."
        case .reservedName: return "Choose a name different from the built-in presets."
        case .duplicateName: return "A preset with this name already exists."
        case .capacity: return "You can save up to 50 presets. Delete one before saving another."
        case .invalidValues: return "These scrolling values are outside the supported range."
        case .notFound: return "This preset is no longer available."
        case .unreadable: return "Saved presets could not be read. Your scrolling settings and original preset data are unchanged."
        case .unsupportedVersion: return "These presets were saved by a newer version of SmoothWheel. Their data has been kept unchanged."
        }
    }
}
