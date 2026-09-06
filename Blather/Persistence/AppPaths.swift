import Foundation

enum AppPaths {
    static var overrideDataDirectory: URL?

    static var dataDirectory: URL {
        if let override = overrideDataDirectory {
            return override
        }
        if let override = ProcessInfo.processInfo.environment["BLATHER_DATA_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".blather", isDirectory: true)
    }

    static var databaseURL: URL {
        dataDirectory.appendingPathComponent("blather.db", isDirectory: false)
    }

    static var mediaDirectory: URL {
        dataDirectory.appendingPathComponent("media", isDirectory: true)
    }

    static func ensureDirectories() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
        try fm.createDirectory(at: mediaDirectory, withIntermediateDirectories: true)
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dataDirectory.path)
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: mediaDirectory.path)
    }
}

enum Time {
    static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func now() -> String {
        isoFormatter.string(from: Date())
    }

    static func newId() -> String {
        UUID().uuidString.lowercased()
    }
}

enum JSONCodec {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    static let decoder = JSONDecoder()

    static func encode<T: Encodable>(_ value: T) -> String {
        let data = try! encoder.encode(value)
        return String(data: data, encoding: .utf8)!
    }

    static func decode<T: Decodable>(_ type: T.Type, from string: String) -> T {
        try! decoder.decode(type, from: Data(string.utf8))
    }

    static func encodeOverrides(_ overrides: [Network: NetworkOverride]) -> String {
        var dict: [String: NetworkOverride] = [:]
        for (network, override) in overrides {
            dict[network.rawValue] = override
        }
        return encode(dict)
    }

    static func decodeOverrides(_ string: String) -> [Network: NetworkOverride] {
        let dict = decode([String: NetworkOverride].self, from: string)
        var result: [Network: NetworkOverride] = [:]
        for (key, value) in dict {
            if let network = Network(rawValue: key) {
                result[network] = value
            }
        }
        return result
    }
}
