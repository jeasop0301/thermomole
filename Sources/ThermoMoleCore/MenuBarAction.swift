import Foundation

public enum MenuBarAction: CaseIterable, Identifiable, Sendable {
    public static let allCases = [MenuBarAction]()

    public var id: String {
        switch self {}
    }
}
