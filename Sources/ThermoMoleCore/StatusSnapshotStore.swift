import Foundation

public struct StatusSnapshotStore: Sendable {
    public var snapshotURL: URL

    public init(snapshotURL: URL = StatusSnapshotStore.defaultSnapshotURL) {
        self.snapshotURL = snapshotURL
    }

    public static var defaultSnapshotURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("ThermoMole", isDirectory: true)
            .appendingPathComponent("last-status.json")
    }

    public static var live: StatusSnapshotStore {
        StatusSnapshotStore()
    }

    public func save(_ snapshot: SystemSnapshot) throws {
        try FileManager.default.createDirectory(
            at: snapshotURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)
        try data.write(to: snapshotURL, options: .atomic)
    }

    public func load() throws -> SystemSnapshot? {
        guard FileManager.default.fileExists(atPath: snapshotURL.path) else { return nil }
        let data = try Data(contentsOf: snapshotURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(SystemSnapshot.self, from: data)
    }
}
