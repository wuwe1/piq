import Foundation

enum SettingsStore {

    /// Load settings from a JSON file. Returns default settings if file is missing or invalid.
    static func load(from url: URL) -> Settings {
        guard let data = try? Data(contentsOf: url) else {
            return Settings()
        }
        let decoder = JSONDecoder()
        guard let settings = try? decoder.decode(Settings.self, from: data) else {
            return Settings()
        }
        return settings
    }

    /// Save settings to a JSON file. Returns true on success.
    @discardableResult
    static func save(_ settings: Settings, to url: URL) -> Bool {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(settings) else { return false }
        do {
            let dir = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }
}
