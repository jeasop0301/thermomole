import Foundation

public struct DiagnosticReport: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var generatedAt: Date
    public var appVersion: String
    public var snapshot: SystemSnapshot
    public var doctorReport: DoctorReport
    public var recentOperations: [OperationHistoryEntry]

    public init(
        schemaVersion: Int = 1,
        generatedAt: Date = Date(),
        appVersion: String,
        snapshot: SystemSnapshot,
        doctorReport: DoctorReport,
        recentOperations: [OperationHistoryEntry]
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.appVersion = appVersion
        self.snapshot = snapshot
        self.doctorReport = doctorReport
        self.recentOperations = recentOperations
    }
}

public struct DiagnosticReportSummary: Equatable, Sendable {
    public var appVersion: String
    public var schemaVersion: Int
    public var generatedAt: Date
    public var machine: String
    public var healthScore: Int
    public var doctorSummary: String
    public var recentOperationCount: Int

    public init(report: DiagnosticReport) {
        appVersion = report.appVersion
        schemaVersion = report.schemaVersion
        generatedAt = report.generatedAt
        machine = "\(report.snapshot.chipName) · \(report.snapshot.modelIdentifier)"
        healthScore = report.snapshot.health.value
        doctorSummary = report.doctorReport.summary
        recentOperationCount = report.recentOperations.count
    }
}

public struct DiagnosticReportStore: Sendable {
    public init() {}

    public static func encode(_ report: DiagnosticReport) throws -> Data {
        try JSONEncoder.thermoMole.encode(report)
    }

    public static func decode(_ data: Data) throws -> DiagnosticReport {
        try JSONDecoder.thermoMole.decode(DiagnosticReport.self, from: data)
    }

    public func write(_ report: DiagnosticReport, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try Self.encode(report)
        try data.write(to: url, options: .atomic)
    }

    public func read(from url: URL) throws -> DiagnosticReport {
        try Self.decode(Data(contentsOf: url))
    }
}

public extension JSONEncoder {
    static var thermoMole: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

public extension JSONDecoder {
    static var thermoMole: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
