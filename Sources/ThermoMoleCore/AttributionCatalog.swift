import Foundation

public struct AttributionEntry: Equatable, Identifiable, Sendable {
    public var id: String { url }
    public var name: String
    public var url: String
    public var note: String

    public init(name: String, url: String, note: String) {
        self.name = name
        self.url = url
        self.note = note
    }
}

public struct AttributionCatalog: Equatable, Sendable {
    public var summary: String
    public var entries: [AttributionEntry]
    public var licenseNotice: String

    public init(summary: String, entries: [AttributionEntry], licenseNotice: String) {
        self.summary = summary
        self.entries = entries
        self.licenseNotice = licenseNotice
    }

    public static let `default` = AttributionCatalog(
        summary: "ThermoMole is an open-source macOS menu-bar utility for Apple Silicon, released under the GNU General Public License v3.0.",
        entries: [
            AttributionEntry(
                name: "MacMonitor",
                url: "https://github.com/ryyansafar/MacMonitor",
                note: "MacMonitor's SMC access pattern informed ThermoMole's native Apple Silicon thermal reader."
            ),
            AttributionEntry(
                name: "Mole",
                url: "https://github.com/tw93/mole",
                note: "Mole informed the five-tool product shape and review-first maintenance workflows."
            ),
            AttributionEntry(
                name: "Mole product site",
                url: "https://mole.fit/",
                note: "The product site informed the quiet, local-first utility positioning."
            )
        ],
        licenseNotice: "ThermoMole is distributed under the GNU General Public License v3.0. MacMonitor (MIT) and Mole (GPL-3.0) are listed as prior-art inspiration only; no code is copied from either project. All native sensor, SMC, and IOHIDEvent code is an independent reimplementation. GPL-3.0 satisfies any GPL-compatibility concern regarding Mole."
    )
}
