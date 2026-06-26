import Foundation

final class ConfigStore: @unchecked Sendable {
    static let shared = ConfigStore()

    private let configURL: URL
    private let fileManager = FileManager.default

    private init() {
        let home = fileManager.homeDirectoryForCurrentUser
        configURL = home.appendingPathComponent(".handytab_config.json")
    }

    var targetGesture: String {
        string(for: "gesture") ?? "Open_Palm"
    }

    var targetURL: String {
        normalizeURL(string(for: "target_url") ?? "https://hsichen.dev")
    }

    var browser: String? {
        guard let value = string(for: "browser")?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty
        else {
            return nil
        }
        return value
    }

    var cameraEnabled: Bool {
        bool(for: "camera_trigger_enabled", defaultValue: false)
    }

    var trackpadEnabled: Bool {
        bool(for: "trackpad_tap_enabled", defaultValue: false)
    }

    var trackpadFingerCount: Int {
        let value = int(for: "trackpad_touch_count", defaultValue: 3)
        return Self.trackpadFingerOptions.contains(value) ? value : 3
    }

    static let trackpadFingerOptions = [2, 3, 4, 5]

    func setTargetURL(_ value: String) throws {
        try set("target_url", value: normalizeURL(value))
    }

    func setBrowser(_ value: String?) throws {
        let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        try set("browser", value: normalized?.isEmpty == false ? normalized : nil)
    }

    func setCameraEnabled(_ value: Bool) throws {
        try set("camera_trigger_enabled", value: value)
    }

    func setTrackpadEnabled(_ value: Bool) throws {
        try set("trackpad_tap_enabled", value: value)
    }

    func setTrackpadFingerCount(_ value: Int) throws {
        try set("trackpad_touch_count", value: Self.trackpadFingerOptions.contains(value) ? value : 3)
    }

    private func string(for key: String) -> String? {
        loadRaw()[key] as? String
    }

    private func bool(for key: String, defaultValue: Bool) -> Bool {
        loadRaw()[key] as? Bool ?? defaultValue
    }

    private func int(for key: String, defaultValue: Int) -> Int {
        if let value = loadRaw()[key] as? Int {
            return value
        }
        if let value = loadRaw()[key] as? Double {
            return Int(value)
        }
        return defaultValue
    }

    private func set(_ key: String, value: Any?) throws {
        var raw = loadRaw()
        if let value {
            raw[key] = value
        } else {
            raw.removeValue(forKey: key)
        }
        let data = try JSONSerialization.data(withJSONObject: raw, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: configURL, options: .atomic)
    }

    private func loadRaw() -> [String: Any] {
        guard let data = try? Data(contentsOf: configURL),
              let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return [:]
        }
        return value
    }

    private func normalizeURL(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "https://hsichen.dev"
        }
        if URLComponents(string: trimmed)?.scheme == nil {
            return "https://\(trimmed)"
        }
        return trimmed
    }
}
